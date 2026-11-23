"""LLM tools for navigation. Turn prompts are spoken by the tracker, not the LLM."""

from __future__ import annotations

from livekit.agents import RunContext, function_tool

from .. import protocol
from ..nav.controller import NavigationController
from ..prompts import build_instructions
from ..session_state import SessionState
from .mode import Publisher, publish_to_phone


def make_navigation_tools(nav: NavigationController, publish: Publisher = publish_to_phone) -> list:
    async def _enter_mode(context: RunContext[SessionState], mode: str) -> None:
        state = context.userdata
        if state.set_mode(mode):
            await context.session.current_agent.update_instructions(build_instructions(state.language, state.mode))
            await publish(protocol.TOPIC_MODE, {"mode": mode, "source": "agent"})

    @function_tool
    async def search_places(context: RunContext[SessionState], query: str) -> str:
        """Find up to 3 nearby places for a general request like "a pharmacy" or "somewhere to eat",
        so the user can pick one. Then call start_navigation with the chosen name.

        Args:
            query: what to look for, e.g. "pharmacy" or "Shoprite Lekki".
        """
        if nav.position is None:
            return "NO_GPS: no location yet."
        try:
            places = await nav.maps.search_text(query, nav.position, max_results=3)
        except Exception:  # noqa: BLE001 - user-safe message only
            return "NETWORK: search failed."
        if not places:
            return "NOT_FOUND"
        lines = [f"{i}. {p.name}" + (f", {p.address.split(',')[0]}" if p.address else "") for i, p in enumerate(places, 1)]
        return "Read these short options and ask which one: " + " ".join(lines)

    @function_tool
    async def start_navigation(context: RunContext[SessionState], destination: str) -> str:
        """Start walking directions to a named place, address or saved place.
        Use when the user says "take me to ..." or picks a search result.

        Args:
            destination: the place name or address, e.g. "Lekki Phase 1 market" or "home".
        """
        result = await nav.start(destination)
        if result.startswith("ROUTE_STARTED"):
            await _enter_mode(context, "navigation")
        return result

    @function_tool
    async def stop_navigation(context: RunContext[SessionState]) -> str:
        """Stop the current walking directions. Hazard warnings continue."""
        nav.stop()
        await _enter_mode(context, "hazard_detection")
        return "Navigation stopped; hazard warnings are still on. Confirm in a few words."

    @function_tool
    async def where_am_i(context: RunContext[SessionState]) -> str:
        """Tell the user where they are, landmark first."""
        return await nav.where_am_i()

    @function_tool
    async def save_place(context: RunContext[SessionState], name: str) -> str:
        """Save the user's current location under a name like "home" or "church" on their phone.

        Args:
            name: short name for this place.
        """
        if nav.position is None:
            return "NO_GPS: no location yet."
        lat, lng = nav.position
        nav.saved_places[name.strip()] = (lat, lng)
        await publish(protocol.TOPIC_PLACE_SAVED, {"name": name.strip(), "lat": lat, "lng": lng})
        return f"Saved as {name}. Confirm in a few words."

    @function_tool
    async def list_saved_places(context: RunContext[SessionState]) -> str:
        """List the user's saved places."""
        return ", ".join(nav.saved_places) or "No saved places yet."

    return [search_places, start_navigation, stop_navigation, where_am_i, save_place, list_saved_places]
