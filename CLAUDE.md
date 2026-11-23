# SafeStep — project brief for Claude

SafeStep is a voice-first Android app for blind and low-vision Nigerians, built for the Nigeria AI Collective "AI for the Visually Impaired" hackathon (**submission 15 Jan 2027**). It is derived from BlindSpot (Flutter app + Python LiveKit agent), which is kept locally in `reference/BlindSpot-master` (gitignored). See `docs/MIGRATION.md` for what we keep, rewrite and delete.

## Layout
- `/app` — Flutter, **Android only**
- `/agent` — Python LiveKit agent + tiny token server
- `/ml` — hazard model training/export (YOLOv8n → TFLite)
- `/docs` — migration plan, architecture, protocol, testing

## Rules
- **Check current official docs** (LiveKit Agents, LiveKit Flutter SDK, Spitch LiveKit plugin, YarnGPT API, Gemini, Google Maps Routes/Places) before writing code that uses them. Don't guess API shapes; if docs are unreachable, ask the user to paste them.
- **Never ship secrets in the app.** The LiveKit API secret lives only on the token server. No in-app JWT signing. Never commit keys; provide `.env.example` files. No `.backboard.json`.
- Ask before adding any paid service or changing the architecture.
- Small commits with clear messages. After each phase, report: what works, how to test it, what's still stubbed.

## Required changes from BlindSpot
1. **Security:** token endpoint in `/agent` issues room tokens and dispatches the agent. Delete `.backboard.json`. `.env.example` only.
2. **Hazard detection on the phone:** YOLOv8n TFLite in Flutter, offline. Stock COCO `yolov8n.tflite` as a placeholder until the fine-tuned model arrives (classes: `open_gutter, pothole, open_manhole, kerb_drop, okada, vehicle, person, pole, trader_table, construction_debris`). Warn only about hazards in the walking path (centre and lower part of the frame), and debounce repeats. Remove server-side `obstacle.py`; no continuous frame streaming.
3. **Alert player on the phone:** pre-recorded clip per hazard class × language, plus a vibration pattern per severity. Works with no network. It ducks/pauses agent audio, plays the alert, then sends a `hazard_event {class, side, distance_band}` data message so the agent can say "Make we continue."
4. **Modes by voice:** `set_mode` tool with `hazard_detection` (warnings only) and `navigation` (turn-by-turn + hazard detection). Hazard detection is ALWAYS on in navigation. Critical classes (`open_gutter`, `open_manhole`, `okada`) can never be silenced; "stop warning me" quiets minor classes only. Fixed phrases are recognised on the phone so switching to hazard detection works offline.
5. **Speech:** Spitch STT (official LiveKit plugin). YarnGPT TTS via a custom LiveKit TTS plugin using YarnGPT streaming, with automatic fallback to Spitch TTS on 429 or timeout. Languages: English, Pidgin, Yoruba, Hausa, Igbo — chosen at onboarding and passed to the agent.
6. **LLM:** Gemini Flash. Short, calm, multilingual replies; landmarks and left/right before compass directions; no "Zapier tools" line; no long replies during navigation.
7. **Navigation tracker** stays separate from the LLM (it announces turns itself); landmark-first phrasing; re-route when the user goes off route.
8. **Local preferences** on the phone (language, last mode, saved places) replace Backboard memory.
9. **Voice-only onboarding (runs once):** spoken multilingual welcome → mic permission ("tap anywhere") → language by voice → camera + location permission → optional tips → "Where do you want to go?" No typing, no account.
10. **UI:** `main.dart` split into screens and services. Full-screen gestures (double-tap to talk, swipe down to mute, long-press to repeat), TalkBack labels everywhere, high-contrast dark theme, large status card. No debug text for users.
11. **Android foreground service** so guidance continues with the screen off. No ios/macos/windows/linux/web folders.
12. **Latency logger** (end of user speech → first audio) and a **demo mode** that replays recorded street video through the on-device detector.

## Phases
1. Migration plan, skeleton, token server, agent voice loop (Spitch → Gemini → YarnGPT, fallback Spitch), latency logger, Flutter app connecting via token server with voice onboarding.
2. Navigation tools + tracker.
3. On-device YOLO + alert player + interrupt logic + offline mode switching.
4. Foreground service, gestures, scene description.
5. Demo mode, tests, docs.

Do one phase, then stop and report.

Status (Nov 2026): phases 1–5 implemented; see README and docs/TESTING.md. Remaining: on-device verification, fine-tuned model, native-speaker review of yo/ha/ig strings, hosting.
