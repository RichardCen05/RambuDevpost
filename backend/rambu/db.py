"""SQLite storage. One connection guarded by a lock: FastAPI runs sync routes in a thread pool."""

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS families (
    id TEXT PRIMARY KEY,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL REFERENCES families(id),
    role TEXT NOT NULL CHECK (role IN ('parent', 'caregiver')),
    status TEXT NOT NULL CHECK (status IN ('pending', 'active')),
    name TEXT NOT NULL,
    relationship TEXT,
    language TEXT NOT NULL DEFAULT 'en',
    token_hash TEXT NOT NULL UNIQUE,
    apns_token TEXT,
    apns_env TEXT,
    la_start_token TEXT,
    la_update_token TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY,
    family_id TEXT NOT NULL REFERENCES families(id),
    expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS pucks (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL REFERENCES families(id),
    token_hash TEXT NOT NULL UNIQUE,
    firmware TEXT,
    last_seen_at TEXT
);
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL REFERENCES families(id),
    puck_id TEXT NOT NULL REFERENCES pucks(id),
    language TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('listening', 'completed', 'no_speech', 'failed')),
    failure_reason TEXT,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    level TEXT NOT NULL DEFAULT 'low',
    signals TEXT NOT NULL DEFAULT '[]',
    evidence TEXT NOT NULL DEFAULT '[]'
);
CREATE TABLE IF NOT EXISTS segments (
    session_id TEXT NOT NULL REFERENCES sessions(id),
    seq INTEGER NOT NULL,
    offset_s REAL NOT NULL,
    text_masked TEXT NOT NULL,
    PRIMARY KEY (session_id, seq)
);
CREATE TABLE IF NOT EXISTS alerts (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES sessions(id),
    level TEXT NOT NULL,
    signals TEXT NOT NULL,
    evidence TEXT NOT NULL,
    raised_at TEXT NOT NULL,
    verdict TEXT CHECK (verdict IN ('scam', 'safe')),
    decided_by TEXT REFERENCES devices(id),
    decided_at TEXT,
    call_ended INTEGER NOT NULL DEFAULT 0
);
"""

JSON_COLUMNS = {"signals", "evidence"}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_id() -> str:
    return uuid.uuid4().hex


def _row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    out = dict(row)
    for key in JSON_COLUMNS & out.keys():
        out[key] = json.loads(out[key])
    return out


class Database:
    def __init__(self, path: Path | str):
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.execute("PRAGMA journal_mode = WAL")
        self._conn.executescript(SCHEMA)
        self.lock = threading.RLock()

    def execute(self, sql: str, params: tuple | dict = ()) -> sqlite3.Cursor:
        with self.lock:
            return self._conn.execute(sql, params)

    def one(self, sql: str, params: tuple | dict = ()) -> dict[str, Any] | None:
        with self.lock:
            return _row(self._conn.execute(sql, params).fetchone())

    def all(self, sql: str, params: tuple | dict = ()) -> list[dict[str, Any]]:
        with self.lock:
            return [_row(r) for r in self._conn.execute(sql, params).fetchall()]

    def transaction(self):
        """Use as `with db.transaction():` for multi-statement atomic writes."""
        return _Transaction(self)

    # Families and pucks -------------------------------------------------

    def create_family(self) -> str:
        family_id = new_id()
        self.execute("INSERT INTO families (id, created_at) VALUES (?, ?)", (family_id, utc_now()))
        return family_id

    def create_puck(self, family_id: str, token_hash: str, puck_id: str | None = None) -> str:
        puck_id = puck_id or new_id()
        self.execute(
            "INSERT INTO pucks (id, family_id, token_hash) VALUES (?, ?, ?)",
            (puck_id, family_id, token_hash),
        )
        return puck_id

    def puck_by_token(self, token_hash: str) -> dict[str, Any] | None:
        return self.one("SELECT * FROM pucks WHERE token_hash = ?", (token_hash,))

    def touch_puck(self, puck_id: str, firmware: str | None = None) -> None:
        self.execute(
            "UPDATE pucks SET last_seen_at = ?, firmware = COALESCE(?, firmware) WHERE id = ?",
            (utc_now(), firmware, puck_id),
        )

    def parent_of(self, family_id: str) -> dict[str, Any] | None:
        return self.one("SELECT * FROM devices WHERE family_id = ? AND role = 'parent'", (family_id,))

    # Sessions -----------------------------------------------------------

    def create_session(self, family_id: str, puck_id: str, language: str) -> dict[str, Any]:
        session_id = new_id()
        self.execute(
            "INSERT INTO sessions (id, family_id, puck_id, language, status, started_at) "
            "VALUES (?, ?, ?, ?, 'listening', ?)",
            (session_id, family_id, puck_id, language, utc_now()),
        )
        return self.session(session_id)

    def session(self, session_id: str) -> dict[str, Any] | None:
        return self.one("SELECT * FROM sessions WHERE id = ?", (session_id,))

    def add_segment(self, session_id: str, seq: int, offset_s: float, text_masked: str) -> None:
        self.execute(
            "INSERT INTO segments (session_id, seq, offset_s, text_masked) VALUES (?, ?, ?, ?)",
            (session_id, seq, offset_s, text_masked),
        )

    def segments(self, session_id: str) -> list[dict[str, Any]]:
        return self.all("SELECT * FROM segments WHERE session_id = ? ORDER BY seq", (session_id,))

    def set_session_risk(self, session_id: str, level: str, signals: list, evidence: list) -> None:
        self.execute(
            "UPDATE sessions SET level = ?, signals = ?, evidence = ? WHERE id = ?",
            (level, json.dumps(signals), json.dumps(evidence, ensure_ascii=False), session_id),
        )

    def finish_session(self, session_id: str, status: str, failure_reason: str | None = None) -> None:
        self.execute(
            "UPDATE sessions SET status = ?, failure_reason = ?, ended_at = ? WHERE id = ?",
            (status, failure_reason, utc_now(), session_id),
        )

    # Alerts -------------------------------------------------------------

    def upsert_alert(self, session_id: str, level: str, signals: list, evidence: list) -> dict[str, Any]:
        with self.transaction():
            existing = self.one("SELECT * FROM alerts WHERE session_id = ?", (session_id,))
            if existing:
                self.execute(
                    "UPDATE alerts SET level = ?, signals = ?, evidence = ? WHERE id = ?",
                    (level, json.dumps(signals), json.dumps(evidence, ensure_ascii=False), existing["id"]),
                )
                alert_id = existing["id"]
            else:
                alert_id = new_id()
                self.execute(
                    "INSERT INTO alerts (id, session_id, level, signals, evidence, raised_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (alert_id, session_id, level, json.dumps(signals),
                     json.dumps(evidence, ensure_ascii=False), utc_now()),
                )
        return self.one("SELECT * FROM alerts WHERE id = ?", (alert_id,))

    def alert_for_session(self, session_id: str) -> dict[str, Any] | None:
        return self.one("SELECT * FROM alerts WHERE session_id = ?", (session_id,))

    def mark_alert_call_ended(self, session_id: str) -> None:
        self.execute("UPDATE alerts SET call_ended = 1 WHERE session_id = ?", (session_id,))


class _Transaction:
    def __init__(self, db: Database):
        self.db = db

    def __enter__(self):
        self.db.lock.acquire()
        self.db._conn.execute("BEGIN IMMEDIATE")
        return self.db

    def __exit__(self, exc_type, exc, tb):
        try:
            self.db._conn.execute("ROLLBACK" if exc_type else "COMMIT")
        finally:
            self.db.lock.release()
        return False
