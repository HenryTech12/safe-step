"""Turn-by-turn phrasing, landmark first, in five languages.

The tracker produces language-neutral Announcements; this module renders them. Turn words
come from the Routes API maneuver enum, so they don't depend on Google supporting the
language. Street names stay as Google gives them.

Yoruba, Hausa and Igbo templates NEED NATIVE-SPEAKER REVIEW.
"""

from __future__ import annotations

from dataclasses import dataclass

# maneuver enum -> action key
_ACTION = {
    "TURN_LEFT": "left",
    "TURN_SHARP_LEFT": "left",
    "ROUNDABOUT_LEFT": "left",
    "RAMP_LEFT": "slight_left",
    "TURN_SLIGHT_LEFT": "slight_left",
    "FORK_LEFT": "slight_left",
    "TURN_RIGHT": "right",
    "TURN_SHARP_RIGHT": "right",
    "ROUNDABOUT_RIGHT": "right",
    "RAMP_RIGHT": "slight_right",
    "TURN_SLIGHT_RIGHT": "slight_right",
    "FORK_RIGHT": "slight_right",
    "UTURN_LEFT": "uturn",
    "UTURN_RIGHT": "uturn",
}


def action_for(maneuver: str) -> str:
    return _ACTION.get(maneuver, "straight")


@dataclass(frozen=True)
class Announcement:
    kind: str  # start | prepare | now | arrive | off_route | rerouted | reroute_failed
    maneuver: str = "STRAIGHT"
    distance_m: float = 0.0
    landmark: str | None = None
    street: str | None = None
    relative: str | None = None  # start only: ahead | left | right | behind
    destination: str | None = None
    next: Announcement | None = None  # rerouted: the first instruction of the new route
    urgent: bool = False  # "now" turns may interrupt the agent


_T: dict[str, dict[str, str]] = {
    "en": {
        "left": "turn left", "right": "turn right", "slight_left": "bear left",
        "slight_right": "bear right", "straight": "continue straight", "uturn": "turn around",
        "at": "at {lm}, ", "onto": " onto {street}",
        "prepare": "In {dist} metres, {at}{action}{onto}.",
        "now": "{at}{action} now{onto}.",
        "start": "Your route starts {rel}. {first}",
        "rel_ahead": "ahead of you", "rel_left": "to your left", "rel_right": "to your right",
        "rel_behind": "behind you, so turn around",
        "arrive": "You have arrived at {dest}.", "arrive_plain": "You have arrived.",
        "off_route": "You have left the route. I am finding a new way.",
        "rerouted": "New route. {next}",
        "reroute_failed": "I could not find a new route. Please wait and ask me again.",
    },
    "pcm": {
        "left": "turn your left", "right": "turn your right", "slight_left": "bend small to your left",
        "slight_right": "bend small to your right", "straight": "dey go straight", "uturn": "turn back",
        "at": "for {lm} side, ", "onto": " enter {street}",
        "prepare": "After {dist} metres, {at}{action}{onto}.",
        "now": "{at}{action} now now{onto}.",
        "start": "The road dey {rel}. {first}",
        "rel_ahead": "your front", "rel_left": "your left", "rel_right": "your right",
        "rel_behind": "your back, so turn back",
        "arrive": "You don reach {dest}.", "arrive_plain": "You don reach.",
        "off_route": "You don comot from the road. I dey find another way.",
        "rerouted": "I don see new road. {next}",
        "reroute_failed": "I no fit find new road. Abeg wait small, then ask me again.",
    },
    "yo": {
        "left": "yà sí òsì", "right": "yà sí ọ̀tún", "slight_left": "yà díẹ̀ sí òsì",
        "slight_right": "yà díẹ̀ sí ọ̀tún", "straight": "máa lọ tààrà", "uturn": "padà sẹ́yìn",
        "at": "ní {lm}, ", "onto": " sí {street}",
        "prepare": "Lẹ́yìn mítà {dist}, {at}{action}{onto}.",
        "now": "{at}{action} báyìí{onto}.",
        "start": "Ọ̀nà wà {rel}. {first}",
        "rel_ahead": "níwájú yín", "rel_left": "ní òsì yín", "rel_right": "ní ọ̀tún yín",
        "rel_behind": "lẹ́yìn yín, ẹ yípadà",
        "arrive": "Ẹ ti dé {dest}.", "arrive_plain": "Ẹ ti dé.",
        "off_route": "Ẹ ti kúrò lójú ọ̀nà. Mo ń wá ọ̀nà mìíràn.",
        "rerouted": "Ọ̀nà tuntun. {next}",
        "reroute_failed": "Mi ò rí ọ̀nà tuntun. Ẹ dúró díẹ̀, kí ẹ tún béèrè.",
    },
    "ha": {
        "left": "juya hagu", "right": "juya dama", "slight_left": "karkata kaɗan zuwa hagu",
        "slight_right": "karkata kaɗan zuwa dama", "straight": "ci gaba kai tsaye", "uturn": "juya baya",
        "at": "a {lm}, ", "onto": " zuwa {street}",
        "prepare": "Bayan mita {dist}, {at}{action}{onto}.",
        "now": "{at}{action} yanzu{onto}.",
        "start": "Hanyar tana {rel}. {first}",
        "rel_ahead": "a gabanka", "rel_left": "a hagunka", "rel_right": "a damanka",
        "rel_behind": "a bayanka, ka juya",
        "arrive": "Ka isa {dest}.", "arrive_plain": "Ka isa.",
        "off_route": "Ka bar hanya. Ina neman wata hanya.",
        "rerouted": "Sabuwar hanya. {next}",
        "reroute_failed": "Ban sami sabuwar hanya ba. Ka jira kaɗan, sannan ka sake tambaya.",
    },
    "ig": {
        "left": "tụgharịa n'aka ekpe", "right": "tụgharịa n'aka nri",
        "slight_left": "gbagọọ ntakịrị n'aka ekpe", "slight_right": "gbagọọ ntakịrị n'aka nri",
        "straight": "gaa n'ihu", "uturn": "tụgharịa azụ",
        "at": "na {lm}, ", "onto": " banye {street}",
        "prepare": "Mgbe mita {dist} gachara, {at}{action}{onto}.",
        "now": "{at}{action} ugbu a{onto}.",
        "start": "Ụzọ dị {rel}. {first}",
        "rel_ahead": "n'ihu gị", "rel_left": "n'aka ekpe gị", "rel_right": "n'aka nri gị",
        "rel_behind": "n'azụ gị, tụgharịa",
        "arrive": "I rutela {dest}.", "arrive_plain": "I rutela.",
        "off_route": "Ị hapụla ụzọ. Ana m achọ ụzọ ọzọ.",
        "rerouted": "Ụzọ ọhụrụ. {next}",
        "reroute_failed": "Ahụghị m ụzọ ọhụrụ. Biko chere ntakịrị, jụọ m ọzọ.",
    },
}


def _round_distance(m: float) -> int:
    if m < 20:
        return max(5, int(round(m / 5.0)) * 5)
    return int(round(m / 10.0)) * 10


def _cap(s: str) -> str:
    return s[:1].upper() + s[1:] if s else s


def render(a: Announcement, lang: str) -> str:
    t = _T.get(lang, _T["en"])
    action = t[action_for(a.maneuver)]
    at = t["at"].format(lm=a.landmark) if a.landmark else ""
    onto = t["onto"].format(street=a.street) if a.street and action_for(a.maneuver) != "uturn" else ""

    if a.kind == "prepare":
        return _cap(t["prepare"].format(dist=_round_distance(a.distance_m), at=at, action=action, onto=onto))
    if a.kind == "now":
        return _cap(t["now"].format(at=at, action=action, onto=onto))
    if a.kind == "start":
        rel = t.get(f"rel_{a.relative or 'ahead'}", t["rel_ahead"])
        first = render(a.next, lang) if a.next else ""
        return _cap(t["start"].format(rel=rel, first=first)).strip()
    if a.kind == "arrive":
        return t["arrive"].format(dest=a.destination) if a.destination else t["arrive_plain"]
    if a.kind == "off_route":
        return t["off_route"]
    if a.kind == "rerouted":
        return t["rerouted"].format(next=render(a.next, lang) if a.next else "").strip()
    if a.kind == "reroute_failed":
        return t["reroute_failed"]
    return ""
