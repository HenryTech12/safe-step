"""Geometry helpers (ported from BlindSpot navigation.py, plus polyline maths)."""

from __future__ import annotations

import math
from typing import Sequence

LatLng = tuple[float, float]
EARTH_R = 6_371_000.0


def haversine(a: LatLng, b: LatLng) -> float:
    """Distance in metres."""
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def bearing(a: LatLng, b: LatLng) -> float:
    """Bearing from a to b, degrees, 0 = north, 90 = east."""
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def cardinal(b: float) -> str:
    names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    return names[int(((b % 360) + 22.5) // 45) % 8]


def relative_direction(user_heading: float, target_bearing: float) -> str:
    """'ahead', 'right', 'left' or 'behind' from the user's point of view."""
    diff = (target_bearing - user_heading + 540) % 360 - 180
    if -45 <= diff <= 45:
        return "ahead"
    if 45 < diff <= 135:
        return "right"
    if -135 <= diff < -45:
        return "left"
    return "behind"


def decode_polyline(encoded: str) -> list[LatLng]:
    """Google encoded polyline (precision 5) → [(lat, lng), ...]."""
    points: list[LatLng] = []
    index = lat = lng = 0
    while index < len(encoded):
        for coord in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if coord == 0:
                lat += delta
            else:
                lng += delta
        points.append((lat / 1e5, lng / 1e5))
    return points


def _to_xy(p: LatLng, ref: LatLng) -> tuple[float, float]:
    # local equirectangular projection, accurate to well under a metre at street scale
    x = math.radians(p[1] - ref[1]) * EARTH_R * math.cos(math.radians(ref[0]))
    y = math.radians(p[0] - ref[0]) * EARTH_R
    return x, y


def distance_to_segment(p: LatLng, a: LatLng, b: LatLng) -> float:
    px, py = _to_xy(p, a)
    bx, by = _to_xy(b, a)
    seg2 = bx * bx + by * by
    t = 0.0 if seg2 == 0 else max(0.0, min(1.0, (px * bx + py * by) / seg2))
    dx, dy = px - t * bx, py - t * by
    return math.hypot(dx, dy)


def distance_to_polyline(p: LatLng, line: Sequence[LatLng]) -> float:
    if not line:
        return float("inf")
    if len(line) == 1:
        return haversine(p, line[0])
    return min(distance_to_segment(p, line[i], line[i + 1]) for i in range(len(line) - 1))
