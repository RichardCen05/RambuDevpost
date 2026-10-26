"""Apple push: alert notifications and Live Activity updates, sent in the background.

Who gets what:
- call starts → parent's Live Activity starts ("Rambu is listening")
- risk rises  → parent: urgent alert + Live Activity turns amber/red; every caregiver: urgent alert
- caregiver decides → parent: alert + Live Activity shows the verdict; other caregivers: quiet update
- call ends   → parent's Live Activity ends
"""

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
import jwt

from . import i18n
from .analyze import Analysis
from .config import Settings
from .db import Database

log = logging.getLogger("rambu.push")

HOSTS = {"sandbox": "https://api.sandbox.push.apple.com", "production": "https://api.push.apple.com"}
URGENT_SOUND = "rambu-urgent.caf"


class APNs:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._token: tuple[str, float] | None = None
        self._lock = threading.Lock()
        self._client = httpx.Client(http2=True, timeout=10) if settings.apns_configured else None
        self._key = Path(settings.apns_key_path).read_text() if settings.apns_configured else ""

    @property
    def enabled(self) -> bool:
        return self._client is not None

    def _jwt(self) -> str:
        with self._lock:
            if not self._token or time.time() - self._token[1] > 50 * 60:
                token = jwt.encode(
                    {"iss": self.settings.apns_team_id, "iat": int(time.time())},
                    self._key, algorithm="ES256", headers={"kid": self.settings.apns_key_id},
                )
                self._token = (token, time.time())
            return self._token[0]

    def send(self, device_token: str, environment: str | None, payload: dict, *,
             push_type: str = "alert", priority: int = 10, live_activity: bool = False) -> int:
        if not self.enabled or not device_token:
            log.info("push skipped (%s): %s", "no APNs key" if not self.enabled else "no token", payload.get("aps", {}).get("event") or push_type)
            return 0
        topic = self.settings.apns_bundle_id + (".push-type.liveactivity" if live_activity else "")
        host = HOSTS.get(environment or "sandbox", HOSTS["sandbox"])
        try:
            response = self._client.post(
                f"{host}/3/device/{device_token}",
                json=payload,
                headers={
                    "authorization": f"bearer {self._jwt()}",
                    "apns-topic": topic,
                    "apns-push-type": push_type,
                    "apns-priority": str(priority),
                },
            )
        except httpx.HTTPError as exc:
            log.warning("push failed: %s", exc)
            return -1
        if response.status_code != 200:
            log.warning("push %s rejected %s: %s", push_type, response.status_code, response.text)
        return response.status_code


def alert_payload(title: str, body: str, rambu: dict, *, urgent: bool) -> dict:
    aps = {"alert": {"title": title, "body": body}, "sound": URGENT_SOUND if urgent else "default"}
    if urgent:
        aps["interruption-level"] = "time-sensitive"
    return {"aps": aps, "rambu": rambu}


def activity_payload(event: str, state: dict, *, attributes: dict | None = None, alert: tuple[str, str] | None = None) -> dict:
    aps: dict = {"timestamp": int(time.time()), "event": event, "content-state": state}
    if attributes is not None:
        aps["attributes-type"] = "RambuCallAttributes"
        aps["attributes"] = attributes
    if alert:
        aps["alert"] = {"title": alert[0], "body": alert[1]}
    if event == "end":
        aps["dismissal-date"] = int(time.time()) + 120
    return {"aps": aps}


class FamilyNotifier:
    """Implements the pipeline's Notifier and the caregiver-decision hook."""

    def __init__(self, db: Database, apns: APNs):
        self.db = db
        self.apns = apns
        self._pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="push")

    def _later(self, fn, *args, **kwargs) -> None:
        self._pool.submit(fn, *args, **kwargs)

    def _members(self, family_id: str) -> tuple[dict | None, list[dict]]:
        rows = self.db.all("SELECT * FROM devices WHERE family_id = ? AND status = 'active'", (family_id,))
        parent = next((r for r in rows if r["role"] == "parent"), None)
        return parent, [r for r in rows if r["role"] == "caregiver"]

    # Pipeline hooks --------------------------------------------------------

    def session_started(self, session: dict) -> None:
        parent, _ = self._members(session["family_id"])
        if not parent:
            return
        # A new activity gets a new push token; drop the old one so updates wait for the new token.
        self.db.execute("UPDATE devices SET la_update_token = NULL WHERE id = ?", (parent["id"],))
        lang = parent["language"]
        state = {"level": "listening", "title": i18n.t(lang, "Rambu is listening", "Rambu mendengarkan"),
                 "headline": i18n.t(lang, "Keep the call on speaker.", "Tetap gunakan loudspeaker.")}
        attributes = {"parentName": parent["name"], "startedAt": time.time()}
        self._later(self.apns.send, parent["la_start_token"], parent["apns_env"],
                    activity_payload("start", state, attributes=attributes), push_type="liveactivity", live_activity=True)

    def risk_raised(self, session: dict, alert: dict, analysis: Analysis) -> None:
        parent, caregivers = self._members(session["family_id"])
        level, signals, evidence = alert["level"], alert["signals"], alert["evidence"]
        rambu = {"kind": "warning", "alertId": alert["id"], "level": level, "verdict": None}
        if parent:
            lang = parent["language"]
            title, body = i18n.parent_warning(lang, level, signals, [c["name"] for c in caregivers])
            self._later(self.apns.send, parent["apns_token"], parent["apns_env"], alert_payload(title, body, rambu, urgent=True))
            state = {"level": level, "title": i18n.level_title(lang, level), "headline": i18n.headline(lang, signals)}
            self._send_activity_update(parent, state)
        for caregiver in caregivers:
            title, body = i18n.caregiver_warning(caregiver["language"], parent["name"] if parent else "", evidence)
            self._later(self.apns.send, caregiver["apns_token"], caregiver["apns_env"], alert_payload(title, body, rambu, urgent=True))

    def session_ended(self, session: dict, alert: dict | None) -> None:
        parent, _ = self._members(session["family_id"])
        if not parent:
            return
        lang = parent["language"]
        if alert and alert["verdict"]:
            _, _, short = i18n.verdict_for_parent(lang, alert["verdict"], self._name(alert["decided_by"]))
            state = {"level": alert["verdict"], "title": short, "headline": i18n.t(lang, "Call ended", "Panggilan selesai")}
        else:
            level = session["level"]
            state = {"level": level, "title": i18n.level_title(lang, level), "headline": i18n.t(lang, "Call ended", "Panggilan selesai")}
        self._send_activity_update(parent, state, event="end")

    # Decision hook ---------------------------------------------------------

    def verdict(self, alert: dict, decider: dict) -> None:
        session = self.db.session(alert["session_id"])
        parent, caregivers = self._members(session["family_id"])
        rambu = {"kind": "verdict", "alertId": alert["id"], "level": alert["level"], "verdict": alert["verdict"]}
        if parent:
            lang = parent["language"]
            title, body, short = i18n.verdict_for_parent(lang, alert["verdict"], decider["name"])
            self._later(self.apns.send, parent["apns_token"], parent["apns_env"],
                        alert_payload(title, body, rambu, urgent=alert["verdict"] == "scam"))
            state = {"level": alert["verdict"], "title": short, "headline": title, "decidedBy": decider["name"]}
            self._send_activity_update(parent, state, alert=(title, body))
        for caregiver in caregivers:
            if caregiver["id"] == decider["id"]:
                continue
            title, body = i18n.decided_by_other(caregiver["language"], alert["verdict"], decider["name"])
            self._later(self.apns.send, caregiver["apns_token"], caregiver["apns_env"],
                        alert_payload(title, body, {**rambu, "kind": "locked"}, urgent=False), priority=5)

    # Helpers ---------------------------------------------------------------

    def _name(self, device_id: str | None) -> str:
        row = self.db.one("SELECT name FROM devices WHERE id = ?", (device_id,)) if device_id else None
        return row["name"] if row else ""

    def _send_activity_update(self, parent: dict, state: dict, *, event: str = "update", alert: tuple[str, str] | None = None) -> None:
        def send():
            # The new activity's token may arrive a moment after the start push; wait briefly for it.
            for _ in range(10):
                token = self.db.one("SELECT la_update_token FROM devices WHERE id = ?", (parent["id"],))["la_update_token"]
                if token:
                    self.apns.send(token, parent["apns_env"], activity_payload(event, state, alert=alert),
                                   push_type="liveactivity", live_activity=True)
                    return
                time.sleep(0.5)
            log.info("live activity %s skipped: no activity token yet", event)

        self._later(send)
