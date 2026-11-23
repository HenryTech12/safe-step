"""Data-message topics and payloads shared with the app. Keep in sync with docs/PROTOCOL.md
and app/lib/services/protocol.dart."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Literal

from .languages import DEFAULT_LANGUAGE, LANGUAGES

Mode = Literal["hazard_detection", "navigation"]
MODES: tuple[str, ...] = ("hazard_detection", "navigation")
DEFAULT_MODE: Mode = "hazard_detection"

# phone ⇄ agent topics
TOPIC_MODE = "mode"  # both ways: {"mode": "...", "source": "agent"|"phone"}
TOPIC_WARNINGS = "warnings"  # agent → phone: {"minor_silenced": bool}
TOPIC_HAZARD = "hazard_event"  # phone → agent: {"class", "side", "distance_band"}
TOPIC_GPS = "gps"  # phone → agent (Phase 2): {"lat", "lng", "heading"?}

CRITICAL_CLASSES = frozenset({"open_gutter", "open_manhole", "okada"})


@dataclass(frozen=True)
class DispatchMetadata:
    """Sent by the token server inside RoomAgentDispatch.metadata."""

    language: str = DEFAULT_LANGUAGE
    mode: Mode = DEFAULT_MODE

    @classmethod
    def parse(cls, raw: str | None) -> DispatchMetadata:
        data: dict[str, Any] = {}
        if raw:
            try:
                loaded = json.loads(raw)
                if isinstance(loaded, dict):
                    data = loaded
            except json.JSONDecodeError:
                pass
        lang = str(data.get("language", DEFAULT_LANGUAGE)).lower()
        mode = str(data.get("mode", DEFAULT_MODE))
        return cls(
            language=lang if lang in LANGUAGES else DEFAULT_LANGUAGE,
            mode=mode if mode in MODES else DEFAULT_MODE,  # type: ignore[arg-type]
        )

    def to_json(self) -> str:
        return json.dumps({"language": self.language, "mode": self.mode})


def encode(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def decode(data: bytes) -> dict[str, Any] | None:
    try:
        obj = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return obj if isinstance(obj, dict) else None
