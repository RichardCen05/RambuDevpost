"""Families: the parent creates one, caregivers join with a six-digit code and the parent's Allow.

No accounts: each phone holds a random device token (iPhone Keychain); the backend stores its hash.
"""

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import Body, FastAPI, Header, HTTPException

from .auth import bearer, hash_token, new_token
from .db import Database, new_id, utc_now

INVITE_MINUTES = 15
PUCK_ONLINE_SECONDS = 150
LANGUAGES = ("en", "id")


def _parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _language(value) -> str:
    if value not in LANGUAGES:
        raise HTTPException(400, "language must be en or id")
    return value


def _name(value) -> str:
    name = str(value or "").strip()
    if not name or len(name) > 60:
        raise HTTPException(400, "name is required (max 60 characters)")
    return name


def new_invite(db: Database, family_id: str) -> dict:
    with db.transaction():
        db.execute("DELETE FROM invites WHERE family_id = ?", (family_id,))
        while True:
            code = f"{secrets.randbelow(1_000_000):06d}"
            if not db.one("SELECT code FROM invites WHERE code = ?", (code,)):
                break
        expires = _iso(datetime.now(timezone.utc) + timedelta(minutes=INVITE_MINUTES))
        db.execute("INSERT INTO invites (code, family_id, expires_at) VALUES (?, ?, ?)", (code, family_id, expires))
    return {"code": code, "expiresAt": expires}


def device_from(db: Database, authorization: str | None, *, role: str | None = None, active: bool = True) -> dict:
    token = bearer(authorization)
    device = db.one("SELECT * FROM devices WHERE token_hash = ?", (hash_token(token),)) if token else None
    if not device:
        raise HTTPException(401, "unknown device")
    if active and device["status"] != "active":
        raise HTTPException(403, "waiting for the parent to allow this device")
    if role and device["role"] != role:
        raise HTTPException(403, f"only the {role} can do this")
    return device


def member_view(device: dict) -> dict:
    return {
        "id": device["id"],
        "role": device["role"],
        "status": device["status"],
        "name": device["name"],
        "relationship": device["relationship"],
        "language": device["language"],
    }


def puck_view(puck: dict | None) -> dict | None:
    if not puck:
        return None
    online = bool(puck["last_seen_at"]) and (
        datetime.now(timezone.utc) - _parse(puck["last_seen_at"])
    ).total_seconds() < PUCK_ONLINE_SECONDS
    return {"id": puck["id"], "online": online, "lastSeenAt": puck["last_seen_at"], "firmware": puck["firmware"]}


def family_view(db: Database, device: dict) -> dict:
    from .alerts import active_call  # alerts imports this module
    family_id = device["family_id"]
    members = db.all("SELECT * FROM devices WHERE family_id = ? ORDER BY created_at", (family_id,))
    invite = None
    if device["role"] == "parent":
        row = db.one("SELECT * FROM invites WHERE family_id = ?", (family_id,))
        if row and _parse(row["expires_at"]) > datetime.now(timezone.utc):
            invite = {"code": row["code"], "expiresAt": row["expires_at"]}
    puck = db.one("SELECT * FROM pucks WHERE family_id = ? ORDER BY last_seen_at DESC", (family_id,))
    return {
        "familyId": family_id,
        "me": member_view(device),
        "members": [member_view(m) for m in members if device["status"] == "active" or m["id"] == device["id"]],
        "invite": invite,
        "puck": puck_view(puck),
        "activeCall": active_call(db, family_id) if device["status"] == "active" else None,
    }


def register(app: FastAPI, db: Database) -> None:
    @app.post("/api/families", status_code=201)
    def create_family(body: dict = Body(...)):
        name = _name(body.get("name"))
        language = _language(body.get("language", "en"))
        token = new_token()
        family_id = db.create_family()
        device_id = new_id()
        db.execute(
            "INSERT INTO devices (id, family_id, role, status, name, relationship, language, token_hash, created_at) "
            "VALUES (?, ?, 'parent', 'active', ?, NULL, ?, ?, ?)",
            (device_id, family_id, name, language, hash_token(token), utc_now()),
        )
        return {"deviceToken": token, "deviceId": device_id, "familyId": family_id, "invite": new_invite(db, family_id)}

    @app.post("/api/families/invite", status_code=201)
    def renew_invite(authorization: str | None = Header(default=None)):
        parent = device_from(db, authorization, role="parent")
        return new_invite(db, parent["family_id"])

    @app.post("/api/families/join", status_code=201)
    def join_family(body: dict = Body(...)):
        code = str(body.get("code", "")).strip()
        name = _name(body.get("name"))
        language = _language(body.get("language", "en"))
        relationship = str(body.get("relationship") or "child")
        invite = db.one("SELECT * FROM invites WHERE code = ?", (code,))
        if not invite:
            raise HTTPException(404, "code not found")
        if _parse(invite["expires_at"]) <= datetime.now(timezone.utc):
            raise HTTPException(410, "code expired")
        token = new_token()
        device_id = new_id()
        db.execute(
            "INSERT INTO devices (id, family_id, role, status, name, relationship, language, token_hash, created_at) "
            "VALUES (?, ?, 'caregiver', 'pending', ?, ?, ?, ?, ?)",
            (device_id, invite["family_id"], name, relationship, language, hash_token(token), utc_now()),
        )
        return {"deviceToken": token, "deviceId": device_id, "status": "pending"}

    @app.get("/api/family")
    def get_family(authorization: str | None = Header(default=None)):
        device = device_from(db, authorization, active=False)
        return family_view(db, device)

    @app.post("/api/family/members/{member_id}/allow")
    def allow_member(member_id: str, authorization: str | None = Header(default=None)):
        parent = device_from(db, authorization, role="parent")
        member = db.one("SELECT * FROM devices WHERE id = ? AND family_id = ?", (member_id, parent["family_id"]))
        if not member:
            raise HTTPException(404, "unknown member")
        db.execute("UPDATE devices SET status = 'active' WHERE id = ?", (member_id,))
        return family_view(db, parent)

    @app.put("/api/devices/me")
    def update_me(body: dict = Body(...), authorization: str | None = Header(default=None)):
        device = device_from(db, authorization, active=False)
        name = _name(body["name"]) if "name" in body else device["name"]
        language = _language(body["language"]) if "language" in body else device["language"]
        relationship = str(body.get("relationship") or device["relationship"] or "") or None
        db.execute(
            "UPDATE devices SET name = ?, language = ?, relationship = ? WHERE id = ?",
            (name, language, relationship, device["id"]),
        )
        return member_view(db.one("SELECT * FROM devices WHERE id = ?", (device["id"],)))

    @app.put("/api/devices/me/push", status_code=204)
    def register_push(body: dict = Body(...), authorization: str | None = Header(default=None)):
        device = device_from(db, authorization, active=False)
        environment = body.get("environment", "sandbox")
        if environment not in ("sandbox", "production"):
            raise HTTPException(400, "environment must be sandbox or production")
        db.execute(
            "UPDATE devices SET apns_token = COALESCE(?, apns_token), apns_env = ?, "
            "la_start_token = COALESCE(?, la_start_token), la_update_token = COALESCE(?, la_update_token) WHERE id = ?",
            (body.get("apnsToken"), environment, body.get("liveActivityStartToken"),
             body.get("liveActivityUpdateToken"), device["id"]),
        )

    @app.post("/api/pucks", status_code=201)
    def pair_puck(authorization: str | None = Header(default=None)):
        parent = device_from(db, authorization, role="parent")
        token = new_token()
        puck_id = db.create_puck(parent["family_id"], hash_token(token))
        return {"puckId": puck_id, "puckToken": token}
