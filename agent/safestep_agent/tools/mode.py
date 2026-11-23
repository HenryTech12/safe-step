"""LLM tools for switching modes and quieting minor warnings.

The phone owns hazard detection, so every change is mirrored to it as a data message.
"""

from __future__ import annotations

import logging
from typing import Awaitable, Callable, Literal

from livekit.agents import RunContext, function_tool, get_job_context

from .. import protocol
from ..prompts import build_instructions
from ..session_state import SessionState

logger = logging.getLogger("safestep.tools")

Publisher = Callable[[str, dict], Awaitable[None]]


async def publish_to_phone(topic: str, payload: dict) -> None:
    room = get_job_context().room
    await room.local_participant.publish_data(protocol.encode(payload), topic=topic, reliable=True)


def make_mode_tools(publish: Publisher = publish_to_phone) -> list:
    @function_tool
    async def set_mode(
        context: RunContext[SessionState],
        mode: Literal["hazard_detection", "navigation"],
    ) -> str:
        """Switch SafeStep's mode.

        Args:
            mode: "hazard_detection" for hazard warnings only, or "navigation" for
                turn-by-turn directions plus hazard warnings.
        """
        state = context.userdata
        if state.set_mode(mode):
            await context.session.current_agent.update_instructions(
                build_instructions(state.language, state.mode)
            )
        await publish(protocol.TOPIC_MODE, {"mode": mode, "source": "agent"})
        logger.info("mode -> %s", mode)
        if mode == "navigation":
            return (
                "Navigation mode is on and hazard warnings stay on. "
                "If no destination is set yet, ask where they want to go."
            )
        return "Hazard warning mode is on. Confirm in a few words."

    @function_tool
    async def quiet_minor_warnings(context: RunContext[SessionState], quiet: bool) -> str:
        """Quiet or restore warnings for minor hazards (people, poles, tables, potholes, kerbs, debris,
        vehicles). Open gutters, open manholes and okadas are always announced.

        Args:
            quiet: true to quiet minor warnings, false to turn them back on.
        """
        state = context.userdata
        state.minor_silenced = quiet
        await publish(protocol.TOPIC_WARNINGS, {"minor_silenced": quiet})
        if quiet:
            return (
                "Minor warnings are quiet. Tell the user that open gutters, open manholes "
                "and okadas will still be announced."
            )
        return "All warnings are on again."

    return [set_mode, quiet_minor_warnings]
