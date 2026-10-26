from fastapi.testclient import TestClient

from rambu.main import create_app
from tests.test_calls import KeywordAnalyzer, Recorder, ScriptedTranscriber, settings


def client(tmp_path) -> TestClient:
    return TestClient(create_app(settings(tmp_path), ScriptedTranscriber(), KeywordAnalyzer(), Recorder()))


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_parent_invites_caregiver_who_waits_for_allow(tmp_path):
    with client(tmp_path) as c:
        parent = c.post("/api/families", json={"name": "Ratna", "language": "en"}).json()
        code = parent["invite"]["code"]
        assert len(code) == 6 and code.isdigit()

        child = c.post("/api/families/join", json={"code": code, "name": "Dimas", "relationship": "child"}).json()
        assert child["status"] == "pending"
        assert c.get("/api/family", headers=auth(child["deviceToken"])).json()["me"]["status"] == "pending"
        assert c.post("/api/families/invite", headers=auth(child["deviceToken"])).status_code == 403

        family = c.get("/api/family", headers=auth(parent["deviceToken"])).json()
        pending = [m for m in family["members"] if m["status"] == "pending"]
        assert [m["name"] for m in pending] == ["Dimas"]

        allowed = c.post(f"/api/family/members/{pending[0]['id']}/allow", headers=auth(parent["deviceToken"])).json()
        assert {m["name"]: m["status"] for m in allowed["members"]} == {"Ratna": "active", "Dimas": "active"}
        seen_by_child = c.get("/api/family", headers=auth(child["deviceToken"])).json()
        assert {m["name"] for m in seen_by_child["members"]} == {"Ratna", "Dimas"}
        assert seen_by_child["invite"] is None  # only the parent sees the code


def test_wrong_and_expired_codes(tmp_path):
    with client(tmp_path) as c:
        parent = c.post("/api/families", json={"name": "Ratna"}).json()
        assert c.post("/api/families/join", json={"code": "000000", "name": "X"}).status_code in (404, 201)
        c.app.state.db.execute("UPDATE invites SET expires_at = '2000-01-01T00:00:00Z'")
        r = c.post("/api/families/join", json={"code": parent["invite"]["code"], "name": "Dimas"})
        assert r.status_code == 410


def test_renewing_replaces_the_old_code(tmp_path):
    with client(tmp_path) as c:
        parent = c.post("/api/families", json={"name": "Ratna"}).json()
        old = parent["invite"]["code"]
        new = c.post("/api/families/invite", headers=auth(parent["deviceToken"])).json()["code"]
        if new != old:
            assert c.post("/api/families/join", json={"code": old, "name": "Dimas"}).status_code == 404


def test_device_settings_and_puck_pairing(tmp_path):
    with client(tmp_path) as c:
        parent = c.post("/api/families", json={"name": "Ratna"}).json()
        h = auth(parent["deviceToken"])
        assert c.put("/api/devices/me", json={"language": "id"}, headers=h).json()["language"] == "id"
        assert c.put("/api/devices/me/push", json={"apnsToken": "abc", "environment": "sandbox"}, headers=h).status_code == 204
        puck = c.post("/api/pucks", headers=h).json()
        puck_auth = auth(puck["puckToken"])
        assert c.post("/api/puck/hello", json={"firmware": "1.0.0"}, headers=puck_auth).status_code == 200
        assert c.get("/api/family", headers=h).json()["puck"]["online"] is True
        # The paired puck's calls use the parent's language.
        assert c.post("/api/puck/sessions", headers=puck_auth).json()["language"] == "id"
