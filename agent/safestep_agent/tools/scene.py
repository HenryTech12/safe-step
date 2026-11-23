from __future__ import annotations

from livekit.agents import RunContext, function_tool

from ..scene import SceneDescriber
from ..session_state import SessionState


def make_scene_tools(scene: SceneDescriber) -> list:
    @function_tool
    async def describe_scene(context: RunContext[SessionState]) -> str:
        """Describe what is in front of the user right now, using one photo from the phone camera.
        Use when the user asks "what is in front of me?", "what do you see?" or similar."""
        return await scene.describe()

    return [describe_scene]
