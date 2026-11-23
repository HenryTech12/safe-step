"""Route model parsed from the Google Routes API (v2 computeRoutes) JSON response."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from .geo import LatLng, decode_polyline

# Fields we ask for (X-Goog-FieldMask). Keep small: cost and latency scale with it.
ROUTES_FIELD_MASK = ",".join(
    [
        "routes.distanceMeters",
        "routes.duration",
        "routes.polyline.encodedPolyline",
        "routes.legs.endLocation",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.staticDuration",
        "routes.legs.steps.polyline.encodedPolyline",
        "routes.legs.steps.startLocation",
        "routes.legs.steps.endLocation",
        "routes.legs.steps.navigationInstruction",
    ]
)

_STREET_RE = re.compile(r"\b(?:onto|on|toward|towards)\s+(.+?)(?:\s*(?:Destination|Pass by|Restricted).*)?$", re.I)


@dataclass
class Step:
    maneuver: str  # Routes API Maneuver enum name, e.g. TURN_LEFT
    instruction: str  # provider text (English), used for street names only
    distance_m: float
    start: LatLng
    end: LatLng
    points: list[LatLng] = field(default_factory=list)
    landmark: str | None = None  # nearby named place at the start of this step (the turn)

    @property
    def street(self) -> str | None:
        m = _STREET_RE.search(self.instruction or "")
        return m.group(1).strip().rstrip(".") if m else None


@dataclass
class Route:
    steps: list[Step]
    distance_m: float
    duration_s: float
    points: list[LatLng]
    destination: LatLng
    destination_name: str = ""


def _latlng(loc: dict[str, Any] | None) -> LatLng | None:
    if not loc:
        return None
    ll = loc.get("latLng") or {}
    if "latitude" not in ll or "longitude" not in ll:
        return None
    return float(ll["latitude"]), float(ll["longitude"])


def _seconds(v: Any) -> float:
    # proto Duration in JSON is a string like "123s"
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str) and v.endswith("s"):
        try:
            return float(v[:-1])
        except ValueError:
            return 0.0
    return 0.0


def parse_route(data: dict[str, Any], destination_name: str = "") -> Route | None:
    routes = data.get("routes") or []
    if not routes:
        return None
    r = routes[0]
    legs = r.get("legs") or []
    if not legs:
        return None
    steps: list[Step] = []
    for s in legs[0].get("steps") or []:
        start, end = _latlng(s.get("startLocation")), _latlng(s.get("endLocation"))
        if start is None or end is None:
            continue
        nav = s.get("navigationInstruction") or {}
        enc = (s.get("polyline") or {}).get("encodedPolyline") or ""
        steps.append(
            Step(
                maneuver=str(nav.get("maneuver") or "MANEUVER_UNSPECIFIED"),
                instruction=str(nav.get("instructions") or ""),
                distance_m=float(s.get("distanceMeters") or 0),
                start=start,
                end=end,
                points=decode_polyline(enc) if enc else [start, end],
            )
        )
    if not steps:
        return None
    enc = (r.get("polyline") or {}).get("encodedPolyline") or ""
    points = decode_polyline(enc) if enc else [p for st in steps for p in st.points]
    dest = _latlng(legs[-1].get("endLocation")) or steps[-1].end
    return Route(
        steps=steps,
        distance_m=float(r.get("distanceMeters") or sum(s.distance_m for s in steps)),
        duration_s=_seconds(r.get("duration")),
        points=points,
        destination=dest,
        destination_name=destination_name,
    )
