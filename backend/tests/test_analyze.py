import pytest

from rambu.analyze import AnalysisError, ScamAnalyzer, safety_net, validate

DEMO = (
    "Good afternoon, ma'am. This is Kevin from the fraud team at your bank. "
    "Then we need to block it right now. I'm sending a six-digit code to your phone. "
    "Read it to me now, before the money leaves. Please don't hang up."
)


def test_validate_keeps_verbatim_quotes_and_derives_signals():
    raw = {
        "risk_level": "high_risk",
        "signals": ["secret_code", "transfer"],  # transfer has no evidence: must be dropped
        "evidence": [
            {"quote": "Read it to me now, before the money leaves.", "signals": ["secret_code", "urgency"]},
            {"quote": "This is Kevin from the fraud team at your bank.", "signals": ["impersonation"]},
        ],
        "explanation": "",
        "recommended_action": "",
    }
    result = validate(raw, DEMO)
    assert result.level == "high_risk"
    assert result.signals == ["impersonation", "urgency", "secret_code"]
    assert [e["quote"] for e in result.evidence][0] == "Read it to me now, before the money leaves."


def test_validate_drops_invented_quotes_and_recovers_case_and_spacing():
    raw = {
        "risk_level": "high_risk",
        "signals": ["secret_code"],
        "evidence": [
            {"quote": "Tell me your PIN immediately.", "signals": ["secret_code"]},
            {"quote": "read it to me  now", "signals": ["secret_code"]},
        ],
        "explanation": "",
        "recommended_action": "",
    }
    result = validate(raw, DEMO)
    assert result.evidence == [{"quote": "Read it to me now", "signals": ["secret_code"]}]


def test_validate_without_surviving_evidence_is_low():
    raw = {"risk_level": "needs_review", "signals": ["urgency"],
           "evidence": [{"quote": "not in the call", "signals": ["urgency"]}],
           "explanation": "", "recommended_action": ""}
    result = validate(raw, DEMO)
    assert (result.level, result.signals, result.evidence) == ("low", [], [])


def test_validate_rejects_unknown_level():
    with pytest.raises(AnalysisError):
        validate({"risk_level": "maybe"}, DEMO)


def test_overlapping_evidence_is_folded_into_the_longer_quote():
    from rambu.pipeline import merge_evidence

    merged = merge_evidence(
        [{"quote": "Read it to me now.", "signals": ["secret_code"]}],
        [{"quote": "I'm sending a code. Read it to me now.", "signals": ["urgency"]},
         {"quote": "Please don't hang up.", "signals": ["urgency"]}],
    )
    assert merged == [
        {"quote": "I'm sending a code. Read it to me now.", "signals": ["secret_code", "urgency"]},
        {"quote": "Please don't hang up.", "signals": ["urgency"]},
    ]


def test_safety_net_catches_the_demo_line_and_skips_protective_talk():
    hits = safety_net(DEMO)
    assert [h["quote"] for h in hits] == ["Read it to me now, before the money leaves."]
    assert safety_net("Never share your OTP code with anyone, Mum.") == []
    assert safety_net("Saya kirim kode OTP. Tolong sebutkan kodenya sekarang ya, Bu.") != []
    assert safety_net("Jangan kasih kode OTP ke siapa pun.") == []
    # Whisper often runs everything into one sentence; a later "jangan" must not hide the request.
    assert safety_net("Saya kirim kode OTP ke HP Ibu, tolong sebutkan kodenya sekarang ya, Bu, jangan tutup teleponnya.") != []


class _Stub(ScamAnalyzer):
    def __init__(self, replies):
        super().__init__(api_key="test", model="test")
        self.replies = list(replies)

    def _ask_model(self, transcript, mode, language):
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


LOW = {"risk_level": "low", "signals": [], "evidence": [], "explanation": "", "recommended_action": ""}


def test_safety_net_lifts_a_low_model_reply():
    result = _Stub([LOW]).analyze(DEMO, "live", "en")
    assert result.level == "needs_review"
    assert result.signals == ["secret_code"]
    assert result.source == "safety_net"


def test_model_failure_retries_then_falls_back_to_safety_net():
    result = _Stub([AnalysisError("x"), AnalysisError("y")]).analyze(DEMO, "live", "en")
    assert result.level == "needs_review"


def test_model_failure_without_safety_net_hit_raises():
    with pytest.raises(AnalysisError):
        _Stub([AnalysisError("x"), AnalysisError("y")]).analyze("Hello, how are you?", "live", "en")
