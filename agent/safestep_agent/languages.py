"""The five SafeStep languages and how each maps onto the speech providers.

SafeStep's own codes match the app (`app/lib/models/language.dart`):
    en  English
    pcm Nigerian Pidgin
    yo  Yoruba
    ha  Hausa
    ig  Igbo

UNVERIFIED (docs.spitch.app was unreachable from the build machine):
- Whether Spitch STT/TTS accept Pidgin. Until confirmed, Pidgin uses Spitch's English
  model (its English STT is trained on African-accented speech) and an English voice.
- Which Spitch voice belongs to which language. The names below are a best guess from
  the SDK's voice list. Override any of them with SPITCH_VOICE_<LANG> in .env.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

DEFAULT_LANGUAGE = "en"


@dataclass(frozen=True)
class Language:
    code: str  # SafeStep code
    name: str  # English name, used in the system prompt
    native_name: str
    spitch_stt: str  # language code sent to Spitch transcribe
    spitch_tts: str  # language code sent to Spitch generate
    spitch_voice: str
    # Fixed lines the agent speaks without the LLM. NEED NATIVE-SPEAKER REVIEW (yo/ha/ig).
    greeting: str
    continue_line: str
    mode_hazard: str
    mode_navigation: str
    reconnecting: str

    def voice_override(self) -> str:
        return os.environ.get(f"SPITCH_VOICE_{self.code.upper()}", "").strip() or self.spitch_voice

    def yarngpt_voice(self) -> str | None:
        v = os.environ.get(f"YARNGPT_VOICE_{self.code.upper()}", "").strip()
        return v or None


LANGUAGES: dict[str, Language] = {
    "en": Language(
        code="en",
        name="English",
        native_name="English",
        spitch_stt="en",
        spitch_tts="en",
        spitch_voice="lina",
        greeting="Where do you want to go?",
        continue_line="Okay, let's continue.",
        mode_hazard="Hazard warnings only.",
        mode_navigation="Navigation on. Hazard warnings stay on.",
        reconnecting="Connection is weak. Hazard warnings still work.",
    ),
    "pcm": Language(
        code="pcm",
        name="Nigerian Pidgin",
        native_name="Naija",
        spitch_stt="en",
        spitch_tts="en",
        spitch_voice="lina",
        greeting="Where you wan go?",
        continue_line="Make we continue.",
        mode_hazard="Na only danger warning I go dey give you now.",
        mode_navigation="Direction don on. I go still dey warn you for danger.",
        reconnecting="Network no strong. Danger warning still dey work.",
    ),
    "yo": Language(
        code="yo",
        name="Yoruba",
        native_name="Yorùbá",
        spitch_stt="yo",
        spitch_tts="yo",
        spitch_voice="sade",
        greeting="Níbo ni o fẹ́ lọ?",
        continue_line="Ó dáa, ẹ jẹ́ ká máa lọ.",
        mode_hazard="Ìkìlọ̀ ewu nìkan.",
        mode_navigation="Ìtọ́sọ́nà ti bẹ̀rẹ̀. Ìkìlọ̀ ewu ṣì wà.",
        reconnecting="Ìsopọ̀ kò lágbára. Ìkìlọ̀ ewu ṣì ń ṣiṣẹ́.",
    ),
    "ha": Language(
        code="ha",
        name="Hausa",
        native_name="Hausa",
        spitch_stt="ha",
        spitch_tts="ha",
        spitch_voice="amina",
        greeting="Ina kake son zuwa?",
        continue_line="To, mu ci gaba.",
        mode_hazard="Gargadin haɗari kawai.",
        mode_navigation="An kunna jagora. Gargadin haɗari yana nan.",
        reconnecting="Hanyar sadarwa ba ta da ƙarfi. Gargadin haɗari yana aiki.",
    ),
    "ig": Language(
        code="ig",
        name="Igbo",
        native_name="Igbo",
        spitch_stt="ig",
        spitch_tts="ig",
        spitch_voice="ngozi",
        greeting="Ebee ka ị chọrọ ịga?",
        continue_line="Ọ dị mma, ka anyị gaa n'ihu.",
        mode_hazard="Ọ bụ naanị ịdọ aka ná ntị maka ihe egwu.",
        mode_navigation="Nduzi amalitela. Ịdọ aka ná ntị ka dị.",
        reconnecting="Netwọk adịghị ike. Ịdọ aka ná ntị ka na-arụ ọrụ.",
    ),
}


def get_language(code: str | None) -> Language:
    """Return the language for `code`, falling back to English for unknown codes."""
    return LANGUAGES.get((code or "").strip().lower(), LANGUAGES[DEFAULT_LANGUAGE])
