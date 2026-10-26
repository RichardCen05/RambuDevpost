"""Settings read from the environment (backend/.env via uvicorn --env-file)."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    database_path: Path
    openrouter_api_key: str
    openrouter_model: str
    whisper_model: str
    apns_team_id: str
    apns_key_id: str
    apns_key_path: str
    apns_bundle_id: str
    dev_puck_token: str

    @property
    def apns_configured(self) -> bool:
        return bool(self.apns_team_id and self.apns_key_id and self.apns_key_path)


def load_settings() -> Settings:
    env = os.environ.get
    return Settings(
        database_path=Path(env("DATABASE_PATH", "data/rambu.sqlite3")),
        openrouter_api_key=env("OPENROUTER_API_KEY", ""),
        openrouter_model=env("OPENROUTER_MODEL", "openai/gpt-6-luna"),
        whisper_model=env("WHISPER_MODEL", "small"),
        apns_team_id=env("APNS_TEAM_ID", ""),
        apns_key_id=env("APNS_KEY_ID", ""),
        apns_key_path=env("APNS_KEY_PATH", ""),
        apns_bundle_id=env("APNS_BUNDLE_ID", "id.rambu.app"),
        dev_puck_token=env("DEV_PUCK_TOKEN", ""),
    )
