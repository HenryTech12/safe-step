import asyncio
import json

import httpx
import pytest
from livekit.agents import APIConnectOptions, APIStatusError, APITimeoutError
from livekit.agents import tts as lk_tts

from safestep_agent.tts import yarngpt

NO_RETRY = APIConnectOptions(max_retry=0, timeout=2.0)


def pcm(seconds: float, rate: int) -> bytes:
    return b"\x01\x00" * int(seconds * rate)


def make(handler, **kw) -> yarngpt.TTS:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return yarngpt.TTS(api_key="sk_test", http_client=client, first_byte_timeout=0.3, **kw)


async def collect(t: lk_tts.TTS, text="Make we continue."):
    frames = []
    async with t.synthesize(text, conn_options=NO_RETRY) as stream:
        async for ev in stream:
            frames.append(ev.frame)
    return frames


def duration(frames):
    return sum(f.samples_per_channel / f.sample_rate for f in frames)


def test_parse_sample_rate():
    assert yarngpt.parse_sample_rate("audio/l16; rate=16000; channels=1") == 16000
    assert yarngpt.parse_sample_rate("audio/l16") is None
    assert yarngpt.parse_sample_rate(None) is None


async def test_streams_pcm_and_sends_expected_request():
    seen = {}

    async def handler(req: httpx.Request):
        seen["url"] = str(req.url)
        seen["auth"] = req.headers["authorization"]
        seen["idem"] = req.headers.get("idempotency-key")
        seen["body"] = json.loads(req.content)
        return httpx.Response(200, headers={"content-type": "audio/l16; rate=24000; channels=1"}, content=pcm(0.5, 24000))

    frames = await collect(make(handler, voice="umar"))
    assert seen["url"] == "https://api.yarngpt.ai/api/v1/streaming/conversation"
    assert seen["auth"] == "Bearer sk_test"
    assert seen["idem"]
    assert seen["body"] == {"text": "Make we continue.", "output_format": "pcm", "voice": "umar"}
    assert all(f.sample_rate == 24000 for f in frames)
    assert duration(frames) == pytest.approx(0.5, abs=0.02)


async def test_resamples_when_provider_rate_differs():
    async def handler(req):
        return httpx.Response(200, headers={"content-type": "audio/l16; rate=16000; channels=1"}, content=pcm(1.0, 16000))

    frames = await collect(make(handler))
    assert {f.sample_rate for f in frames} == {24000}
    assert duration(frames) == pytest.approx(1.0, abs=0.05)


async def test_429_raises_and_starts_cooldown():
    calls = []

    async def handler(req):
        calls.append(1)
        return httpx.Response(429, json={"error": {"code": "RATE_LIMITED"}})

    t = make(handler, rate_limit_cooldown=60)
    with pytest.raises(APIStatusError) as e:
        await collect(t)
    assert e.value.status_code == 429 and not e.value.retryable
    assert t.cooling_down
    with pytest.raises(APIStatusError):
        await collect(t)
    assert len(calls) == 1  # second call failed fast without hitting the network


async def test_first_byte_timeout():
    async def handler(req):
        await asyncio.sleep(1.0)
        return httpx.Response(200, content=b"")

    with pytest.raises(APITimeoutError):
        await collect(make(handler))


async def test_missing_key_fails_without_network():
    t = yarngpt.TTS(api_key="", http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: 1 / 0)))
    t._api_key = ""
    with pytest.raises(APIStatusError):
        await collect(t)


async def test_fallback_adapter_switches_on_429():
    async def busy(req):
        return httpx.Response(429, json={"code": "RATE_LIMITED"})

    async def ok(req):
        return httpx.Response(200, headers={"content-type": "audio/l16; rate=24000; channels=1"}, content=pcm(0.3, 24000))

    adapter = lk_tts.FallbackAdapter([make(busy), make(ok)], max_retry_per_tts=0, sample_rate=24000)
    frames = await collect(adapter)
    assert duration(frames) == pytest.approx(0.3, abs=0.02)
    await adapter.aclose()
