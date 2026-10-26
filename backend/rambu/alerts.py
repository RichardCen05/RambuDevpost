"""Alerts, caregiver decisions, and call history."""

from datetime import datetime

from fastapi import Body, FastAPI, Header, HTTPException

from .auth import hash_token, new_token
from .db import Database, utc_now
from .families import _parse, device_from


def decision_view(db: Database, row: dict) -> dict | None:
    if not row or not row.get("verdict"):
        return None
    decider = db.one("SELECT id, name FROM devices WHERE id = ?", (row["decided_by"],))
    return {"verdict": row["verdict"], "byId": row["decided_by"], "byName": decider["name"] if decider else "",
            "at": row["decided_at"]}


def alert_view(db: Database, alert: dict) -> dict:
    session = db.session(alert["session_id"])
    parent = db.parent_of(session["family_id"])
    caregivers = db.all("SELECT id, name FROM devices WHERE family_id = ? AND role = 'caregiver' AND status = 'active' "
                        "ORDER BY created_at", (session["family_id"],))
    return {
        "id": alert["id"],
        "sessionId": alert["session_id"],
        "parentName": parent["name"] if parent else "",
        "level": alert["level"],
        "signals": alert["signals"],
        "evidence": alert["evidence"],
        "raisedAt": alert["raised_at"],
        "callEnded": bool(alert["call_ended"]),
        "decision": decision_view(db, alert),
        "recipients": [{"id": c["id"], "name": c["name"]} for c in caregivers],
    }


def call_view(db: Database, session: dict, *, with_transcript: bool = False) -> dict:
    alert = db.alert_for_session(session["id"])
    duration = None
    if session["ended_at"]:
        duration = int((_parse(session["ended_at"]) - _parse(session["started_at"])).total_seconds())
    view = {
        "id": session["id"],
        "startedAt": session["started_at"],
        "endedAt": session["ended_at"],
        "durationSeconds": duration,
        "status": session["status"],
        "level": session["level"],
        "signals": session["signals"],
        "evidence": session["evidence"],
        "decision": decision_view(db, alert),
        "failureReason": session["failure_reason"],
        "transcript": None,
    }
    if with_transcript:
        view["transcript"] = " ".join(s["text_masked"] for s in db.segments(session["id"]))
    return view


def active_call(db: Database, family_id: str) -> dict | None:
    session = db.one("SELECT * FROM sessions WHERE family_id = ? AND status = 'listening' ORDER BY started_at DESC",
                     (family_id,))
    if not session:
        return None
    alert = db.alert_for_session(session["id"])
    return {"sessionId": session["id"], "startedAt": session["started_at"], "level": session["level"],
            "alertId": alert["id"] if alert else None}


def register(app: FastAPI, db: Database, notifier) -> None:
    def family_alert(alert_id: str, device: dict) -> dict:
        alert = db.one("SELECT alerts.* FROM alerts JOIN sessions ON sessions.id = alerts.session_id "
                       "WHERE alerts.id = ? AND sessions.family_id = ?", (alert_id, device["family_id"]))
        if not alert:
            raise HTTPException(404, "unknown alert")
        return alert

    @app.get("/api/alerts")
    def list_alerts(authorization: str | None = Header(default=None)):
        device = device_from(db, authorization)
        rows = db.all("SELECT alerts.* FROM alerts JOIN sessions ON sessions.id = alerts.session_id "
                      "WHERE sessions.family_id = ? ORDER BY alerts.raised_at DESC LIMIT 50", (device["family_id"],))
        return [alert_view(db, row) for row in rows]

    @app.get("/api/alerts/{alert_id}")
    def get_alert(alert_id: str, authorization: str | None = Header(default=None)):
        device = device_from(db, authorization)
        return alert_view(db, family_alert(alert_id, device))

    @app.post("/api/alerts/{alert_id}/decision")
    def decide(alert_id: str, body: dict = Body(...), authorization: str | None = Header(default=None)):
        device = device_from(db, authorization, role="caregiver")
        verdict = body.get("verdict")
        if verdict not in ("scam", "safe"):
            raise HTTPException(400, "verdict must be scam or safe")
        family_alert(alert_id, device)
        with db.transaction():
            current = db.one("SELECT * FROM alerts WHERE id = ?", (alert_id,))
            accepted = current["verdict"] is None
            if accepted:  # first answer wins
                db.execute("UPDATE alerts SET verdict = ?, decided_by = ?, decided_at = ? WHERE id = ?",
                           (verdict, device["id"], utc_now(), alert_id))
        alert = db.one("SELECT * FROM alerts WHERE id = ?", (alert_id,))
        if accepted:
            notifier.verdict(alert, device)
        return {"alert": alert_view(db, alert), "accepted": accepted}

    @app.get("/api/history")
    def history(authorization: str | None = Header(default=None)):
        device = device_from(db, authorization)
        rows = db.all("SELECT * FROM sessions WHERE family_id = ? ORDER BY started_at DESC LIMIT 100",
                      (device["family_id"],))
        return [call_view(db, row) for row in rows]

    @app.get("/api/history/{session_id}")
    def call_detail(session_id: str, authorization: str | None = Header(default=None)):
        device = device_from(db, authorization)
        session = db.session(session_id)
        if not session or session["family_id"] != device["family_id"]:
            raise HTTPException(404, "unknown call")
        return call_view(db, session, with_transcript=device["role"] == "parent")

    @app.post("/api/pucks/claim", status_code=201)
    def claim_puck(body: dict = Body(...)):
        """Pairs a stand-in puck (Mac) with the family whose invite code is currently shown on the parent's phone."""
        invite = db.one("SELECT * FROM invites WHERE code = ?", (str(body.get("code", "")).strip(),))
        if not invite or _parse(invite["expires_at"]) <= datetime.now(_parse(invite["expires_at"]).tzinfo):
            raise HTTPException(404, "code not found or expired")
        token = new_token()
        puck_id = db.create_puck(invite["family_id"], hash_token(token))
        db.touch_puck(puck_id, "mac-stand-in")
        return {"puckId": puck_id, "puckToken": token}
