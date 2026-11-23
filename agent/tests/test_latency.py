from types import SimpleNamespace as NS

from safestep_agent.latency import LatencyTracker


def make(sink=None):
    return LatencyTracker(session_id="r", language="pcm", mode="hazard_detection", vad_silence_s=0.5, sink=sink)


def test_measures_end_of_speech_to_first_audio():
    out = []
    t = make(out.append)
    t.on_user_state("speaking", "listening", 100.0)
    t.on_metrics(NS(type="eou_metrics", end_of_utterance_delay=0.42))
    t.on_metrics(NS(type="llm_metrics", ttft=0.31))
    t.on_metrics(NS(type="tts_metrics", ttfb=0.25, label="YarnGPT"))
    t.on_agent_state("thinking", 100.2)
    t.on_agent_state("speaking", 101.2)
    assert len(out) == 1
    rec = out[0]
    assert rec["vad_end_to_audio_ms"] == 1200.0
    assert rec["speech_end_to_audio_ms"] == 1700.0  # + VAD silence window
    assert rec["eou_delay_ms"] == 420.0 and rec["llm_ttft_ms"] == 310.0
    assert rec["tts_ttfb_ms"] == 250.0 and rec["tts_label"] == "YarnGPT"
    assert rec["language"] == "pcm" and rec["turn"] == 1


def test_greeting_without_user_turn_is_not_logged():
    out = []
    t = make(out.append)
    t.on_agent_state("speaking", 5.0)
    assert out == []


def test_user_interrupts_before_answer_drops_turn():
    out = []
    t = make(out.append)
    t.on_user_state("speaking", "listening", 1.0)
    t.on_user_state("listening", "speaking", 1.5)
    t.on_user_state("speaking", "listening", 3.0)
    t.on_agent_state("speaking", 3.8)
    assert len(out) == 1 and out[0]["turn"] == 2
    assert out[0]["vad_end_to_audio_ms"] == 800.0


def test_only_first_llm_and_tts_metrics_count():
    out = []
    t = make(out.append)
    t.on_user_state("speaking", "listening", 0.0)
    t.on_metrics(NS(type="tts_metrics", ttfb=0.2, label="a"))
    t.on_metrics(NS(type="tts_metrics", ttfb=0.9, label="b"))
    t.on_agent_state("speaking", 1.0)
    assert out[0]["tts_ttfb_ms"] == 200.0 and out[0]["tts_label"] == "a"
