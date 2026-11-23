"""Synthetic Lagos route for tests: walk 100 m north, turn right (east) 80 m, arrive."""

from safestep_agent.nav.route import Route, Step

BASE = (6.4300, 3.4200)
M_LAT = 1 / 111_320  # degrees per metre (north)
M_LNG = 1 / (111_320 * 0.99371)  # cos(6.43°)


def at(north_m: float, east_m: float) -> tuple[float, float]:
    return BASE[0] + north_m * M_LAT, BASE[1] + east_m * M_LNG


def l_route() -> Route:
    a, b, c = at(0, 0), at(100, 0), at(100, 80)
    s0 = Step("DEPART", "Head north on Akin Adesola Street", 100, a, b, [a, at(50, 0), b])
    s1 = Step("TURN_RIGHT", "Turn right onto Adeola Odeku Street", 80, b, c, [b, at(100, 40), c], landmark="Shoprite")
    return Route(steps=[s0, s1], distance_m=180, duration_s=150, points=[a, at(50, 0), b, at(100, 40), c], destination=c, destination_name="Bar Beach")
