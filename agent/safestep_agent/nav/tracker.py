"""GPS-driven turn tracker, independent of the LLM (ported from BlindSpot navigation.py).

Feed it GPS fixes; it returns language-neutral Announcements:
- "prepare" once at ~45 m before a turn, "now" at ~12 m (then moves on to the next step)
- "arrive" within ~15 m of the destination
- "off_route" once when the user is clearly away from the route line for 2 fixes in a row;
  the controller then fetches a new route and calls `replace_route`.
"""

from __future__ import annotations

import time
from typing import Callable

from .geo import LatLng, bearing, distance_to_polyline, haversine, relative_direction
from .phrases import Announcement
from .route import Route

PREPARE_M = 45.0
NOW_M = 12.0
ARRIVE_M = 15.0
OFF_ROUTE_M = 30.0
OFF_ROUTE_FIXES = 2
MAX_ACCURACY_M = 50.0  # ignore worse fixes for off-route and turn triggers
GRACE_S = 12.0  # after (re)routing, let the summary finish before turn prompts


class NavigationTracker:
    def __init__(self, route: Route, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self.replace_route(route)

    # --- public ---

    def replace_route(self, route: Route) -> None:
        self.route = route
        self.step_index = 0
        self._prepared: set[int] = set()
        self._off_count = 0
        self.off_route = False
        self.arrived = False
        self._started_at = self._clock()

    def start_announcement(self, heading: float | None, here: LatLng | None) -> Announcement:
        """Summary for the first instruction: where the route starts, then the first turn."""
        steps = self.route.steps
        first = steps[0]
        target = first.points[1] if len(first.points) > 1 else first.end
        rel = relative_direction(heading, bearing(here or first.start, target)) if heading is not None else None
        if len(steps) > 1:
            nxt = steps[1]
            follow = Announcement(
                kind="prepare",
                maneuver=nxt.maneuver,
                distance_m=first.distance_m,
                landmark=nxt.landmark,
                street=nxt.street,
            )
        else:
            follow = Announcement(kind="arrive", destination=self.route.destination_name or None)
        return Announcement(kind="start", relative=rel or "ahead", next=follow)

    def update(self, pos: LatLng, accuracy_m: float | None = None) -> list[Announcement]:
        if self.arrived:
            return []
        if accuracy_m is not None and accuracy_m > MAX_ACCURACY_M:
            return []
        steps = self.route.steps

        # arrival
        if haversine(pos, self.route.destination) <= ARRIVE_M:
            self.arrived = True
            return [Announcement(kind="arrive", destination=self.route.destination_name or None)]

        # off route?
        margin = max(OFF_ROUTE_M, (accuracy_m or 0) * 1.5)
        if distance_to_polyline(pos, self.route.points) > margin:
            self._off_count += 1
            if self._off_count >= OFF_ROUTE_FIXES and not self.off_route:
                self.off_route = True
                return [Announcement(kind="off_route")]
            return []
        self._off_count = 0
        self.off_route = False

        if self._clock() - self._started_at < GRACE_S:
            self._sync_step(pos)
            return []

        self._sync_step(pos)
        i = self.step_index
        if i + 1 >= len(steps):
            return []  # on the final step; arrival handles the rest
        turn = steps[i + 1]
        dist = haversine(pos, steps[i].end)
        if dist <= NOW_M:
            self.step_index = i + 1
            self._prepared.add(i + 1)
            return [
                Announcement(
                    kind="now", maneuver=turn.maneuver, landmark=turn.landmark, street=turn.street, urgent=True
                )
            ]
        if dist <= PREPARE_M and (i + 1) not in self._prepared:
            self._prepared.add(i + 1)
            return [
                Announcement(
                    kind="prepare",
                    maneuver=turn.maneuver,
                    distance_m=dist,
                    landmark=turn.landmark,
                    street=turn.street,
                )
            ]
        return []

    # --- internals ---

    def _sync_step(self, pos: LatLng) -> None:
        """If the user is clearly on a later step (missed a 'now'), jump ahead."""
        steps = self.route.steps
        i = self.step_index
        best, best_d = i, distance_to_polyline(pos, steps[i].points)
        for j in range(i + 1, min(i + 3, len(steps))):
            d = distance_to_polyline(pos, steps[j].points)
            if d + 5.0 < best_d:
                best, best_d = j, d
        if best != i:
            self.step_index = best
            self._prepared.update(range(i + 1, best + 1))
