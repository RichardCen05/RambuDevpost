"""Rambu API. Start with: uv run uvicorn rambu.main:create_app --factory --port 8001 --env-file .env"""

import logging
import threading
from contextlib import asynccontextmanager

from fastapi import Body, FastAPI, Header, HTTPException, Request

from . import alerts, families
from .analyze import ScamAnalyzer
from .push import APNs, FamilyNotifier
from .auth import bearer, hash_token
from .config import Settings, load_settings
from .db import Database
from .pipeline import Analyzer, CallManager, Notifier, Transcriber
from .transcribe import SAMPLE_RATE, WhisperTranscriber, decode_wav

DEV_PUCK_ID = "dev-puck"


def ensure_dev_puck(db: Database, token: str) -> None:
    """A puck usable without app pairing, for the fake puck script and serial-configured hardware."""
    if db.puck_by_token(hash_token(token)):
        return
    db.execute("DELETE FROM pucks WHERE id = ?", (DEV_PUCK_ID,))
    db.create_puck(db.create_family(), hash_token(token), puck_id=DEV_PUCK_ID)


def create_app(
    settings: Settings | None = None,
    transcriber: Transcriber | None = None,
    analyzer: Analyzer | None = None,
    notifier: Notifier | None = None,
) -> FastAPI:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    settings = settings or load_settings()
    db = Database(settings.database_path)
    transcriber = transcriber or WhisperTranscriber(settings.whisper_model)
    analyzer = analyzer or ScamAnalyzer(settings.openrouter_api_key, settings.openrouter_model)
    notifier = notifier or FamilyNotifier(db, APNs(settings))
    calls = CallManager(db, transcriber, analyzer, notifier)
    if settings.dev_puck_token:
        ensure_dev_puck(db, settings.dev_puck_token)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        warm_up = getattr(transcriber, "warm_up", None)
        if warm_up:
            threading.Thread(target=warm_up, name="whisper-warm-up", daemon=True).start()
        yield

    app = FastAPI(title="Rambu", lifespan=lifespan)
    app.state.db = db
    app.state.calls = calls
    app.state.settings = settings
    families.register(app, db)
    alerts.register(app, db, notifier)

    def puck_from(authorization: str | None) -> dict:
        token = bearer(authorization)
        puck = db.puck_by_token(hash_token(token)) if token else None
        if not puck:
            raise HTTPException(401, "unknown puck")
        return puck

    def puck_session(session_id: str, puck: dict) -> dict:
        session = db.session(session_id)
        if not session or session["puck_id"] != puck["id"]:
            raise HTTPException(404, "unknown session")
        return session

    @app.get("/health")
    def health():
        return {"ok": True}

    # Puck ---------------------------------------------------------------

    @app.post("/api/puck/hello")
    def puck_hello(body: dict | None = Body(default=None), authorization: str | None = Header(default=None)):
        puck = puck_from(authorization)
        db.touch_puck(puck["id"], (body or {}).get("firmware"))
        return {"puckId": puck["id"]}

    @app.post("/api/puck/sessions", status_code=201)
    def start_session(body: dict | None = Body(default=None), authorization: str | None = Header(default=None)):
        puck = puck_from(authorization)
        db.touch_puck(puck["id"])
        parent = db.parent_of(puck["family_id"])
        if parent:
            language = parent["language"]
        else:  # dev puck without a family: the caller may pick the language for testing
            language = (body or {}).get("language", "en")
        if language not in ("en", "id"):
            raise HTTPException(400, "language must be en or id")
        session = calls.start(puck["family_id"], puck["id"], language)
        return {"sessionId": session["id"], "language": language}

    @app.post("/api/puck/sessions/{session_id}/chunks", status_code=202)
    async def add_chunk(session_id: str, request: Request, authorization: str | None = Header(default=None)):
        puck = puck_from(authorization)
        session = puck_session(session_id, puck)
        worker = calls.worker(session_id)
        if session["status"] != "listening" or worker is None:
            raise HTTPException(409, "session is not listening")
        try:
            pcm = decode_wav(await request.body())
        except Exception as exc:
            raise HTTPException(400, f"bad audio: {exc}") from exc
        worker.add_audio(pcm)
        return {"seconds": round(len(pcm) / SAMPLE_RATE, 2)}

    @app.post("/api/puck/sessions/{session_id}/end", status_code=202)
    def end_session(session_id: str, authorization: str | None = Header(default=None)):
        puck = puck_from(authorization)
        puck_session(session_id, puck)
        calls.end(session_id)
        return {"ending": True}

    @app.get("/api/puck/sessions/{session_id}")
    def session_status(session_id: str, authorization: str | None = Header(default=None)):
        """Debug view for the fake puck and hardware tests."""
        puck = puck_from(authorization)
        session = puck_session(session_id, puck)
        worker = calls.worker(session_id)
        first_warning = None
        if worker and worker.first_warning_at is not None:
            first_warning = round(worker.first_warning_at - worker.started_at, 1)
        return {
            **session,
            "transcript": " ".join(s["text_masked"] for s in db.segments(session_id)),
            "firstWarningAfterSeconds": first_warning,
        }

    return app
