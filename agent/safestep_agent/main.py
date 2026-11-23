"""SafeStep agent worker.

Run locally:   uv run python -m safestep_agent.main dev
Console test:  uv run python -m safestep_agent.main console   (uses your laptop mic/speaker)
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

from livekit import rtc  # noqa: E402
from livekit.agents import (  # noqa: E402
    Agent,
    AgentServer,
    AgentSession,
    JobContext,
    JobProcess,
    cli,
    room_io,
)
from livekit.agents.voice.events import (  # noqa: E402
    AgentStateChangedEvent,
    MetricsCollectedEvent,
    UserStateChangedEvent,
)
from livekit.plugins import google, noise_cancellation, silero  # noqa: E402

from . import config, protocol  # noqa: E402
from .latency import LatencyTracker, jsonl_sink  # noqa: E402
from .prompts import build_instructions  # noqa: E402
from .session_state import SessionState  # noqa: E402
from .speech import build_stt, build_tts  # noqa: E402
from .nav.controller import NavigationController  # noqa: E402
from .nav.maps import MapsClient  # noqa: E402
from .tools.mode import make_mode_tools  # noqa: E402
from .tools.navigation import make_navigation_tools  # noqa: E402

logger = logging.getLogger("safestep.agent")


def _thinking_config(model: str) -> dict:
    # Gemini 3+ takes a thinking level, 2.x a token budget. Keep thinking minimal for latency.
    m = model.lower()
    if m.startswith("gemini-2"):
        return {"thinking_budget": 0}
    return {"thinking_level": "minimal"}


class SafeStepAgent(Agent):
    def __init__(self, state: SessionState, nav: NavigationController) -> None:
        super().__init__(
            instructions=build_instructions(state.language, state.mode),
            tools=make_mode_tools() + make_navigation_tools(nav),
        )


def prewarm(proc: JobProcess) -> None:
    proc.userdata["vad"] = silero.VAD.load(
        min_speech_duration=config.VAD_MIN_SPEECH_DURATION,
        min_silence_duration=config.VAD_MIN_SILENCE_DURATION,
        activation_threshold=config.VAD_ACTIVATION_THRESHOLD,
    )


server = AgentServer(setup_fnc=prewarm)


@server.rtc_session(agent_name=config.AGENT_NAME)
async def entrypoint(ctx: JobContext) -> None:
    meta = protocol.DispatchMetadata.parse(ctx.job.metadata)
    state = SessionState.create(meta.language, meta.mode)
    lang = state.language
    logger.info("session start room=%s language=%s mode=%s", ctx.room.name, lang.code, state.mode)

    session: AgentSession[SessionState] = AgentSession(
        stt=build_stt(lang),
        llm=google.LLM(
            model=config.GEMINI_MODEL,
            temperature=config.LLM_TEMPERATURE,
            max_output_tokens=config.LLM_MAX_OUTPUT_TOKENS,
            thinking_config=_thinking_config(config.GEMINI_MODEL),
        ),
        tts=build_tts(lang),
        vad=ctx.proc.userdata["vad"],
        turn_handling={
            "turn_detection": "vad",
            "endpointing": {"min_delay": config.ENDPOINTING_MIN_DELAY},
        },
        userdata=state,
    )

    # --- latency logging ---
    tracker = LatencyTracker(
        session_id=ctx.room.name or "unknown",
        language=lang.code,
        mode=state.mode,
        vad_silence_s=config.VAD_MIN_SILENCE_DURATION,
        sink=jsonl_sink(config.LATENCY_LOG_PATH),
    )

    @session.on("user_state_changed")
    def _on_user_state(ev: UserStateChangedEvent) -> None:
        tracker.on_user_state(ev.old_state, ev.new_state, ev.created_at)

    @session.on("agent_state_changed")
    def _on_agent_state(ev: AgentStateChangedEvent) -> None:
        tracker.mode = state.mode
        tracker.on_agent_state(ev.new_state, ev.created_at)

    @session.on("metrics_collected")
    def _on_metrics(ev: MetricsCollectedEvent) -> None:
        tracker.on_metrics(ev.metrics)

    # --- navigation: the tracker speaks turns itself, without the LLM ---
    def _speak_nav(text: str, urgent: bool) -> None:
        try:
            if urgent:
                session.interrupt()
            session.say(text, allow_interruptions=not urgent)
        except RuntimeError as e:
            logger.debug("nav say failed: %s", e)

    maps = MapsClient()
    nav = NavigationController(maps, lang.code, _speak_nav)
    ctx.add_shutdown_callback(maps.aclose)

    # --- data messages from the phone ---
    def _on_data(packet: rtc.DataPacket) -> None:
        payload = protocol.decode(packet.data)
        if payload is None:
            return
        if packet.topic == protocol.TOPIC_MODE and payload.get("source") == "phone":
            # phone switched mode by itself (offline phrase); keep the agent in sync
            mode = str(payload.get("mode", ""))
            if mode in protocol.MODES and state.set_mode(mode):
                logger.info("mode synced from phone -> %s", mode)
                asyncio.create_task(
                    session.current_agent.update_instructions(
                        build_instructions(state.language, state.mode)
                    )
                )
        elif packet.topic == protocol.TOPIC_GPS:
            try:
                nav.on_gps(
                    float(payload["lat"]),
                    float(payload["lng"]),
                    _opt_float(payload.get("heading")),
                    _opt_float(payload.get("accuracy")),
                )
            except (KeyError, TypeError, ValueError):
                pass
        elif packet.topic == protocol.TOPIC_PLACES:
            for p in payload.get("places") or []:
                try:
                    nav.saved_places[str(p["name"])] = (float(p["lat"]), float(p["lng"]))
                except (KeyError, TypeError, ValueError):
                    continue
        elif packet.topic == protocol.TOPIC_HAZARD:
            # Phone already played the offline alert; just help the user carry on.
            logger.info("hazard_event %s", payload)
            asyncio.create_task(_say_continue())

    async def _say_continue() -> None:
        try:
            session.say(lang.continue_line, allow_interruptions=True)
        except RuntimeError as e:
            logger.debug("say continue failed: %s", e)

    ctx.room.on("data_received", _on_data)

    await session.start(
        room=ctx.room,
        agent=SafeStepAgent(state, nav),
        room_options=room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=lambda params: noise_cancellation.BVCTelephony()
                if params.participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_SIP
                else noise_cancellation.BVC(),
            ),
        ),
    )
    session.say(lang.greeting, allow_interruptions=True)


def _opt_float(v: object) -> float | None:
    try:
        return None if v is None else float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


if __name__ == "__main__":
    cli.run_app(server)
