"""YarnGPT TTS plugin for LiveKit Agents.

Uses YarnGPT's real-time route (POST /api/v1/streaming/conversation), which streams raw audio
back in the same response. We ask for `pcm` (signed 16-bit LE, mono). The sample rate is NOT
fixed: it is read from `Content-Type: audio/l16; rate=<N>; channels=1` and resampled to the
rate this TTS declares, so tts.FallbackAdapter can mix it with Spitch without glitches.

Failure behaviour (so the FallbackAdapter switches to Spitch quickly):
- 429 / 402 / other non-200 -> APIStatusError(retryable=False)
- no first audio byte within `first_byte_timeout` -> APITimeoutError(retryable=False)
- after a 429 or 402 we stop calling YarnGPT for `rate_limit_cooldown` seconds and fail at once,
  so a busy account doesn't add a slow round trip to every sentence.

Each synthesize() call sends a fresh Idempotency-Key, so a retry of the same request is not
charged twice.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
import uuid

import httpx
from livekit import rtc
from livekit.agents import (
    DEFAULT_API_CONNECT_OPTIONS,
    APIConnectionError,
    APIConnectOptions,
    APIStatusError,
    APITimeoutError,
    tts,
    utils,
)

logger = logging.getLogger("safestep.yarngpt")

CONVERSATION_PATH = "/api/v1/streaming/conversation"
MAX_CHARS = 5000  # documented limit for this route
_RATE_RE = re.compile(r"rate\s*=\s*(\d+)", re.IGNORECASE)
_COOLDOWN_STATUSES = (402, 429)


def parse_sample_rate(content_type: str | None) -> int | None:
    if not content_type:
        return None
    m = _RATE_RE.search(content_type)
    return int(m.group(1)) if m else None


def _error_code(body: bytes) -> str:
    try:
        obj = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return ""
    if isinstance(obj, dict):
        err = obj.get("error")
        if isinstance(err, dict) and err.get("code"):
            return str(err["code"])
        if obj.get("code"):
            return str(obj["code"])
    return ""


class TTS(tts.TTS):
    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str = "https://api.yarngpt.ai",
        voice: str | None = None,
        sample_rate: int = 24_000,
        first_byte_timeout: float = 2.0,
        rate_limit_cooldown: float = 30.0,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(
            capabilities=tts.TTSCapabilities(streaming=False),
            sample_rate=sample_rate,
            num_channels=1,
        )
        self._api_key = (api_key or os.environ.get("YARNGPT_API_KEY", "")).strip()
        self._base_url = base_url.rstrip("/")
        self._voice = voice
        self._first_byte_timeout = first_byte_timeout
        self._cooldown_s = rate_limit_cooldown
        self._cooldown_until = 0.0
        self._client = http_client
        self._owns_client = http_client is None

    @property
    def model(self) -> str:
        return "streaming-conversation"

    @property
    def provider(self) -> str:
        return "YarnGPT"

    @property
    def cooling_down(self) -> bool:
        return time.monotonic() < self._cooldown_until

    def _start_cooldown(self) -> None:
        self._cooldown_until = time.monotonic() + self._cooldown_s

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                limits=httpx.Limits(max_keepalive_connections=4), http2=False
            )
        return self._client

    def synthesize(
        self, text: str, *, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS
    ) -> ChunkedStream:
        return ChunkedStream(tts=self, input_text=text, conn_options=conn_options)

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None


class ChunkedStream(tts.ChunkedStream):
    def __init__(self, *, tts: TTS, input_text: str, conn_options: APIConnectOptions) -> None:
        super().__init__(tts=tts, input_text=input_text, conn_options=conn_options)
        self._yarn = tts
        self._idempotency_key = uuid.uuid4().hex  # reused if this same request is retried

    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        yarn = self._yarn
        request_id = utils.shortuuid()

        if not yarn._api_key:
            raise APIStatusError("YARNGPT_API_KEY not set", status_code=401, retryable=False)
        if yarn.cooling_down:
            raise APIStatusError(
                "YarnGPT cooling down after rate limit", status_code=429, retryable=False
            )

        text = self.input_text.strip()[:MAX_CHARS]
        out_rate = yarn.sample_rate
        if not text:
            output_emitter.initialize(
                request_id=request_id, sample_rate=out_rate, num_channels=1, mime_type="audio/pcm"
            )
            output_emitter.flush()
            return

        body: dict[str, str] = {"text": text, "output_format": "pcm"}
        if yarn._voice:
            body["voice"] = yarn._voice
        headers = {
            "Authorization": f"Bearer {yarn._api_key}",
            "Idempotency-Key": self._idempotency_key,
            "Content-Type": "application/json",
        }
        timeout = httpx.Timeout(
            connect=self._conn_options.timeout,
            read=max(10.0, yarn._first_byte_timeout),
            write=self._conn_options.timeout,
            pool=self._conn_options.timeout,
        )

        try:
            async with asyncio.timeout(yarn._first_byte_timeout) as first_byte_deadline:
                async with yarn._http().stream(
                    "POST",
                    yarn._base_url + CONVERSATION_PATH,
                    json=body,
                    headers=headers,
                    timeout=timeout,
                ) as resp:
                    if resp.status_code != 200:
                        raw = await resp.aread()
                        code = _error_code(raw)
                        if resp.status_code in _COOLDOWN_STATUSES:
                            yarn._start_cooldown()
                        raise APIStatusError(
                            f"YarnGPT {resp.status_code} {code}".strip(),
                            status_code=resp.status_code,
                            request_id=request_id,
                            body=raw[:500].decode("utf-8", "replace"),
                            retryable=False,
                        )

                    in_rate = parse_sample_rate(resp.headers.get("content-type")) or out_rate
                    if in_rate != out_rate:
                        logger.debug("resampling YarnGPT %d Hz -> %d Hz", in_rate, out_rate)
                    output_emitter.initialize(
                        request_id=request_id,
                        sample_rate=out_rate,
                        num_channels=1,
                        mime_type="audio/pcm",
                    )
                    await self._pump(resp, output_emitter, in_rate, out_rate, first_byte_deadline)
            output_emitter.flush()
        except TimeoutError:
            raise APITimeoutError("YarnGPT first byte timeout", retryable=False) from None
        except httpx.TimeoutException:
            raise APITimeoutError("YarnGPT timeout", retryable=False) from None
        except APIStatusError:
            raise
        except httpx.HTTPError as e:
            raise APIConnectionError(f"YarnGPT connection error: {e}", retryable=False) from e

    async def _pump(
        self,
        resp: httpx.Response,
        emitter: tts.AudioEmitter,
        in_rate: int,
        out_rate: int,
        first_byte_deadline: asyncio.Timeout,
    ) -> None:
        resampler = (
            rtc.AudioResampler(input_rate=in_rate, output_rate=out_rate, num_channels=1)
            if in_rate != out_rate
            else None
        )
        bstream = utils.audio.AudioByteStream(sample_rate=in_rate, num_channels=1)
        got_first = False

        def emit(frames: list[rtc.AudioFrame]) -> None:
            for frame in frames:
                if resampler is None:
                    emitter.push(bytes(frame.data.cast("B")))
                else:
                    for rf in resampler.push(frame):
                        emitter.push(bytes(rf.data.cast("B")))

        async for chunk in resp.aiter_bytes():
            if not chunk:
                continue
            if not got_first:
                got_first = True
                first_byte_deadline.reschedule(None)  # only the first byte is time-boxed
            emit(bstream.write(chunk))

        emit(bstream.flush())
        if resampler is not None:
            for rf in resampler.flush():
                emitter.push(bytes(rf.data.cast("B")))
        if not got_first:
            raise APIConnectionError("YarnGPT returned no audio", retryable=False)
