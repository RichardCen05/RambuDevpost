"""Scam analysis: OpenRouter model with a strict JSON schema, checked in code, plus a keyword safety net."""

import json
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

import httpx

SIGNALS = ["impersonation", "urgency", "secret_code", "transfer", "remote_app"]
LEVELS = ["low", "needs_review", "high_risk"]
LANGUAGE_NAMES = {"en": "English", "id": "Indonesian (Bahasa Indonesia)"}
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
PROMPT = (Path(__file__).parent / "prompt.md").read_text()

RISK_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["risk_level", "signals", "evidence", "explanation", "recommended_action"],
    "properties": {
        "risk_level": {"type": "string", "enum": LEVELS},
        "signals": {"type": "array", "items": {"type": "string", "enum": SIGNALS}},
        "evidence": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["quote", "signals"],
                "properties": {
                    "quote": {"type": "string"},
                    "signals": {"type": "array", "items": {"type": "string", "enum": SIGNALS}},
                },
            },
        },
        "explanation": {"type": "string"},
        "recommended_action": {"type": "string"},
    },
}


class AnalysisError(Exception):
    pass


@dataclass
class Analysis:
    level: str
    signals: list[str] = field(default_factory=list)
    evidence: list[dict] = field(default_factory=list)
    explanation: str = ""
    recommended_action: str = ""
    source: str = "model"

    def to_dict(self) -> dict:
        return asdict(self)


def level_rank(level: str) -> int:
    return LEVELS.index(level)


def find_quote(quote: str, transcript: str) -> str | None:
    """The quote as it actually appears in the transcript, or None if it isn't there."""
    quote = quote.strip()
    if not quote:
        return None
    if quote in transcript:
        return quote
    words = re.findall(r"[\w•']+", quote)
    if not words:
        return None
    pattern = r"\W+".join(re.escape(w) for w in words)
    match = re.search(pattern, transcript, re.IGNORECASE)
    return match.group(0) if match else None


def validate(raw: dict, transcript: str) -> Analysis:
    level = raw.get("risk_level")
    if level not in LEVELS:
        raise AnalysisError(f"invalid risk_level: {level!r}")
    evidence: list[dict] = []
    for item in raw.get("evidence") or []:
        quote = find_quote(str(item.get("quote", "")), transcript)
        signals = [s for s in SIGNALS if s in (item.get("signals") or [])]
        if quote and signals and all(e["quote"] != quote for e in evidence):
            evidence.append({"quote": quote, "signals": signals})
    signals = [s for s in SIGNALS if any(s in e["signals"] for e in evidence)]
    if level == "low" or not evidence:
        level, signals, evidence = "low", [], []
    return Analysis(
        level=level,
        signals=signals,
        evidence=evidence,
        explanation=str(raw.get("explanation", "")),
        recommended_action=str(raw.get("recommended_action", "")),
    )


# Safety net --------------------------------------------------------------

_NEGATION = re.compile(r"\b(never|don't|do not|dont|jangan|tidak|bukan|nggak|gak|enggak)\b", re.IGNORECASE)
_CODE_WORD = re.compile(r"\b(code|otp|pin|password|passcode|kode\w*|sandi\w*)\b", re.IGNORECASE)
_CODE_REQUESTS = [
    re.compile(r"\b(read|tell|give|say|share|type|forward|provide|confirm)\b(?:\W+\w+){0,6}?\W+(code|otp|pin|password|passcode)\b", re.IGNORECASE),
    re.compile(r"\bread (it|them|that) (out )?to me\b", re.IGNORECASE),
    re.compile(r"\b(bacakan|sebutkan|kasih tahu|kasih|berikan|beri tahu|beritahu|infokan|kirimkan)\b(?:\W+\w+){0,6}?\W+(kode\w*|otp|pin|sandi\w*|password)\b", re.IGNORECASE),
    re.compile(r"\b(kode\w*|otp|pin)\b(?:\W+\w+){0,6}?\W+(bacakan|sebutkan|kasih tahu|berikan|beri tahu)\b", re.IGNORECASE),
]


def _sentences(transcript: str) -> list[str]:
    return [s for s in re.split(r"(?<=[.!?])\s+", transcript.strip()) if s]


def safety_net(transcript: str) -> list[dict]:
    """Caller sentences that plainly ask for a code. Used only to keep the key case from slipping through."""
    if not _CODE_WORD.search(transcript):
        return []
    hits = []
    for sentence in _sentences(transcript):
        for pattern in _CODE_REQUESTS:
            match = pattern.search(sentence)
            # "Never tell anyone the code" is protection; only a negation right before the request counts.
            if match and not _NEGATION.search(sentence[max(0, match.start() - 25):match.start()]):
                hits.append({"quote": sentence, "signals": ["secret_code"]})
                break
    return hits


# Analyzer ----------------------------------------------------------------

class ScamAnalyzer:
    def __init__(self, api_key: str, model: str, timeout: float = 20.0):
        self.api_key = api_key
        self.model = model
        self._client = httpx.Client(timeout=timeout)

    def _ask_model(self, transcript: str, mode: str, language: str) -> dict:
        if not self.api_key:
            raise AnalysisError("OPENROUTER_API_KEY is not set")
        system = PROMPT.replace("{language}", language).replace(
            "{language_name}", LANGUAGE_NAMES.get(language, "English")
        )
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": json.dumps(
                    {"transcript": transcript, "mode": mode, "language": language}, ensure_ascii=False)},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "rambu_risk", "strict": True, "schema": RISK_SCHEMA},
            },
            "reasoning": {"effort": "low"},
            "temperature": 0,
        }
        try:
            response = self._client.post(
                OPENROUTER_URL,
                headers={"Authorization": f"Bearer {self.api_key}", "X-Title": "Rambu"},
                json=payload,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            return json.loads(content)
        except (httpx.HTTPError, KeyError, IndexError, TypeError, json.JSONDecodeError) as exc:
            raise AnalysisError(f"model call failed: {exc}") from exc

    def analyze(self, transcript: str, mode: str, language: str) -> Analysis:
        result: Analysis | None = None
        error: AnalysisError | None = None
        for _ in range(2):
            try:
                result = validate(self._ask_model(transcript, mode, language), transcript)
                break
            except AnalysisError as exc:
                error = exc
        hits = safety_net(transcript)
        if result is None:
            if hits:
                return Analysis(level="needs_review", signals=["secret_code"], evidence=hits, source="safety_net")
            raise error or AnalysisError("analysis failed")
        if result.level == "low" and hits:
            result = Analysis(
                level="needs_review",
                signals=["secret_code"],
                evidence=hits,
                explanation=result.explanation,
                recommended_action=result.recommended_action,
                source="safety_net",
            )
        return result
