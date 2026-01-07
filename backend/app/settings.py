from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import List, Optional

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

# Import configuration defaults
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from config import OPENAI_MODEL, OPENAI_LOCATION_MODEL, CORS_ALLOW_ORIGINS


def _candidate_env_files() -> List[Path]:
    """
    Priority:
    1) backend/.env
    2) repo-root/.env (one level up)
    """
    here = Path(__file__).resolve()
    backend_dir = here.parents[2]  # backend/
    return [
        backend_dir / ".env",
        backend_dir.parent / ".env",
    ]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=[str(p) for p in _candidate_env_files()],
        env_file_encoding="utf-8",
        extra="ignore",
    )

    openai_api_key: Optional[SecretStr] = None
    openai_model: str = OPENAI_MODEL
    openai_location_model: str = OPENAI_LOCATION_MODEL

    cors_allow_origins: List[str] = CORS_ALLOW_ORIGINS


@lru_cache
def get_settings() -> Settings:
    return Settings()

