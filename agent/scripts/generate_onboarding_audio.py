"""Generate the app's offline onboarding clips from app/assets/onboarding/prompts.json.

Uses Spitch TTS (needs SPITCH_API_KEY in agent/.env). Every clip costs credits, so existing
files are skipped unless --force is given.

    cd agent
    uv run python scripts/generate_onboarding_audio.py            # all languages
    uv run python scripts/generate_onboarding_audio.py --lang yo   # one language
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "agent"))
load_dotenv(ROOT / "agent" / ".env")

from spitch import Spitch  # noqa: E402

from safestep_agent.languages import LANGUAGES  # noqa: E402

ASSETS = ROOT / "app" / "assets" / "onboarding"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", choices=sorted(LANGUAGES), action="append")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    prompts = json.loads((ASSETS / "prompts.json").read_text(encoding="utf-8"))
    client = Spitch()
    langs = args.lang or list(LANGUAGES)
    made = skipped = 0
    for prompt_id, by_lang in prompts.items():
        if prompt_id.startswith("_"):
            continue
        for code in langs:
            text = by_lang.get(code)
            if not text:
                continue
            lang = LANGUAGES[code]
            out = ASSETS / code / f"{prompt_id}.mp3"
            if out.exists() and not args.force:
                skipped += 1
                continue
            audio = client.speech.generate(
                text=text, language=lang.spitch_tts, voice=lang.voice_override(), format="mp3"
            )
            out.write_bytes(audio.read())
            made += 1
            print(f"wrote {out.relative_to(ROOT)}")
    print(f"done: {made} generated, {skipped} already present")


if __name__ == "__main__":
    main()
