"""Non-secret agent settings. Secrets are read from the environment (.env), never stored here."""

from __future__ import annotations

import os


def _f(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


AGENT_NAME = "safestep"  # must match the token server's dispatch

# --- LLM ---
# Default is the LiveKit Google plugin's own default chat model (livekit-plugins-google 1.8).
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.8-flash")
LLM_TEMPERATURE = 0.4
LLM_MAX_OUTPUT_TOKENS = 220  # short spoken replies only

# --- VAD / turn taking ---
VAD_MIN_SPEECH_DURATION = 0.2
VAD_MIN_SILENCE_DURATION = 0.5  # also used by the latency logger (end of speech estimate)
VAD_ACTIVATION_THRESHOLD = 0.6
ENDPOINTING_MIN_DELAY = 0.3

# --- TTS ---
TTS_SAMPLE_RATE = 24_000
YARNGPT_BASE_URL = os.environ.get("YARNGPT_BASE_URL", "https://api.yarngpt.ai").rstrip("/")
YARNGPT_FIRST_BYTE_TIMEOUT = _f("YARNGPT_FIRST_BYTE_TIMEOUT", 2.0)
YARNGPT_RATE_LIMIT_COOLDOWN = _f("YARNGPT_RATE_LIMIT_COOLDOWN", 30.0)

# --- Latency log ---
LATENCY_LOG_PATH = os.environ.get("LATENCY_LOG_PATH", "logs/latency.jsonl")
