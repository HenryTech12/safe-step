from safestep_agent.languages import LANGUAGES, get_language
from safestep_agent.prompts import build_instructions
from safestep_agent.protocol import DispatchMetadata, decode, encode
from safestep_agent.session_state import SessionState


def test_metadata_parse_defaults_and_validation():
    assert DispatchMetadata.parse(None) == DispatchMetadata("en", "hazard_detection")
    assert DispatchMetadata.parse("not json") == DispatchMetadata("en", "hazard_detection")
    assert DispatchMetadata.parse('{"language":"HA","mode":"navigation"}') == DispatchMetadata("ha", "navigation")
    assert DispatchMetadata.parse('{"language":"fr","mode":"x"}') == DispatchMetadata("en", "hazard_detection")


def test_metadata_roundtrip():
    m = DispatchMetadata("ig", "navigation")
    assert DispatchMetadata.parse(m.to_json()) == m


def test_encode_decode():
    assert decode(encode({"a": 1})) == {"a": 1}
    assert decode(b"\xff") is None and decode(b"[1]") is None


def test_all_five_languages():
    assert set(LANGUAGES) == {"en", "pcm", "yo", "ha", "ig"}
    assert get_language("zz").code == "en"


def test_prompt_rules():
    for lang in LANGUAGES.values():
        p = build_instructions(lang, "navigation")
        assert lang.name in p
        assert "Zapier" not in p
        assert "left or right first" in p
        assert "current mode: navigation" in p


def test_session_state_modes():
    s = SessionState.create("pcm", "bogus")
    assert s.mode == "hazard_detection" and s.hazard_detection_on
    assert s.set_mode("navigation") and s.hazard_detection_on
    assert not s.set_mode("navigation")
