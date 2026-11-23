"""Per-session state shared by tools and data handlers (AgentSession.userdata)."""

from __future__ import annotations

from dataclasses import dataclass

from .languages import Language, get_language
from .protocol import DEFAULT_MODE, MODES, Mode


@dataclass
class SessionState:
    language: Language
    mode: Mode = DEFAULT_MODE
    minor_silenced: bool = False

    @classmethod
    def create(cls, language_code: str, mode: str) -> SessionState:
        return cls(
            language=get_language(language_code),
            mode=mode if mode in MODES else DEFAULT_MODE,  # type: ignore[arg-type]
        )

    @property
    def hazard_detection_on(self) -> bool:
        # Hazard detection is on in every mode; navigation adds turn-by-turn on top.
        return True

    def set_mode(self, mode: str) -> bool:
        """Return True if the mode changed. Raise ValueError for unknown modes."""
        if mode not in MODES:
            raise ValueError(f"unknown mode {mode!r}")
        changed = mode != self.mode
        self.mode = mode  # type: ignore[assignment]
        return changed
