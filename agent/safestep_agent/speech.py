"""Builds the STT and TTS chain for a session language."""

from __future__ import annotations

import logging
import os

from livekit.agents import tts as lk_tts
from livekit.plugins import spitch

from . import config
from .languages import Language
from .tts import yarngpt

logger = logging.getLogger("safestep.speech")


def build_stt(language: Language) -> spitch.STT:
    # Spitch STT is batch (non-streaming); AgentSession wraps it with the VAD automatically.
    return spitch.STT(language=language.spitch_stt)


def build_tts(language: Language) -> lk_tts.TTS:
    """YarnGPT first, Spitch TTS as fallback. Without a YarnGPT key, Spitch only."""
    fallback = spitch.TTS(language=language.spitch_tts, voice=language.voice_override())
    if not os.environ.get("YARNGPT_API_KEY", "").strip():
        logger.warning("YARNGPT_API_KEY not set; using Spitch TTS only")
        return fallback

    primary = yarngpt.TTS(
        base_url=config.YARNGPT_BASE_URL,
        voice=language.yarngpt_voice(),
        sample_rate=config.TTS_SAMPLE_RATE,
        first_byte_timeout=config.YARNGPT_FIRST_BYTE_TIMEOUT,
        rate_limit_cooldown=config.YARNGPT_RATE_LIMIT_COOLDOWN,
    )
    adapter = lk_tts.FallbackAdapter(
        [primary, fallback],
        max_retry_per_tts=0,  # fall back immediately; retries cost latency
        sample_rate=config.TTS_SAMPLE_RATE,
    )

    def _on_fallback(*_args: object, **_kwargs: object) -> None:
        logger.info("TTS fell back to Spitch")

    adapter.on("fallback_activated", _on_fallback)
    return adapter
