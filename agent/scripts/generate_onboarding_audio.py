"""Generate the app's offline clips: onboarding (app/assets/onboarding/prompts.json) and
hazard alerts (app/assets/alerts/alerts.json).

Uses Spitch TTS (needs SPITCH_API_KEY in agent/.env). Every clip costs credits, so existing
files are skipped unless --force is given.

    cd agent
    uv run python scripts/generate_onboarding_audio.py            # all languages
    uv run python scripts/generate_onboarding_audio.py --lang yo   # one language
    uv run python scripts/generate_onboarding_audio.py --only alerts
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

SETS = {
    "onboarding": ROOT / "app" / "assets" / "onboarding" / "prompts.json",
    "alerts": ROOT / "app" / "assets" / "alerts" / "alerts.json",
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", choices=sorted(LANGUAGES), action="append")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", choices=sorted(SETS))
    args = ap.parse_args()

    client = Spitch()
    langs = args.lang or list(LANGUAGES)
    made = skipped = 0
    items = []
    for set_name, path in SETS.items():
        if args.only and args.only != set_name:
            continue
        for prompt_id, by_lang in json.loads(path.read_text(encoding="utf-8")).items():
            items.append((path.parent, prompt_id, by_lang))
    for assets, prompt_id, by_lang in items:
        if prompt_id.startswith("_"):
            continue
        for code in langs:
            text = by_lang.get(code)
            if not text:
                continue
            lang = LANGUAGES[code]
            out = assets / code / f"{prompt_id}.mp3"
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
