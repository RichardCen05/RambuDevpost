"""Push copy in English and Indonesian. Each recipient gets their own language."""

SIGNAL_PRIORITY = ["secret_code", "transfer", "remote_app", "impersonation", "urgency"]

HEADLINES = {
    "impersonation": ("The caller claims to be an institution", "Penelepon mengaku dari lembaga"),
    "urgency": ("The caller is pressuring you", "Penelepon mendesak Anda"),
    "secret_code": ("The caller is asking for a secret code", "Penelepon meminta kode rahasia"),
    "transfer": ("The caller is asking for a transfer", "Penelepon meminta transfer"),
    "remote_app": ("The caller wants you to install an app", "Penelepon menyuruh pasang aplikasi"),
}

LEVEL_TITLES = {
    "needs_review": ("Worth a look", "Perlu dicek"),
    "high_risk": ("Danger", "Bahaya"),
    "low": ("Safe", "Aman"),
}


def t(lang: str, english: str, indonesian: str) -> str:
    return indonesian if lang == "id" else english


def top_signal(signals: list[str]) -> str | None:
    return next((s for s in SIGNAL_PRIORITY if s in signals), None)


def headline(lang: str, signals: list[str]) -> str:
    signal = top_signal(signals)
    if not signal:
        return t(lang, "Rambu is listening", "Rambu mendengarkan")
    return t(lang, *HEADLINES[signal])


def level_title(lang: str, level: str) -> str:
    return t(lang, *LEVEL_TITLES.get(level, LEVEL_TITLES["needs_review"]))


def strongest_quote(evidence: list[dict]) -> str:
    for signal in SIGNAL_PRIORITY:
        for item in evidence:
            if signal in item["signals"]:
                return item["quote"]
    return evidence[0]["quote"] if evidence else ""


def names(people: list[str], lang: str) -> str:
    if len(people) <= 1:
        return "".join(people)
    return ", ".join(people[:-1]) + t(lang, " and ", " dan ") + people[-1]


def parent_warning(lang: str, level: str, signals: list[str], caregivers: list[str]) -> tuple[str, str]:
    title = (t(lang, "Danger: possible scam", "Bahaya: kemungkinan penipuan") if level == "high_risk"
             else t(lang, "Be careful with this call", "Hati-hati dengan telepon ini"))
    body = headline(lang, signals) + "."
    if caregivers:
        body += t(lang, f" Sent to {names(caregivers, lang)}.", f" Dikirim ke {names(caregivers, 'id')}.")
    return title, body


def caregiver_warning(lang: str, parent: str, evidence: list[dict]) -> tuple[str, str]:
    title = t(lang, f"{parent} may be getting scammed", f"{parent} mungkin sedang ditipu")
    quote = strongest_quote(evidence)
    body = f"“{quote}”" if quote else t(lang, "Open Rambu to check the call.", "Buka Rambu untuk memeriksa panggilan.")
    return title, body


def verdict_for_parent(lang: str, verdict: str, by: str) -> tuple[str, str, str]:
    """(push title, push body, short Live Activity title)."""
    if verdict == "scam":
        return (
            t(lang, f"{by} says this is a scam", f"{by}: ini penipuan"),
            t(lang, "Hang up and call the number on the back of your card.",
              "Tutup telepon dan hubungi nomor di balik kartu Anda."),
            t(lang, "Scam", "Penipuan"),
        )
    return (
        t(lang, f"{by} checked: this looks safe", f"{by} sudah cek: ini terlihat aman"),
        t(lang, "You can continue the call.", "Anda bisa melanjutkan telepon."),
        t(lang, "Safe", "Aman"),
    )


def decided_by_other(lang: str, verdict: str, by: str) -> tuple[str, str]:
    word = t(lang, "a scam", "penipuan") if verdict == "scam" else t(lang, "safe", "aman")
    return (t(lang, f"{by} already answered", f"{by} sudah menjawab"),
            t(lang, f"{by} marked the call as {word}.", f"{by} menandai panggilan sebagai {word}."))
