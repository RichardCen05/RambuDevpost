"""Masks codes, PINs, and account numbers before any text is stored or sent to the model."""

import re

MASK = "•••"

_NUMBER_WORDS = (
    "zero|one|two|three|four|five|six|seven|eight|nine|"
    "nol|kosong|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan"
)
# Three or more spelled-out digits in a row: "four eight two nine", "satu dua tiga".
_SPELLED_RUN = re.compile(
    rf"\b(?:{_NUMBER_WORDS})(?:[\s,.\-]+(?:{_NUMBER_WORDS})){{2,}}\b", re.IGNORECASE
)
# Three or more digits, optionally separated by single spaces, dashes or dots: "482913", "482 913".
_DIGIT_RUN = re.compile(r"\d(?:[ \-.]?\d){2,}")
# Money written with thousands separators stays readable: "8,000,000", "Rp 8.000.000".
_MONEY = re.compile(r"(?:Rp\.?\s?\d{1,3}(?:[.,]\d{3})+|\b\d{1,3}(?:,\d{3})+\b)", re.IGNORECASE)


def mask_sensitive(text: str) -> str:
    protected: list[str] = []

    def keep(match: re.Match) -> str:
        protected.append(match.group(0))
        return f"\x00{len(protected) - 1}\x00"

    text = _MONEY.sub(keep, text)
    text = _SPELLED_RUN.sub(MASK, text)
    text = _DIGIT_RUN.sub(MASK, text)
    return re.sub(r"\x00(\d+)\x00", lambda m: protected[int(m.group(1))], text)
