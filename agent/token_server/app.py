"""Tiny token server: the ONLY place the LiveKit API secret is used.

POST /token  {"language": "yo", "mode": "hazard_detection", "install_id": "<random per install>"}
  -> 200 {"url": "wss://...", "token": "<jwt>", "room": "safestep-...", "identity": "user-..."}

Every call creates a fresh room name, so the agent dispatch inside the token always applies
(LiveKit ignores a token's room config when the room already exists).

Run:  uv run uvicorn token_server.app:app --host 0.0.0.0 --port 8765
"""

from __future__ import annotations

import hashlib
import os
import re
import time
import uuid
from collections import defaultdict, deque
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from livekit import api
from pydantic import BaseModel, Field

from safestep_agent import config as agent_config
from safestep_agent.languages import LANGUAGES
from safestep_agent.protocol import MODES, DispatchMetadata

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

_INSTALL_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


class TokenRequest(BaseModel):
    language: str = Field(default="en")
    mode: str = Field(default="hazard_detection")
    install_id: str = Field(min_length=8, max_length=64)


class TokenResponse(BaseModel):
    url: str
    token: str
    room: str
    identity: str


class RateLimiter:
    """In-memory sliding window per key. Good enough for one small server."""

    def __init__(self, per_minute: int, clock=time.monotonic) -> None:
        self._limit = per_minute
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = self._clock()
        q = self._hits[key]
        while q and now - q[0] > 60.0:
            q.popleft()
        if len(q) >= self._limit:
            return False
        q.append(now)
        return True


def _env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise HTTPException(status_code=503, detail="server not configured")
    return value


def create_app() -> FastAPI:
    app = FastAPI(title="SafeStep token server", docs_url=None, redoc_url=None)
    limiter = RateLimiter(int(os.environ.get("TOKEN_RATE_LIMIT_PER_MINUTE", "6")))
    ttl = timedelta(minutes=int(os.environ.get("TOKEN_TTL_MINUTES", "60")))

    @app.get("/healthz")
    def healthz() -> dict:
        return {"ok": True}

    @app.post("/token", response_model=TokenResponse)
    def token(req: TokenRequest, request: Request) -> TokenResponse:
        if req.language not in LANGUAGES:
            raise HTTPException(status_code=422, detail="unknown language")
        if req.mode not in MODES:
            raise HTTPException(status_code=422, detail="unknown mode")
        if not _INSTALL_ID_RE.match(req.install_id):
            raise HTTPException(status_code=422, detail="bad install_id")

        client_ip = request.client.host if request.client else "unknown"
        if not (limiter.allow("install:" + req.install_id) and limiter.allow("ip:" + client_ip)):
            raise HTTPException(status_code=429, detail="too many requests")

        url = _env("LIVEKIT_URL")
        key = _env("LIVEKIT_API_KEY")
        secret = _env("LIVEKIT_API_SECRET")

        # identity is stable per install but doesn't reveal the raw install id
        identity = "user-" + hashlib.sha256(req.install_id.encode()).hexdigest()[:16]
        room = f"safestep-{uuid.uuid4().hex[:12]}"
        meta = DispatchMetadata(language=req.language, mode=req.mode)  # type: ignore[arg-type]

        jwt = (
            api.AccessToken(key, secret)
            .with_identity(identity)
            .with_name("SafeStep user")
            .with_ttl(ttl)
            .with_grants(
                api.VideoGrants(
                    room_join=True,
                    room=room,
                    can_publish=True,
                    can_subscribe=True,
                    can_publish_data=True,
                )
            )
            .with_room_config(
                api.RoomConfiguration(
                    agents=[
                        api.RoomAgentDispatch(
                            agent_name=agent_config.AGENT_NAME, metadata=meta.to_json()
                        )
                    ],
                    empty_timeout=60,
                    departure_timeout=20,
                    max_participants=2,
                )
            )
            .to_jwt()
        )
        return TokenResponse(url=url, token=jwt, room=room, identity=identity)

    return app


app = create_app()
