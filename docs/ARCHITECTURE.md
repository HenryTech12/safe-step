# SafeStep architecture

```
 Phone (Flutter, Android)                                  Server side (yours to host)
 ─────────────────────────                                 ───────────────────────────
 Onboarding (offline clips, Android STT, taps) ──► prefs
                                                           token_server (FastAPI)
 GuideController ── POST /token {lang, mode} ───────────►  signs token + agent dispatch
   │                                                       (LiveKit secret lives here only)
   ├─ LiveKitService ◄═══ WebRTC audio + data ═══►  LiveKit Cloud ◄══► agent worker
   │     mic ↑  agent voice ↓ (paused during alerts)                 ├ Spitch STT
   │                                                                 ├ Gemini Flash + tools
   ├─ LocationService ── gps (lossy, 3 s / 3 m) ──────────────────►  │   mode, nav, scene
   │                                                                 ├ YarnGPT TTS → Spitch TTS
   ├─ HazardController (always on, OFFLINE)                          ├ NavigationController
   │     camera YUV → worker isolate: rotate, letterbox,             │   Routes v2, Places, landmarks
   │     YOLOv8n TFLite, NMS → HazardPolicy (path, 2/3,              │   tracker speaks turns itself
   │     cooldowns, critical never silenced) → AlertPlayer           └ LatencyTracker → latency.jsonl
   │     (vibration + clip) → hazard_event ──────────────────────►  "Make we continue."
   ├─ offline phrases (double tap while offline)
   └─ GuidanceService (foreground service: camera|mic|location)
```

## Design rules

- **Hazards never depend on the network.** Detection, the decision to warn, the clip and the vibration all run on the phone. The agent is told afterwards (`hazard_event`) only so it can say a short line to carry on.
- **The LLM never drives turn prompts.** `NavigationTracker` turns GPS fixes into prepare/now/arrive/off-route announcements. These are phrased per language from Routes API maneuver types and spoken directly with `session.say`. The LLM only starts and stops routes and answers questions.
- **No continuous video upload.** Scene description sends one JPEG when asked (`frame_request` → `camera_frame` byte stream).
- **No secrets in the app.** The app knows only `TOKEN_URL`.

## Where things live

| Concern | Agent (`agent/safestep_agent`) | App (`app/lib`) |
|---|---|---|
| Entry / wiring | `main.py` | `main.dart`, `guide/guide_controller.dart` |
| Languages | `languages.py`, `prompts.py`, `nav/phrases.py` | `models/language.dart`, `l10n/strings.dart`, `assets/*/*.json` |
| Speech | `speech.py`, `tts/yarngpt.py` | `services/prompt_player.dart`, `hazard/alert_player.dart` |
| Modes / warnings | `tools/mode.py`, `session_state.py` | `hazard/local_phrases.dart`, `hazard/hazard_policy.dart` |
| Navigation | `nav/*`, `tools/navigation.py` | `services/location_service.dart` |
| Hazards | – | `hazard/*` |
| Scene | `scene.py`, `tools/scene.py` | `GuideController._sendFrame` |
| Latency | `latency.py` | `HazardDetector.avgMs` (shown in demo mode) |
| Demo | – | `demo/*`, `ml/scripts/video_to_frames.py` |
