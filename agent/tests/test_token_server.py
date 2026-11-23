import json

import pytest
from fastapi.testclient import TestClient
from livekit import api

from token_server.app import RateLimiter, create_app

KEY, SECRET = "devkey", "devsecret-devsecret-devsecret-1234"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("LIVEKIT_URL", "wss://example.livekit.cloud")
    monkeypatch.setenv("LIVEKIT_API_KEY", KEY)
    monkeypatch.setenv("LIVEKIT_API_SECRET", SECRET)
    monkeypatch.setenv("TOKEN_RATE_LIMIT_PER_MINUTE", "3")
    return TestClient(create_app())


def _req(**kw):
    body = {"language": "yo", "mode": "hazard_detection", "install_id": "abcdef123456"}
    body.update(kw)
    return body


def test_token_dispatches_agent_with_language(client):
    r = client.post("/token", json=_req())
    assert r.status_code == 200
    data = r.json()
    assert data["url"] == "wss://example.livekit.cloud"
    assert data["room"].startswith("safestep-")
    assert SECRET not in r.text  # the secret never leaves the server

    claims = api.TokenVerifier(KEY, SECRET).verify(data["token"])
    assert claims.identity == data["identity"]
    assert claims.video.room == data["room"]
    assert claims.video.room_join
    dispatch = claims.room_config.agents[0]
    assert dispatch.agent_name == "safestep"
    assert json.loads(dispatch.metadata) == {"language": "yo", "mode": "hazard_detection"}


def test_each_call_gets_new_room(client):
    a = client.post("/token", json=_req()).json()["room"]
    b = client.post("/token", json=_req()).json()["room"]
    assert a != b


@pytest.mark.parametrize(
    "bad", [{"language": "fr"}, {"mode": "party"}, {"install_id": "short"}, {"install_id": "bad id!!!!"}]
)
def test_rejects_bad_input(client, bad):
    assert client.post("/token", json=_req(**bad)).status_code == 422


def test_rate_limited(client):
    codes = [client.post("/token", json=_req()).status_code for _ in range(4)]
    assert codes == [200, 200, 200, 429]


def test_not_configured(monkeypatch):
    monkeypatch.delenv("LIVEKIT_API_SECRET", raising=False)
    monkeypatch.setenv("LIVEKIT_URL", "wss://x")
    monkeypatch.setenv("LIVEKIT_API_KEY", KEY)
    c = TestClient(create_app())
    assert c.post("/token", json=_req()).status_code == 503


def test_rate_limiter_window():
    t = [0.0]
    rl = RateLimiter(2, clock=lambda: t[0])
    assert rl.allow("k") and rl.allow("k") and not rl.allow("k")
    t[0] = 61.0
    assert rl.allow("k")
