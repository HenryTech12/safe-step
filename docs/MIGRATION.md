# BlindSpot → SafeStep migration plan

Status: **approved; Phases 1–5 implemented.** Hosting is deferred. Notes from implementation are marked *(Phase 1)*.

Source reviewed: `reference/BlindSpot-master` (kept locally only and ignored by git, because it contains `.backboard.json`, a 12 MB ONNX model, `.pyc` files and `.DS_Store`).

---

## 1. What BlindSpot is today (findings)

| File | What it does | Problems for SafeStep |
|---|---|---|
| `agent.py` (313 lines) | LiveKit `AgentServer`, agent name `voice-agent`. ElevenLabs STT/TTS, Gemini 2.5 Flash (thinking budget 0), Silero VAD, BVC noise cancellation. Data topics: `gps`, `app-mode`, `obstacle-mode`, `obstacle-frame`, `obstacle`. Runs server-side obstacle detection on JPEG frames streamed over data channels. Backboard memory. Says a hard-coded greeting after 2 s. Leaves the room when the user disconnects. | Frames streamed continuously (bandwidth, latency, 14 KB payload limit). Detection needs the network. ElevenLabs is English-centric and paid. Tools are added through the private `agent._tools` attribute. |
| `agent_config.py` | Prompt and model constants. | English only. Compass-first directions. Leftover "Use Zapier tools" line. Long route summaries. |
| `google_maps.py` (445 lines) | `NavigationTool`: `get_current_location` (reverse geocode), `get_heading`, `start_navigation` (legacy **Directions API** with alternatives, plus a second Gemini call that picks the "safest" route), `update_location`, `get_walking_directions`, `search_places` and `navigate_to_nearby` (**Places API (New)** `places:searchText`). | Uses the legacy Directions API through `googlemaps`. Exposes `update_location` as an LLM tool, although GPS already drives it. The extra Gemini route pick adds latency. Error strings are written for developers ("enable Directions API…"), not for users. |
| `navigation.py` (215 lines) | `NavigationSession`: a pure-Python step tracker using haversine distance. Warns at 45 m, says "Now" at 12 m, has an 18 s grace period after the route starts. Relative direction (forward, left, right, behind) plus a compass point. | **Good core; keep it.** No off-route detection or re-routing. Phrasing is compass-first and English-only. Only reads `legs[0]`. |
| `obstacle.py` (261 lines) | OpenCV HOG or YOLOv8n ONNX on the server. "In path" means x 20–80 %, y 25–100 %. | Moves to the phone. Keep the idea of a walking-path region, not the code. |
| `backboard_store.py` | Remote memory through Backboard. | Delete. Replaced by local preferences. |
| `lib/main.dart` (1,581 lines) | One giant file: splash, home, camera preview, GPS, compass, mic test, obstacle frame capture (BGRA→JPEG in an isolate), haptics, buttons, compass painter, debug text. | Split into screens and services. Remove frame streaming, button-driven modes, mic test UI and debug text. |
| `lib/voice_service.dart` | LiveKit `Room` connect, publishes GPS every 3 s and on compass change, **signs LiveKit JWTs in the app with the API secret** (`dart_jsonwebtoken`), and falls back to a token URL. | **Security bug: the API secret ships in the APK.** Keep the connect, listener and safe-publish pattern; delete JWT signing. |
| `lib/config.dart` | `--dart-define` constants, including `LIVEKIT_API_SECRET` and `GOOGLE_API_KEY`. | Remove all secrets. Only `TOKEN_URL` (and non-secret flags) remain. |
| `run_app.sh` | Copies `LIVEKIT_API_SECRET` and `GOOGLE_API_KEY` from `.env.local` into the Flutter build. | Delete. This is how secrets reached the app. |
| `.backboard.json` | Backboard assistant and thread IDs. | Delete. Never commit. |
| `mcp_client/` | Only stale `.pyc` files (Zapier MCP leftovers). | Delete. |
| `yolov8n.onnx`, `scripts/download_yolov8n_onnx.py`, `test_obstacle_local.py`, `tests/test_obstacle.py` | Server-side detection assets. | Delete. Replaced by `/ml` export scripts and a TFLite model on the phone. |
| `ios/ macos/ windows/ linux/ web/` | Other platforms. | Delete. SafeStep is Android only. |
| `android/` | Package `com.example.cam_preview`. Camera, mic and location permissions. | Keep as a starting point. Rename the package to `ng.safestep.app`. Add the foreground-service, notification, vibration and wake-lock permissions. |

---

## 2. Keep / Rewrite / Delete

### Keep (port with small changes)
- `navigation.py` → `agent/safestep_agent/nav/tracker.py`. Keep the haversine distance, bearing, relative-direction maths, 45 m / 12 m thresholds and grace period. Add off-route detection, re-routing and landmark-first phrasing in Phase 2.
- `tests/test_navigation.py` → `agent/tests/test_tracker.py`. Extend it.
- From `agent.py`: the `AgentServer` and `@server.rtc_session(agent_name=…)` structure, Silero VAD settings, BVC noise cancellation, the `data_received` topic router pattern, and leaving the room when the participant disconnects.
- From `google_maps.py`: the Places (New) `searchText` request with `locationBias` and `rankPreference: DISTANCE`, and the "list three options, then let the user pick" flow.
- From `voice_service.dart`: room listeners, `_publishDataSafe`, GPS and heading publishing (only while navigating), and fetching from a token URL.
- From `main.dart`: the Geolocator stream setup (`bestForNavigation`, `distanceFilter: 3`), compass subscription and back-camera selection.
- Android launcher icons and assets.

### Rewrite
- `agent_config.py` → `agent/safestep_agent/prompts.py` plus `config.py`. Multilingual and calm, 1–2 sentence replies, landmarks and left/right before compass points, no Zapier line, very short replies while navigating, language injected per session.
- `agent.py` → `agent/safestep_agent/main.py` with `Spitch STT → Gemini Flash → YarnGPT TTS (FallbackAdapter → Spitch TTS)`. Language comes from participant/dispatch metadata. Add `set_mode` and latency logging. Register tools through the public `Agent(tools=[…])` API.
- `google_maps.py` → `agent/safestep_agent/nav/maps.py`, moved to the **Routes API** (`computeRoutes`, `travelMode: WALK`), with no second LLM call for route choice in the hot path. Error messages are user-safe and translated. *(Phase 2)*
- `voice_service.dart` → `app/lib/services/livekit_service.dart`. Uses the token server only. Sends `language` and `mode`. Handles the `hazard_event` and `mode` topics.
- `main.dart` → split into screens and services (see the structure below).
- `config.dart` → `app/lib/config.dart` with `TOKEN_URL` and feature flags only.

### Delete
`backboard_store.py`, `.backboard.json`, `obstacle.py`, `test_obstacle_local.py`, `tests/test_obstacle.py`, `yolov8n.onnx`, `scripts/download_yolov8n_onnx.py`, `mcp_client/`, `run_app.sh`, `run_app_release.sh`, `run_simulator.sh`, `UPGRADE.md`, `CONFIG.md`, `devtools_options.yaml`, `.DS_Store`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`, the `dart_jsonwebtoken`, `record` and `image` packages, and the ElevenLabs and Backboard dependencies. Also drop `opencv-python`, `ultralytics`, `onnx`, `onnxslim` and `pillow` from the agent (`ultralytics` moves to `/ml`).

---

## 3. Target folder structure

```
safe-step/
├── CLAUDE.md
├── README.md
├── .gitignore
├── docs/
│   ├── MIGRATION.md            ← this file
│   ├── ARCHITECTURE.md         (Phase 1: data topics, sequence diagrams)
│   ├── PROTOCOL.md             (data-message schemas: gps, mode, hazard_event, prefs)
│   └── TESTING.md              (Phase 5)
├── agent/                      Python, uv-managed
│   ├── pyproject.toml
│   ├── .env.example
│   ├── safestep_agent/
│   │   ├── main.py             AgentServer entrypoint, agent_name="safestep"
│   │   ├── config.py           models, VAD, timeouts (no secrets)
│   │   ├── prompts.py          system prompt per language and mode
│   │   ├── session_state.py    mode, language, silenced classes
│   │   ├── protocol.py         topic names and payload dataclasses (mirrors docs/PROTOCOL.md)
│   │   ├── latency.py          end of user speech → first audio frame logger
│   │   ├── tools/
│   │   │   ├── mode.py         set_mode, quiet_minor_warnings
│   │   │   └── navigation.py   (Phase 2) LLM-facing nav tools
│   │   ├── nav/
│   │   │   ├── tracker.py      (Phase 2) ported navigation.py plus re-routing
│   │   │   └── maps.py         (Phase 2) Routes + Places (New) client
│   │   └── tts/
│   │       └── yarngpt.py      custom LiveKit TTS plugin (streaming)
│   ├── token_server/
│   │   └── app.py              tiny FastAPI app: POST /token → {url, token}, dispatches the agent
│   └── tests/
├── app/                        Flutter, Android only
│   ├── pubspec.yaml
│   ├── android/                package ng.safestep.app
│   ├── assets/
│   │   ├── models/             yolov8n.tflite (placeholder), labels.txt
│   │   ├── alerts/<lang>/<class>.mp3   pre-recorded hazard clips (Phase 3)
│   │   └── onboarding/<lang>/*.mp3     pre-recorded onboarding prompts
│   └── lib/
│       ├── main.dart           bootstrap and routing only
│       ├── config.dart         TOKEN_URL and flags (no secrets)
│       ├── theme.dart          high-contrast dark theme
│       ├── l10n/strings.dart   en, pcm, yo, ha, ig strings for TalkBack and status
│       ├── models/             Language, AppMode, Hazard, SavedPlace
│       ├── screens/
│       │   ├── onboarding_screen.dart
│       │   └── guide_screen.dart   full-screen gestures and status card
│       ├── services/
│       │   ├── prefs_service.dart       shared_preferences
│       │   ├── token_client.dart        calls the token server
│       │   ├── livekit_service.dart     room, data topics, audio ducking hooks
│       │   ├── location_service.dart    GPS and compass
│       │   ├── prompt_player.dart       plays bundled clips (onboarding, alerts)
│       │   ├── local_phrases.dart       (Phase 3) offline command matcher
│       │   ├── detector_service.dart    (Phase 3) YOLOv8n TFLite
│       │   ├── hazard_policy.dart       (Phase 3) path region, debounce, silencing
│       │   ├── alert_player.dart        (Phase 3) clip plus vibration, ducking
│       │   └── foreground_service.dart  (Phase 4)
│       └── widgets/status_card.dart
└── ml/
    ├── README.md               dataset plan, class list, export steps
    ├── classes.yaml            the 10 SafeStep classes and severities
    └── scripts/export_tflite.py   (stock yolov8n → TFLite placeholder; fine-tuned later)
```

---

## 4. Key design decisions (please confirm)

1. **Token server.** A small FastAPI service in `agent/token_server/`. The app sends `POST /token {language, mode}`. The server creates a unique room name and identity, and signs a token with `RoomConfiguration(agents=[RoomAgentDispatch(agent_name="safestep", metadata={"language":…, "mode":…})])`. It returns `{url, token, room}`. Because the room is new on every connect, token-based dispatch works reliably; LiveKit ignores that config for rooms that already exist. Protection for the hackathon: a per-install random ID plus simple rate limiting, no accounts. It can be deployed next to the agent or on any small host.
2. **TTS chain.** `tts.FallbackAdapter([YarnGPTTTS(...), spitch.TTS(...)])`. The YarnGPT plugin raises `APIStatusError` on 429 and `APITimeoutError` on timeout (time to first byte above roughly 1.5 s), so the adapter switches to Spitch. *(Phase 1)* Implemented on YarnGPT's real-time route `POST /api/v1/streaming/conversation` with `output_format: pcm`. The sample rate is read from the `Content-Type` header and resampled to 24 kHz. A fresh `Idempotency-Key` is sent per request. A first-byte timeout of 2 s, and a cooldown after a 429 or 402, make the fallback fast. Voices come from `YARNGPT_VOICE_<LANG>` (blank means YarnGPT's default), because YarnGPT says not to hardcode voice ids.
3. **STT.** `livekit-plugins-spitch` (current docs show `spitch.STT(language="en")`, `spitch.TTS(language=…, voice=…)` and `SPITCH_API_KEY`). Language codes are to be confirmed against Spitch docs; Pidgin support in Spitch STT/TTS needs checking. If Pidgin is unsupported, the fallback is English STT with a Pidgin-aware prompt.
4. **Language at onboarding before any network.** Onboarding prompts are **pre-recorded clips** bundled in the app, so onboarding works offline and before the agent connects. Choosing a language by voice uses on-device Android speech recognition, matching a tiny fixed word list (e.g. "English", "Pidgin", "Yoruba", "Hausa", "Igbo" and their native names), with a tap-count fallback (tap 1–5 times). *(Phase 1)* Implemented with Android's recogniser (`speech_to_text`) plus tap counting. Clips come from `assets/onboarding/prompts.json`, generated by `agent/scripts/generate_onboarding_audio.py`. When a clip is missing, Android TTS reads the text instead.
5. **Modes.** Mode is owned by the phone and mirrored to the agent. The agent's `set_mode` tool publishes `{"mode": …}` on topic `mode`, and the phone's offline phrase matcher can switch to `hazard_detection` with no network. In `navigation`, hazard detection is forced on. Critical classes (`open_gutter`, `open_manhole`, `okada`) are never silenced.
6. **Hazard event flow (Phase 3).** The phone detects, ducks agent audio (mutes the remote audio track locally), plays the clip and vibration, unducks, then sends `hazard_event {class, side, distance_band}` on topic `hazard`. The agent replies with a short "make we continue"-style line in the user's language. The agent does **not** interrupt itself for hazards.
7. **Routes API instead of the legacy Directions API (Phase 2).** Routes API `computeRoutes` with `WALK`. Landmark-first phrasing comes from step `navigationInstruction` and `landmarks` where available, plus nearby Places for anchors.
8. **No new paid services** beyond those named in the brief (LiveKit Cloud, Spitch, YarnGPT, Gemini, Google Maps). Hosting for the token server and agent is still to be decided; I'll ask before choosing.

---

## 5. Phase 1 scope (after approval)

1. Skeleton: `/app`, `/agent`, `/ml`, `/docs`, `.env.example` files, and the BlindSpot files ported as listed above.
2. Token server with tests (token claims, agent dispatch metadata, no secret leaves the server).
3. Agent voice loop: Spitch STT → Gemini Flash → YarnGPT TTS with a Spitch fallback, multilingual prompt, `set_mode` stub publishing to the phone, and a latency logger (`user_state` → `speaking` to first TTS frame, written as JSON lines).
4. Flutter app: Android-only project, dark theme, voice onboarding (pre-recorded clips plus language selection), prefs service, token client, LiveKit connect with language and mode, and a basic guide screen with a status card.

Phases 2–5 follow the brief and are not started.
