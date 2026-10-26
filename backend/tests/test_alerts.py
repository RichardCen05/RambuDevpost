"""Alerts, the first-answer-wins decision, history, and push payloads."""

import threading

from fastapi.testclient import TestClient

from rambu import i18n
from rambu.main import create_app
from rambu.push import activity_payload, alert_payload
from tests.test_calls import TOKEN, KeywordAnalyzer, ScriptedTranscriber, run_call, settings, tone


class Recorder:
    def __init__(self):
        self.events = []

    def session_started(self, session):
        self.events.append("started")

    def risk_raised(self, session, alert, analysis):
        self.events.append(("risk", alert["level"]))

    def session_ended(self, session, alert):
        self.events.append("ended")

    def verdict(self, alert, decider):
        self.events.append(("verdict", alert["verdict"], decider["name"]))


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def family_with_two_caregivers(c):
    parent = c.post("/api/families", json={"name": "Ratna"}).json()
    code = parent["invite"]["code"]
    kids = []
    for name in ("Dimas", "Sinta"):
        kid = c.post("/api/families/join", json={"code": code, "name": name}).json()
        c.post(f"/api/family/members/{kid['deviceId']}/allow", headers=auth(parent["deviceToken"]))
        kids.append(kid)
    puck = c.post("/api/pucks/claim", json={"code": code}).json()
    return parent, kids, puck


def test_scam_call_alerts_family_and_first_answer_wins(tmp_path):
    notifier = Recorder()
    app = create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), notifier)
    with TestClient(app) as c:
        parent, (dimas, sinta), puck = family_with_two_caregivers(c)
        # stream a call through the family's puck
        global_token = puck["puckToken"]
        import tests.test_calls as calls
        original, calls.TOKEN = calls.TOKEN, global_token
        try:
            status = run_call(c, [tone(3.0, 0.1 * (n + 1)) for n in range(4)])
        finally:
            calls.TOKEN = original
        assert status["level"] == "high_risk"

        alerts = c.get("/api/alerts", headers=auth(dimas["deviceToken"])).json()
        assert len(alerts) == 1
        alert = alerts[0]
        assert alert["parentName"] == "Ratna"
        assert {r["name"] for r in alert["recipients"]} == {"Dimas", "Sinta"}
        assert alert["callEnded"] is True

        # parent can't decide
        assert c.post(f"/api/alerts/{alert['id']}/decision", json={"verdict": "scam"}, headers=auth(parent["deviceToken"])).status_code == 403

        results = {}

        def answer(who, token, verdict):
            results[who] = c.post(f"/api/alerts/{alert['id']}/decision", json={"verdict": verdict}, headers=auth(token)).json()

        threads = [threading.Thread(target=answer, args=("dimas", dimas["deviceToken"], "scam")),
                   threading.Thread(target=answer, args=("sinta", sinta["deviceToken"], "safe"))]
        [t.start() for t in threads]
        [t.join() for t in threads]
        accepted = [w for w, r in results.items() if r["accepted"]]
        assert len(accepted) == 1
        final = {r["alert"]["decision"]["verdict"] for r in results.values()}
        assert len(final) == 1  # both see the same decision
        assert len([e for e in notifier.events if e[0] == "verdict"]) == 1

        history = c.get("/api/history", headers=auth(parent["deviceToken"])).json()
        assert history[0]["level"] == "high_risk" and history[0]["decision"] is not None
        detail_parent = c.get(f"/api/history/{history[0]['id']}", headers=auth(parent["deviceToken"])).json()
        detail_kid = c.get(f"/api/history/{history[0]['id']}", headers=auth(dimas["deviceToken"])).json()
        assert "•••" in detail_parent["transcript"]
        assert detail_kid["transcript"] is None


def test_active_call_shows_in_family(tmp_path):
    app = create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), Recorder())
    with TestClient(app) as c:
        parent, _, puck = family_with_two_caregivers(c)
        session = c.post("/api/puck/sessions", headers=auth(puck["puckToken"])).json()
        family = c.get("/api/family", headers=auth(parent["deviceToken"])).json()
        assert family["activeCall"]["sessionId"] == session["sessionId"]
        assert family["puck"]["online"] is True


def test_push_copy_and_payloads():
    title, body = i18n.parent_warning("en", "high_risk", ["urgency", "secret_code"], ["Dimas"])
    assert title == "Danger: possible scam"
    assert body == "The caller is asking for a secret code. Sent to Dimas."
    title, _ = i18n.caregiver_warning("id", "Ratna", [{"quote": "Q", "signals": ["urgency"]}])
    assert title == "Ratna mungkin sedang ditipu"
    assert i18n.verdict_for_parent("en", "scam", "Dimas")[0] == "Dimas says this is a scam"

    payload = alert_payload("t", "b", {"kind": "warning"}, urgent=True)
    assert payload["aps"]["interruption-level"] == "time-sensitive"
    assert payload["aps"]["sound"] == "rambu-urgent.caf"
    start = activity_payload("start", {"level": "listening"}, attributes={"parentName": "Ratna", "startedAt": 1.0})
    assert start["aps"]["attributes-type"] == "RambuCallAttributes"
    assert "dismissal-date" in activity_payload("end", {})["aps"]
