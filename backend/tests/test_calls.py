"""The puck call flow end to end, with stand-ins for Whisper and the model."""

import io
import time
import wave

import numpy as np
from fastapi.testclient import TestClient

from rambu.analyze import Analysis, AnalysisError, safety_net
from rambu.config import Settings
from rambu.main import create_app
from rambu.transcribe import SAMPLE_RATE, Segment

TOKEN = "dev-token"
LINES = [
    "This is Kevin from the fraud team at your bank.",
    "I'm sending a six-digit code to your phone. The code is 482913.",
    "Read it to me now, before the money leaves.",
]


def settings(tmp_path) -> Settings:
    return Settings(
        database_path=tmp_path / "test.sqlite3", openrouter_api_key="", openrouter_model="",
        whisper_model="", apns_team_id="", apns_key_id="", apns_key_path="",
        apns_bundle_id="id.rambu.app", dev_puck_token=TOKEN,
    )


class ScriptedTranscriber:
    """Piece n of the call is a tone of amplitude 0.1·(n+1) and 'says' LINES[n]."""

    def transcribe(self, pcm, language):
        segments = []
        for i in range(int(len(pcm) / SAMPLE_RATE // 3)):
            mid = int((i * 3 + 1.5) * SAMPLE_RATE)
            piece = round(float(np.max(np.abs(pcm[mid - 800:mid + 800]))) / 0.1) - 1
            if piece >= 0:
                segments.append(Segment(i * 3.0, i * 3.0 + 2.5, LINES[piece % len(LINES)]))
        return segments


class KeywordAnalyzer:
    def __init__(self, fail=False):
        self.fail = fail
        self.calls = []

    def analyze(self, transcript, mode, language):
        self.calls.append((mode, transcript))
        if self.fail:
            raise AnalysisError("model down")
        hits = safety_net(transcript)
        if hits:
            return Analysis(level="high_risk", signals=["secret_code"], evidence=hits)
        return Analysis(level="low")


class Recorder:
    def __init__(self):
        self.events = []

    def session_started(self, session):
        self.events.append(("started", session["id"]))

    def risk_raised(self, session, alert, analysis):
        self.events.append(("risk", analysis.level))

    def session_ended(self, session, alert):
        self.events.append(("ended", session["status"]))


def tone(seconds: float, amplitude: float = 0.1) -> bytes:
    t = np.arange(int(seconds * SAMPLE_RATE)) / SAMPLE_RATE
    pcm = amplitude * np.sin(2 * np.pi * 440 * t)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes((pcm * 32767).astype("<i2").tobytes())
    return buffer.getvalue()


def run_call(client, pieces):
    auth = {"Authorization": f"Bearer {TOKEN}"}
    session_id = client.post("/api/puck/sessions", headers=auth).json()["sessionId"]
    for piece in pieces:
        r = client.post(f"/api/puck/sessions/{session_id}/chunks", content=piece,
                        headers={**auth, "Content-Type": "audio/wav"})
        assert r.status_code == 202
    assert client.post(f"/api/puck/sessions/{session_id}/end", headers=auth).status_code == 202
    for _ in range(100):
        status = client.get(f"/api/puck/sessions/{session_id}", headers=auth).json()
        if status["status"] != "listening":
            return status
        time.sleep(0.05)
    raise AssertionError("call never finished")


def test_scam_call_is_flagged_masked_and_finished(tmp_path):
    notifier = Recorder()
    app = create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), notifier)
    with TestClient(app) as client:
        status = run_call(client, [tone(3.0, 0.1 * (n + 1)) for n in range(4)])
    assert status["status"] == "completed"
    assert status["level"] == "high_risk"
    assert status["evidence"][0]["quote"] == "Read it to me now, before the money leaves."
    assert "482913" not in status["transcript"] and "•••" in status["transcript"]
    assert ("risk", "high_risk") in notifier.events
    assert notifier.events[-1] == ("ended", "completed")


def test_silent_call_is_no_speech(tmp_path):
    app = create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), Recorder())
    with TestClient(app) as client:
        status = run_call(client, [tone(3.0, 0.0) for _ in range(2)])
    assert status["status"] == "no_speech"
    assert status["level"] == "low"


def test_model_failure_is_never_reported_safe(tmp_path):
    class Hears(ScriptedTranscriber):
        def transcribe(self, pcm, language):
            return [Segment(0.0, 1.0, "Hello, it's your neighbour.")] if len(pcm) else []

    app = create_app(settings(tmp_path), Hears(), KeywordAnalyzer(fail=True), Recorder())
    with TestClient(app) as client:
        status = run_call(client, [tone(3.0)])
    assert status["status"] == "failed"
    assert status["failure_reason"] == "analysis failed"


def test_unknown_puck_is_rejected(tmp_path):
    app = create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), Recorder())
    with TestClient(app) as client:
        assert client.post("/api/puck/sessions", headers={"Authorization": "Bearer nope"}).status_code == 401
