# Testing SafeStep

## Automated (no keys, no network)

```bash
cd agent && uv run pytest     # 52 tests: token server, YarnGPT plugin + fallback, latency,
                              # navigation (geo, parsing, phrasing, tracker, re-route), scene, repo hygiene
cd app && flutter test        # 24 tests: onboarding flow, language matching, token client, YOLO decoding,
                              # rotation/letterbox, hazard policy, offline phrases, assets/strings, prefs
```

## On a phone (needs keys in `agent/.env`)

1. Start the agent (`uv run python -m safestep_agent.main dev`) and the token server.
2. Generate the clips: `uv run python scripts/generate_onboarding_audio.py`.
3. `flutter run --dart-define=TOKEN_URL=http://<laptop-ip>:8765` (add `--dart-define=DEMO=true` for demo mode).

| Check | How | Expect |
|---|---|---|
| Onboarding by voice | Fresh install; tap; say "Yoruba" | Confirmation in Yoruba; camera/location asked; agent greets in Yoruba |
| Onboarding by taps | Tap 4 times at the language prompt | Hausa |
| Language fallback | Stay silent 3 times | English |
| Agent loop | Ask "where am I?" | Landmark first, then street |
| TTS fallback | Set a wrong `YARNGPT_API_KEY` | Spitch voice answers; log shows "TTS fell back" |
| Navigation | "Take me to the nearest pharmacy", walk | Options read out; turns at about 45 m and 12 m with a landmark; arrival |
| Re-route | Walk off the route for about 40 m | "You have left the route…", then a new first instruction |
| Hazard (placeholder) | Point at a motorbike or person in the path | Vibration + clip; agent pauses, then "Make we continue." (for a critical alert, or if it was speaking) |
| Path only | Person at the far edge of the frame | No alert |
| Silence minor | "Stop warning me" | Persons/poles quiet; motorbike (okada) still alerts |
| Offline mode | Airplane mode, double tap, say "warnings only" | Spoken confirmation; alerts keep working |
| Screen off | Lock the phone mid-route | Notification stays; turns and alerts continue |
| Gestures | Swipe down / long press | Agent voice muted / last line repeated |
| Scene | "What is in front of me?" | Two-sentence description |
| Latency | After 10 turns, inspect `agent/logs/latency.jsonl` | `speech_end_to_audio_ms` per turn |
| Demo | Push frames, open Demo mode | Boxes, path overlay, alerts, ms/frame |

## Latency summary

```bash
python -c "import json,statistics as s;r=[json.loads(l)['speech_end_to_audio_ms'] for l in open('agent/logs/latency.jsonl')];print(len(r),'turns, median',s.median(r),'ms, p90',sorted(r)[int(len(r)*.9)-1],'ms')"
```
