"""Navigation controller: owns the latest GPS fix, the active route and re-routing.

The tracker speaks turns by itself through `speak`; the LLM only starts/stops navigation
and answers questions, so turn prompts never wait on the LLM.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Callable

from .geo import LatLng
from .maps import MapsClient, MapsError
from .phrases import Announcement, render
from .route import Route
from .tracker import NavigationTracker

logger = logging.getLogger("safestep.nav")

REROUTE_COOLDOWN_S = 20.0
LANDMARK_TIMEOUT_S = 3.0

Speak = Callable[[str, bool], None]  # (text, urgent)


class NavigationController:
    def __init__(
        self,
        maps: MapsClient,
        language: str,
        speak: Speak,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.maps = maps
        self.language = language
        self._speak = speak
        self._clock = clock
        self.position: LatLng | None = None
        self.heading: float | None = None
        self.accuracy: float | None = None
        self.tracker: NavigationTracker | None = None
        self._destination: LatLng | None = None
        self._destination_name = ""
        self._last_reroute = -1e9
        self._reroute_task: asyncio.Task | None = None
        self.saved_places: dict[str, LatLng] = {}

    @property
    def active(self) -> bool:
        return self.tracker is not None and not self.tracker.arrived

    # --- GPS ---

    def on_gps(self, lat: float, lng: float, heading: float | None, accuracy: float | None) -> None:
        self.position = (lat, lng)
        if heading is not None:
            self.heading = heading
        self.accuracy = accuracy
        if not self.tracker:
            return
        for a in self.tracker.update(self.position, accuracy):
            self._say(a)
            if a.kind == "off_route":
                self._schedule_reroute()
            elif a.kind == "arrive":
                self.tracker = None

    # --- starting / stopping ---

    async def start(self, query: str) -> str:
        """Find the destination, compute a walking route, start tracking.
        Returns text for the LLM (the first instruction is to be read out as is)."""
        if self.position is None:
            return "NO_GPS: the phone has not sent a location yet. Ask the user to wait a moment."
        try:
            dest, name = await self._resolve(query)
            route = await self.maps.walking_route(self.position, dest, name)
        except MapsError as e:
            return _error_text(e)
        await self._landmarks(route)
        self._destination, self._destination_name = dest, name
        self.tracker = NavigationTracker(route, clock=self._clock)
        first = render(self.tracker.start_announcement(self.heading, self.position), self.language)
        minutes = max(1, round(route.duration_s / 60)) if route.duration_s else None
        eta = f", about {minutes} minutes walking" if minutes else ""
        return (
            f"ROUTE_STARTED to {name}: {round(route.distance_m)} metres{eta}. "
            f"Say the destination and time in one short sentence, then read this first instruction "
            f"exactly: \"{first}\""
        )

    def stop(self) -> None:
        self.tracker = None
        self._destination = None
        if self._reroute_task:
            self._reroute_task.cancel()

    async def _resolve(self, query: str) -> tuple[LatLng, str]:
        q = query.strip()
        for name, ll in self.saved_places.items():
            if name.lower() == q.lower() or name.lower() in q.lower():
                return ll, name
        places = await self.maps.search_text(q, self.position, max_results=1)
        if not places or places[0].location is None:
            raise MapsError("not_found", q)
        p = places[0]
        return p.location, p.name

    async def _landmarks(self, route: Route) -> None:
        try:
            await asyncio.wait_for(self.maps.add_landmarks(route), LANDMARK_TIMEOUT_S)
        except (asyncio.TimeoutError, MapsError):
            logger.info("landmarks skipped (slow or unavailable)")

    # --- re-routing ---

    def _schedule_reroute(self) -> None:
        if self._reroute_task and not self._reroute_task.done():
            return
        if self._clock() - self._last_reroute < REROUTE_COOLDOWN_S:
            return
        self._last_reroute = self._clock()
        self._reroute_task = asyncio.create_task(self.reroute())

    async def reroute(self) -> None:
        if self.position is None or self._destination is None or self.tracker is None:
            return
        try:
            route = await self.maps.walking_route(self.position, self._destination, self._destination_name)
        except MapsError as e:
            logger.warning("reroute failed: %s", e)
            self._say(Announcement(kind="reroute_failed"))
            return
        await self._landmarks(route)
        if self.tracker is None:  # stopped meanwhile
            return
        self.tracker.replace_route(route)
        first = self.tracker.start_announcement(self.heading, self.position)
        self._say(Announcement(kind="rerouted", next=first))

    # --- where am I ---

    async def where_am_i(self) -> str:
        if self.position is None:
            return "NO_GPS: no location yet."
        landmark = await self.maps.nearest_landmark(self.position, radius_m=60)
        try:
            address = await self.maps.reverse_geocode(self.position)
        except MapsError:
            address = None
        parts = []
        if landmark:
            parts.append(f"nearest landmark: {landmark}")
        if address:
            parts.append(f"address: {address}")
        if not parts:
            return "UNKNOWN: could not find a place name for this location."
        return "LOCATION " + "; ".join(parts) + ". Say the landmark first, then the street, briefly."

    def _say(self, a: Announcement) -> None:
        text = render(a, self.language)
        if text:
            self._speak(text, a.urgent)


def _error_text(e: MapsError) -> str:
    return {
        "not_configured": "MAPS_UNAVAILABLE: directions are not set up. Apologise briefly.",
        "denied": "MAPS_UNAVAILABLE: directions service refused. Apologise briefly.",
        "not_found": "NOT_FOUND: no place matched. Ask the user to say the name another way.",
        "no_route": "NO_ROUTE: no walking route found. Suggest a nearby place instead.",
        "network": "NETWORK: could not reach the directions service. Hazard warnings still work.",
    }.get(e.kind, "ERROR: directions failed.")
