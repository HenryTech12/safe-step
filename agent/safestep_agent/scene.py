"""Scene description: the phone sends one camera JPEG on request; Gemini describes it.

Flow: describe_scene tool → `frame_request {id}` to the phone → phone sends a JPEG byte
stream on topic `camera_frame` with attribute id → we caption it with Gemini vision →
the tool returns the caption for the agent to speak. No continuous streaming.
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from typing import Awaitable, Callable

from google import genai
from google.genai import types

from . import config, protocol
from .languages import Language

logger = logging.getLogger("safestep.scene")

FRAME_TIMEOUT_S = 6.0

PROMPT = (
    "You are describing a street scene for a blind pedestrian in Nigeria, from a chest-height phone "
    "camera. In {lang}, in at most two short spoken sentences: first say anything dangerous or in the "
    "way on the walking path (open gutters, holes, okadas, cars, poles, traders' tables, steps), with "
    "left, right or ahead; then the most useful landmark or sign. No lists, no markdown. If the image is "
    "too dark or blurry, say so briefly."
)


class SceneDescriber:
    def __init__(
        self,
        request_frame: Callable[[str], Awaitable[None]],
        language: Language,
        client: genai.Client | None = None,
        model: str | None = None,
    ) -> None:
        self._request = request_frame
        self._language = language
        self._client = client
        self._model = model or os.environ.get("GEMINI_VISION_MODEL", config.GEMINI_MODEL)
        self._waiting: dict[str, asyncio.Future[bytes]] = {}

    def _genai(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client()
        return self._client

    def on_frame(self, request_id: str, jpeg: bytes) -> None:
        fut = self._waiting.pop(request_id, None)
        if fut and not fut.done():
            fut.set_result(jpeg)

    async def describe(self) -> str:
        rid = uuid.uuid4().hex[:12]
        fut: asyncio.Future[bytes] = asyncio.get_running_loop().create_future()
        self._waiting[rid] = fut
        await self._request(rid)
        try:
            jpeg = await asyncio.wait_for(fut, FRAME_TIMEOUT_S)
        except asyncio.TimeoutError:
            self._waiting.pop(rid, None)
            return "NO_FRAME: the camera did not send a picture. Ask the user to hold the phone up and try again."
        try:
            resp = await self._genai().aio.models.generate_content(
                model=self._model,
                contents=[
                    types.Part.from_bytes(data=jpeg, mime_type="image/jpeg"),
                    PROMPT.format(lang=self._language.name),
                ],
                config=types.GenerateContentConfig(temperature=0.2, max_output_tokens=160),
            )
            text = (resp.text or "").strip()
        except Exception as e:  # noqa: BLE001
            logger.warning("scene description failed: %s", e)
            return "NETWORK: could not describe the scene right now."
        if not text:
            return "UNKNOWN: nothing clear to describe."
        return f"SCENE (read this out as is): {text}"


def frame_request_payload(request_id: str) -> bytes:
    return protocol.encode({"id": request_id})
