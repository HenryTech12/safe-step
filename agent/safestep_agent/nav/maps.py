"""Google Maps client: Routes API v2 (walking routes), Places API (New) and reverse geocoding.

Request/response field names were checked against Google's official generated clients
(google-maps-routing / google-maps-places on PyPI), because developers.google.com was
unreachable from the build machine. REST JSON uses the lowerCamelCase form of those fields.
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from typing import Any

import httpx

from .geo import LatLng
from .route import ROUTES_FIELD_MASK, Route, parse_route

logger = logging.getLogger("safestep.maps")

ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
PLACES_TEXT_URL = "https://places.googleapis.com/v1/places:searchText"
PLACES_NEARBY_URL = "https://places.googleapis.com/v1/places:searchNearby"
GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"

# Place types that make poor landmarks for a blind pedestrian ("at the route" is meaningless).
_NOT_LANDMARKS = {"route", "street_address", "premise", "plus_code", "locality", "political"}


class MapsError(Exception):
    """kind: not_configured | no_route | not_found | denied | network"""

    def __init__(self, kind: str, detail: str = "") -> None:
        super().__init__(f"{kind}: {detail}")
        self.kind = kind


@dataclass
class Place:
    name: str
    address: str
    location: LatLng | None


def _ll(lat: float, lng: float) -> dict[str, float]:
    return {"latitude": lat, "longitude": lng}


class MapsClient:
    def __init__(self, api_key: str | None = None, http: httpx.AsyncClient | None = None) -> None:
        self._key = (api_key if api_key is not None else os.environ.get("GOOGLE_MAPS_API_KEY", "")).strip()
        self._http = http or httpx.AsyncClient(timeout=httpx.Timeout(8.0, connect=4.0))

    @property
    def configured(self) -> bool:
        return bool(self._key)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _post(self, url: str, body: dict[str, Any], field_mask: str) -> dict[str, Any]:
        if not self._key:
            raise MapsError("not_configured")
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._key,
            "X-Goog-FieldMask": field_mask,
        }
        try:
            resp = await self._http.post(url, json=body, headers=headers)
        except httpx.HTTPError as e:
            raise MapsError("network", str(e)) from e
        if resp.status_code in (401, 403):
            raise MapsError("denied", resp.text[:300])
        if resp.status_code != 200:
            raise MapsError("network", f"{resp.status_code} {resp.text[:300]}")
        return resp.json()

    async def walking_route(
        self, origin: LatLng, destination: LatLng | str, destination_name: str = ""
    ) -> Route:
        dest: dict[str, Any] = (
            {"address": destination}
            if isinstance(destination, str)
            else {"location": {"latLng": _ll(*destination)}}
        )
        body = {
            "origin": {"location": {"latLng": _ll(*origin)}},
            "destination": dest,
            "travelMode": "WALK",
            "languageCode": "en",  # street names only; we phrase turns ourselves per language
            "regionCode": "NG",
            "units": "METRIC",
        }
        data = await self._post(ROUTES_URL, body, ROUTES_FIELD_MASK)
        route = parse_route(data, destination_name or (destination if isinstance(destination, str) else ""))
        if route is None:
            raise MapsError("no_route")
        return route

    async def search_text(self, query: str, near: LatLng | None, max_results: int = 3) -> list[Place]:
        body: dict[str, Any] = {"textQuery": query, "maxResultCount": max_results, "regionCode": "NG"}
        if near:
            body["locationBias"] = {"circle": {"center": _ll(*near), "radius": 5000.0}}
            body["rankPreference"] = "DISTANCE"
        data = await self._post(
            PLACES_TEXT_URL, body, "places.displayName,places.formattedAddress,places.location"
        )
        return [_place(p) for p in data.get("places") or []]

    async def nearest_landmark(self, at: LatLng, radius_m: float = 40.0) -> str | None:
        body = {
            "maxResultCount": 5,
            "rankPreference": "DISTANCE",
            "locationRestriction": {"circle": {"center": _ll(*at), "radius": radius_m}},
        }
        try:
            data = await self._post(
                PLACES_NEARBY_URL, body, "places.displayName,places.types,places.location"
            )
        except MapsError as e:
            logger.debug("landmark lookup failed: %s", e)
            return None
        for p in data.get("places") or []:
            types = set(p.get("types") or [])
            name = ((p.get("displayName") or {}).get("text") or "").strip()
            if name and not (types & _NOT_LANDMARKS):
                return name
        return None

    async def add_landmarks(self, route: Route, max_steps: int = 12) -> None:
        """Attach a nearby named place to each turn (step start), in parallel."""
        targets = route.steps[1 : max_steps + 1]  # step 0 starts where the user stands
        names = await asyncio.gather(*(self.nearest_landmark(s.start) for s in targets))
        for step, name in zip(targets, names):
            step.landmark = name

    async def reverse_geocode(self, at: LatLng) -> str | None:
        if not self._key:
            raise MapsError("not_configured")
        try:
            resp = await self._http.get(
                GEOCODE_URL, params={"latlng": f"{at[0]},{at[1]}", "key": self._key}
            )
            results = resp.json().get("results") or []
        except (httpx.HTTPError, ValueError) as e:
            raise MapsError("network", str(e)) from e
        return results[0].get("formatted_address") if results else None


def _place(p: dict[str, Any]) -> Place:
    loc = p.get("location") or {}
    ll = (float(loc["latitude"]), float(loc["longitude"])) if "latitude" in loc else None
    return Place(
        name=((p.get("displayName") or {}).get("text") or "").strip() or "Unknown place",
        address=(p.get("formattedAddress") or "").strip(),
        location=ll,
    )
