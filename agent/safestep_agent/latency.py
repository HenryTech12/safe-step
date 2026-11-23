"""Latency logger: end of user speech → first agent audio.

How it measures:
- `user_state_changed` speaking → listening fires when the VAD decides speech ended, which is
  `vad_silence_s` after the last spoken word. We subtract that to estimate the real end of speech.
- `agent_state_changed` → speaking fires when the first TTS frame is played into the room.
- `metrics_collected` events in between are attached to the turn (EOU delay, STT time,
  LLM time-to-first-token, TTS time-to-first-byte and which TTS served).

Each finished turn is written as one JSON line, so it can be loaded into a spreadsheet or pandas.
Network time from the room to the phone's speaker is NOT included (the app logs that side).
"""

from __future__ import annotations

import json
import logging
import os
import threading
from dataclasses import asdict, dataclass, field
from typing import Any, Callable

logger = logging.getLogger("safestep.latency")


@dataclass
class TurnRecord:
    session: str
    turn: int
    language: str
    mode: str
    vad_end_at: float  # wall clock, seconds
    first_audio_at: float | None = None
    speech_end_to_audio_ms: float | None = None  # headline number
    vad_end_to_audio_ms: float | None = None
    eou_delay_ms: float | None = None
    stt_ms: float | None = None
    llm_ttft_ms: float | None = None
    tts_ttfb_ms: float | None = None
    tts_label: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


Sink = Callable[[dict[str, Any]], None]


def jsonl_sink(path: str) -> Sink:
    lock = threading.Lock()
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)

    def write(rec: dict[str, Any]) -> None:
        line = json.dumps(rec, ensure_ascii=False)
        with lock, open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    return write


class LatencyTracker:
    def __init__(
        self,
        *,
        session_id: str,
        language: str,
        mode: str,
        vad_silence_s: float,
        sink: Sink | None = None,
    ) -> None:
        self._session_id = session_id
        self.language = language
        self.mode = mode
        self._vad_silence_s = vad_silence_s
        self._sink = sink
        self._turn = 0
        self._current: TurnRecord | None = None
        self.records: list[TurnRecord] = []

    # --- event hooks (plain values so they are easy to unit test) ---

    def on_user_state(self, old: str, new: str, at: float) -> None:
        if old == "speaking" and new == "listening":
            self._turn += 1
            self._current = TurnRecord(
                session=self._session_id,
                turn=self._turn,
                language=self.language,
                mode=self.mode,
                vad_end_at=at,
            )
        elif new == "speaking" and self._current and self._current.first_audio_at is None:
            # user spoke again before we answered: drop the unanswered turn
            self._current = None

    def on_agent_state(self, new: str, at: float) -> None:
        cur = self._current
        if new != "speaking" or cur is None or cur.first_audio_at is not None:
            return
        cur.first_audio_at = at
        vad_ms = (at - cur.vad_end_at) * 1000.0
        cur.vad_end_to_audio_ms = round(vad_ms, 1)
        cur.speech_end_to_audio_ms = round(vad_ms + self._vad_silence_s * 1000.0, 1)
        self._finish(cur)

    def on_metrics(self, metrics: Any) -> None:
        cur = self._current
        if cur is None or cur.first_audio_at is not None:
            return
        kind = getattr(metrics, "type", "")
        if kind == "eou_metrics":
            cur.eou_delay_ms = _ms(getattr(metrics, "end_of_utterance_delay", None))
        elif kind == "stt_metrics":
            cur.stt_ms = _ms(getattr(metrics, "duration", None))
        elif kind == "llm_metrics" and cur.llm_ttft_ms is None:
            cur.llm_ttft_ms = _ms(getattr(metrics, "ttft", None))
        elif kind == "tts_metrics" and cur.tts_ttfb_ms is None:
            cur.tts_ttfb_ms = _ms(getattr(metrics, "ttfb", None))
            cur.tts_label = getattr(metrics, "label", None)

    # --- internals ---

    def _finish(self, rec: TurnRecord) -> None:
        self.records.append(rec)
        self._current = None
        logger.info(
            "turn %d latency %.0f ms (llm_ttft=%s tts_ttfb=%s via %s)",
            rec.turn,
            rec.speech_end_to_audio_ms or -1,
            rec.llm_ttft_ms,
            rec.tts_ttfb_ms,
            rec.tts_label,
        )
        if self._sink:
            try:
                self._sink(asdict(rec))
            except OSError as e:
                logger.warning("latency sink failed: %s", e)


def _ms(seconds: float | None) -> float | None:
    if seconds is None or seconds < 0:
        return None
    return round(seconds * 1000.0, 1)
