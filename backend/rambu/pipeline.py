"""Per-call worker: audio pieces in, transcript + live risk out.

Each call gets one worker thread so its transcript stays in order. Uploads only append audio and
return at once; the worker coalesces whatever has arrived, so a slow model never backs up the puck.

Whisper sees the not-yet-committed tail of the audio each time. Segments that end more than
COMMIT_MARGIN seconds before the edge are committed (stored); the rest is re-heard next round, so
words cut at a piece boundary are not lost.
"""

import logging
import threading
import time
from typing import Protocol

import numpy as np

from .analyze import Analysis, AnalysisError, level_rank
from .db import Database
from .mask import mask_sensitive
from .transcribe import SAMPLE_RATE, Segment, rms

log = logging.getLogger("rambu.pipeline")

COMMIT_MARGIN = 1.0
FORCE_COMMIT_AFTER = 12.0
SILENCE_RMS = 0.002
MIN_WINDOW = 0.8


class Transcriber(Protocol):
    def transcribe(self, pcm: np.ndarray, language: str) -> list[Segment]: ...


class Analyzer(Protocol):
    def analyze(self, transcript: str, mode: str, language: str) -> Analysis: ...


class Notifier(Protocol):
    def session_started(self, session: dict) -> None: ...
    def risk_raised(self, session: dict, alert: dict, analysis: Analysis) -> None: ...
    def session_ended(self, session: dict, alert: dict | None) -> None: ...


class LogNotifier:
    def session_started(self, session: dict) -> None:
        log.info("session %s started", session["id"])

    def risk_raised(self, session: dict, alert: dict, analysis: Analysis) -> None:
        log.info("session %s risk %s %s", session["id"], analysis.level, analysis.signals)

    def session_ended(self, session: dict, alert: dict | None) -> None:
        log.info("session %s ended: %s", session["id"], session["status"])


def _norm(text: str) -> str:
    return " ".join(text.lower().split())


def merge_evidence(old: list[dict], new: list[dict]) -> list[dict]:
    """Union of quotes across live checks. A quote contained in another is folded into the longer one,
    so the caregiver doesn't see the same sentence twice from overlapping audio windows."""
    merged = [dict(e) for e in old]
    for item in new:
        item = {"quote": item["quote"], "signals": list(item["signals"])}
        inside = next((e for e in merged if _norm(item["quote"]) in _norm(e["quote"])), None)
        if inside:
            inside["signals"] = sorted(set(inside["signals"]) | set(item["signals"]))
            continue
        covered = [e for e in merged if _norm(e["quote"]) in _norm(item["quote"])]
        for e in covered:
            item["signals"] = sorted(set(item["signals"]) | set(e["signals"]))
            merged.remove(e)
        merged.append(item)
    return merged


class CallWorker:
    def __init__(self, session: dict, db: Database, transcriber: Transcriber, analyzer: Analyzer, notifier: Notifier):
        self.session_id = session["id"]
        self.language = session["language"]
        self.db = db
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.notifier = notifier

        self._cond = threading.Condition()
        self._incoming: list[np.ndarray] = []
        self._ended = False
        self._audio = np.zeros(0, dtype=np.float32)
        self._committed_until = 0.0
        self._committed: list[str] = []
        self._tentative = ""
        self._seq = 0
        self._last_analyzed = ""
        self._level = "low"
        self._signals: list[str] = []
        self._evidence: list[dict] = []
        self._failure: str | None = None
        self._heard_speech = False
        self.started_at = time.monotonic()
        self.first_warning_at: float | None = None
        self.done = threading.Event()
        self._thread = threading.Thread(target=self._run, name=f"call-{self.session_id[:8]}", daemon=True)
        self._thread.start()

    # Called from request threads ------------------------------------------

    def add_audio(self, pcm: np.ndarray) -> None:
        with self._cond:
            if self._ended:
                return
            self._incoming.append(pcm)
            self._cond.notify()

    def end(self) -> None:
        with self._cond:
            self._ended = True
            self._cond.notify()

    @property
    def transcript(self) -> str:
        return " ".join([*self._committed, self._tentative]).strip()

    # Worker thread ---------------------------------------------------------

    def _run(self) -> None:
        try:
            while True:
                with self._cond:
                    while not self._incoming and not self._ended:
                        self._cond.wait()
                    pieces, self._incoming = self._incoming, []
                    final = self._ended
                if pieces:
                    self._audio = np.concatenate([self._audio, *pieces])
                self._hear(final)
                if final:
                    self._finish()
                    return
                self._analyze("live")
        except Exception:  # never leave a call stuck in "listening"
            log.exception("call worker crashed")
            self._failure = self._failure or "internal error"
            self._finish(crashed=True)
        finally:
            self.done.set()

    def _hear(self, final: bool) -> None:
        start = int(self._committed_until * SAMPLE_RATE)
        window = self._audio[start:]
        duration = len(window) / SAMPLE_RATE
        if duration < MIN_WINDOW and not final:
            return
        if not len(window):
            self._tentative = ""
            return
        if rms(window) < SILENCE_RMS:
            if duration > 3.0 or final:
                self._committed_until += duration - (0 if final else COMMIT_MARGIN)
                self._tentative = ""
            return
        try:
            segments = self.transcriber.transcribe(window, self.language)
        except Exception as exc:
            log.warning("transcription failed: %s", exc)
            self._failure = "transcription failed"
            return
        edge = duration if final else duration - COMMIT_MARGIN
        commit = [s for s in segments if s.end <= edge]
        if not commit and duration > FORCE_COMMIT_AFTER and segments:
            commit = segments[:-1] or segments
        for seg in commit:
            text = mask_sensitive(seg.text)
            self.db.add_segment(self.session_id, self._seq, self._committed_until + seg.start, text)
            self._committed.append(text)
            self._seq += 1
            self._heard_speech = True
        rest = segments[len(commit):]
        self._tentative = " ".join(mask_sensitive(s.text) for s in rest)
        if rest:
            self._heard_speech = True
        if commit:
            self._committed_until += commit[-1].end
        elif not segments and duration > 6.0:
            self._committed_until += duration - COMMIT_MARGIN

    def _analyze(self, mode: str) -> bool:
        transcript = self.transcript
        if not transcript or (mode == "live" and transcript == self._last_analyzed):
            return True
        self._last_analyzed = transcript
        try:
            result = self.analyzer.analyze(transcript, mode, self.language)
        except AnalysisError as exc:
            log.warning("analysis failed: %s", exc)
            self._failure = "analysis failed"
            return False
        if result.level == "low":
            return True
        raised = level_rank(result.level) > level_rank(self._level)
        self._level = max(self._level, result.level, key=level_rank)
        self._evidence = merge_evidence(self._evidence, result.evidence)
        self._signals = sorted({s for e in self._evidence for s in e["signals"]})
        self.db.set_session_risk(self.session_id, self._level, self._signals, self._evidence)
        alert = self.db.upsert_alert(self.session_id, self._level, self._signals, self._evidence)
        if raised:
            if self.first_warning_at is None:
                self.first_warning_at = time.monotonic()
            self.notifier.risk_raised(self.db.session(self.session_id), alert, result)
        return True

    def _finish(self, crashed: bool = False) -> None:
        analyzed = False if crashed else self._analyze("final")
        if not self._heard_speech:
            status, reason = ("failed", self._failure) if self._failure else ("no_speech", None)
        elif self._level != "low" or analyzed:
            # A warning already sent stands even if the last check failed; never fall back to safe.
            status, reason = "completed", None
        else:
            status, reason = "failed", self._failure or "analysis failed"
        self.db.finish_session(self.session_id, status, reason)
        self.db.mark_alert_call_ended(self.session_id)
        self.notifier.session_ended(self.db.session(self.session_id), self.db.alert_for_session(self.session_id))


class CallManager:
    def __init__(self, db: Database, transcriber: Transcriber, analyzer: Analyzer, notifier: Notifier):
        self.db = db
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.notifier = notifier
        self._workers: dict[str, CallWorker] = {}
        self._lock = threading.Lock()

    def start(self, family_id: str, puck_id: str, language: str) -> dict:
        session = self.db.create_session(family_id, puck_id, language)
        with self._lock:
            self._workers[session["id"]] = CallWorker(session, self.db, self.transcriber, self.analyzer, self.notifier)
        self.notifier.session_started(session)
        return session

    def worker(self, session_id: str) -> CallWorker | None:
        with self._lock:
            return self._workers.get(session_id)

    def end(self, session_id: str) -> None:
        worker = self.worker(session_id)
        if worker:
            worker.end()
