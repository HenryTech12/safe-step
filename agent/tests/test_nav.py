import pytest

from safestep_agent.nav.controller import NavigationController
from safestep_agent.nav.geo import bearing, decode_polyline, distance_to_polyline, haversine, relative_direction
from safestep_agent.nav.maps import MapsClient, MapsError, Place
from safestep_agent.nav.phrases import Announcement, render
from safestep_agent.nav.route import parse_route
from safestep_agent.nav.tracker import NavigationTracker

from navhelpers import at, l_route


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


# --- geo ---

def test_decode_polyline_reference_example():
    pts = decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    assert pts == [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]


def test_distances_and_directions():
    assert haversine(at(0, 0), at(100, 0)) == pytest.approx(100, abs=0.5)
    assert distance_to_polyline(at(50, 20), [at(0, 0), at(100, 0)]) == pytest.approx(20, abs=0.5)
    assert bearing(at(0, 0), at(0, 50)) == pytest.approx(90, abs=0.5)
    assert relative_direction(0, 90) == "right" and relative_direction(0, 270) == "left"
    assert relative_direction(90, 85) == "ahead" and relative_direction(0, 180) == "behind"


# --- parsing (shape per Routes API v2 JSON) ---

def test_parse_routes_response():
    data = {
        "routes": [{
            "distanceMeters": 180, "duration": "150s",
            "polyline": {"encodedPolyline": "_p~iF~ps|U_ulLnnqC"},
            "legs": [{
                "endLocation": {"latLng": {"latitude": 6.43, "longitude": 3.43}},
                "steps": [
                    {"distanceMeters": 100, "staticDuration": "80s",
                     "startLocation": {"latLng": {"latitude": 6.42, "longitude": 3.42}},
                     "endLocation": {"latLng": {"latitude": 6.421, "longitude": 3.42}},
                     "navigationInstruction": {"maneuver": "DEPART", "instructions": "Head north on Akin Adesola St"}},
                    {"distanceMeters": 80,
                     "startLocation": {"latLng": {"latitude": 6.421, "longitude": 3.42}},
                     "endLocation": {"latLng": {"latitude": 6.43, "longitude": 3.43}},
                     "navigationInstruction": {"maneuver": "TURN_LEFT", "instructions": "Turn left onto Adeola Odeku St"}},
                ],
            }],
        }]
    }
    r = parse_route(data, "Bar Beach")
    assert r and len(r.steps) == 2 and r.duration_s == 150 and r.destination == (6.43, 3.43)
    assert r.steps[1].maneuver == "TURN_LEFT" and r.steps[1].street == "Adeola Odeku St"
    assert parse_route({"routes": []}) is None


# --- phrasing ---

def test_landmark_first_english():
    a = Announcement(kind="prepare", maneuver="TURN_LEFT", distance_m=43, landmark="Shoprite", street="Admiralty Way")
    assert render(a, "en") == "In 40 metres, at Shoprite, turn left onto Admiralty Way."
    now = Announcement(kind="now", maneuver="TURN_RIGHT", landmark="Shoprite")
    assert render(now, "en") == "At Shoprite, turn right now."
    assert render(now, "pcm") == "For Shoprite side, turn your right now now."


@pytest.mark.parametrize("lang", ["en", "pcm", "yo", "ha", "ig"])
def test_every_kind_renders_in_every_language(lang):
    nxt = Announcement(kind="prepare", maneuver="TURN_SLIGHT_RIGHT", distance_m=100)
    for a in [
        nxt,
        Announcement(kind="now", maneuver="UTURN_LEFT", street="X Street"),
        Announcement(kind="start", relative="behind", next=nxt),
        Announcement(kind="arrive", destination="Church"),
        Announcement(kind="arrive"),
        Announcement(kind="off_route"),
        Announcement(kind="rerouted", next=nxt),
        Announcement(kind="reroute_failed"),
    ]:
        text = render(a, lang)
        assert text and "{" not in text and "north" not in text.lower()


# --- tracker ---

def walk(tracker, clock, points, step_s=3.0, accuracy=5.0):
    out = []
    for p in points:
        clock.t += step_s
        out += [a.kind for a in tracker.update(p, accuracy)]
    return out


def test_prepare_now_arrive_sequence():
    c = Clock()
    t = NavigationTracker(l_route(), clock=c)
    path = [at(n, 0) for n in range(0, 101, 5)] + [at(100, e) for e in range(5, 81, 5)]
    kinds = walk(t, c, path)
    assert kinds == ["prepare", "now", "arrive"]


def test_turn_prompt_carries_landmark_and_street():
    c = Clock()
    t = NavigationTracker(l_route(), clock=c)
    c.t = 100
    (a,) = t.update(at(60, 0), 5)
    assert a.kind == "prepare" and a.landmark == "Shoprite" and a.street == "Adeola Odeku Street"


def test_grace_period_suppresses_turn_prompts():
    c = Clock()
    t = NavigationTracker(l_route(), clock=c)
    c.t = 1.0
    assert t.update(at(60, 0), 5) == []


def test_off_route_needs_two_bad_fixes_and_fires_once():
    c = Clock()
    t = NavigationTracker(l_route(), clock=c)
    c.t = 100
    assert t.update(at(30, 60), 5) == []
    assert [a.kind for a in t.update(at(30, 62), 5)] == ["off_route"]
    assert t.update(at(30, 64), 5) == []
    assert t.off_route


def test_poor_accuracy_is_ignored():
    c = Clock()
    t = NavigationTracker(l_route(), clock=c)
    c.t = 100
    assert t.update(at(30, 60), 80) == [] and t.update(at(30, 60), 80) == []
    assert not t.off_route


def test_start_announcement_uses_heading():
    t = NavigationTracker(l_route(), clock=Clock())
    a = t.start_announcement(heading=180.0, here=at(0, 0))  # facing south, route goes north
    assert a.relative == "behind"
    assert render(a, "en").startswith("Your route starts behind you, so turn around. In 100 metres, at Shoprite, turn right")


# --- controller with fake maps ---

class FakeMaps(MapsClient):
    def __init__(self, fail_route=False):
        super().__init__(api_key="k")
        self.fail_route = fail_route
        self.route_calls = 0

    async def search_text(self, query, near, max_results=3):
        return [Place("Bar Beach", "Victoria Island, Lagos", at(100, 80))]

    async def walking_route(self, origin, destination, destination_name=""):
        self.route_calls += 1
        if self.fail_route:
            raise MapsError("no_route")
        r = l_route()
        r.destination_name = destination_name
        return r

    async def add_landmarks(self, route, max_steps=12):
        return None


async def test_controller_start_and_speaks_turns():
    said = []
    c = Clock()
    nav = NavigationController(FakeMaps(), "en", lambda t, u: said.append((t, u)), clock=c)
    assert (await nav.start("bar beach")).startswith("NO_GPS")
    nav.on_gps(*at(0, 0), heading=0.0, accuracy=5.0)
    res = await nav.start("bar beach")
    assert res.startswith("ROUTE_STARTED to Bar Beach") and "Your route starts ahead of you." in res
    c.t = 100
    nav.on_gps(*at(92, 0), heading=0.0, accuracy=5.0)
    assert said[-1] == ("At Shoprite, turn right now onto Adeola Odeku Street.", True)


async def test_controller_reroutes_when_off_route():
    import asyncio

    said = []
    c = Clock()
    maps = FakeMaps()
    nav = NavigationController(maps, "pcm", lambda t, u: said.append(t), clock=c)
    nav.on_gps(*at(0, 0), heading=0.0, accuracy=5.0)
    await nav.start("Bar Beach")
    c.t = 100
    nav.on_gps(*at(30, 60), None, 5.0)
    nav.on_gps(*at(30, 62), None, 5.0)
    await asyncio.sleep(0)  # let the reroute task run
    await asyncio.sleep(0)
    assert said[0] == "You don comot from the road. I dey find another way."
    assert maps.route_calls == 2
    assert said[-1].startswith("I don see new road.")


async def test_saved_place_resolves_without_search():
    nav = NavigationController(FakeMaps(), "en", lambda t, u: None)
    nav.saved_places["home"] = at(100, 80)
    nav.on_gps(*at(0, 0), None, 5.0)
    assert (await nav.start("take me home")).startswith("ROUTE_STARTED to home")


async def test_controller_error_messages_are_user_safe():
    nav = NavigationController(FakeMaps(fail_route=True), "en", lambda t, u: None)
    nav.on_gps(*at(0, 0), None, 5.0)
    assert (await nav.start("x")).startswith("NO_ROUTE")
