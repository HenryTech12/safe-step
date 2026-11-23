# SafeStep phone ⇄ agent protocol

Source of truth in code: `agent/safestep_agent/protocol.py` and `app/lib/services/protocol.dart`.

## Getting into a room

1. App → token server: `POST /token`
   ```json
   {"language": "yo", "mode": "hazard_detection", "install_id": "<random per install>"}
   ```
   - `language`: `en` | `pcm` | `yo` | `ha` | `ig`
   - `mode`: `hazard_detection` | `navigation`
   - `install_id`: 8–64 chars `[A-Za-z0-9_-]`. Used only for rate limiting (default 6 requests per minute per install and per IP).
2. Token server → app: `{"url", "token", "room", "identity"}`. A new room is created on every call.
3. The token carries `RoomConfiguration.agents = [RoomAgentDispatch(agent_name="safestep", metadata='{"language":"yo","mode":"hazard_detection"}')]`, so LiveKit dispatches the agent when the phone joins. The agent reads this from `ctx.job.metadata`.

The LiveKit API secret exists only on the token server.

## Agent state

The agent publishes `lk.agent.state` as a participant attribute (`initializing`, `listening`, `thinking`, `speaking`, `idle`). The app's status card shows it.

## Data messages (reliable, JSON, UTF-8)

| Topic | Direction | Payload | Phase |
|---|---|---|---|
| `mode` | agent → phone | `{"mode": "navigation", "source": "agent"}` sent by the `set_mode` tool | 1 |
| `mode` | phone → agent | `{"mode": "hazard_detection", "source": "phone"}` sent after an offline phrase switches mode | 1 (agent side) / 3 (phone matcher) |
| `warnings` | agent → phone | `{"minor_silenced": true}` sent by `quiet_minor_warnings`. Critical classes are never silenced. | 1 (agent) / 3 (phone) |
| `hazard_event` | phone → agent | `{"class": "open_gutter", "side": "left", "distance_band": "near"}`, sent **after** the phone has played its own alert. The agent answers with a short "Make we continue." | 1 (agent) / 3 (phone) |
| `gps` | phone → agent | `{"lat": 6.5, "lng": 3.4, "accuracy": 5, "heading": 90}`, sent on each 3 m move and every 3 s (lossy) | 2 |
| `places` | phone → agent | `{"places": [{"name": "home", "lat": .., "lng": ..}]}`, sent once after connecting | 2 |
| `place_saved` | agent → phone | `{"name", "lat", "lng"}`, sent by the `save_place` tool; the phone stores it | 2 |

Critical classes: `open_gutter`, `open_manhole`, `okada`.
