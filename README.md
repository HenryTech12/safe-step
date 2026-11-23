# SafeStep

Voice-first Android walking companion for blind and low-vision Nigerians, in English, Pidgin, Yoruba, Hausa and Igbo.
Built for the Nigeria AI Collective "AI for the Visually Impaired" hackathon.

```
app/     Flutter app (Android only)
agent/   Python LiveKit agent + token server
ml/      hazard model (Phase 3)
docs/    MIGRATION.md, PROTOCOL.md
```

## Status

All five phases are implemented: voice loop, navigation, on-device hazards, foreground service and gestures, and demo mode. See `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md` and `docs/TESTING.md`.

## Run it locally

You need: Python 3.11+, [uv](https://docs.astral.sh/uv/), Flutter 3.50+, an Android phone or emulator, and keys for
LiveKit Cloud, Gemini (Google AI Studio), Spitch, YarnGPT and Google Maps (Routes API, Places API (New), Geocoding API).

### 1. Agent and token server
```bash
cd agent
cp .env.example .env        # fill in the keys
uv sync
uv run pytest               # no network or keys needed

# terminal 1: the agent worker
uv run python -m safestep_agent.main dev

# terminal 2: the token server (0.0.0.0 so the phone can reach it)
uv run uvicorn token_server.app:app --host 0.0.0.0 --port 8765
```
To talk to the agent without the phone, run `uv run python -m safestep_agent.main console`. It uses your laptop's mic and speaker, with English and hazard mode.

### 2. Onboarding clips (recommended before any demo)
Android has no built-in Yoruba, Hausa or Igbo voice. Generate the offline clips once with Spitch:
```bash
cd agent && uv run python scripts/generate_onboarding_audio.py
```

### 3. App
```bash
cd app
flutter pub get
flutter test
# Emulator: the token server on your laptop is http://10.0.2.2:8765 (the default)
flutter run
# Real phone on the same Wi-Fi:
flutter run --dart-define=TOKEN_URL=http://<your-laptop-LAN-IP>:8765
```
Debug builds allow plain HTTP to the token server. Release builds need HTTPS.

### Demo mode
```bash
python ml/scripts/video_to_frames.py walk.mp4 --out demo_frames --fps 5
adb push demo_frames/. /sdcard/Android/data/ng.safestep.app/files/demo/
flutter run --dart-define=TOKEN_URL=... --dart-define=DEMO=true   # "Demo mode" button on the guide screen
```

### Latency
Each answered turn is appended to `agent/logs/latency.jsonl`. `speech_end_to_audio_ms` is the headline number: the end of the user's speech to the first agent audio sent into the room.
