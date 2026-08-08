"""Environment-backed configuration for the disease inference API."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    """Validated runtime settings with repository-relative defaults."""

    model_path: Path
    feature_columns_path: Path
    confidence_threshold: float
    google_application_credentials: str | None
    firestore_timeout_seconds: float
    model_version: str
    log_level: str
    require_firebase_auth: bool
    require_app_check: bool
    check_revoked_tokens: bool
    ai_rate_limit_requests: int
    ai_rate_limit_window_seconds: int


def _resolve_path(value: str | None, default: Path) -> Path:
    path = Path(value).expanduser() if value else default
    return path.resolve()


def _bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    normalized = value.strip().casefold()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be true or false")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load settings once; environment variables override safe defaults."""
    try:
        from dotenv import load_dotenv

        load_dotenv()
    except ImportError:
        pass
    backend_dir = Path(__file__).resolve().parents[1]
    threshold = float(os.getenv("CONFIDENCE_THRESHOLD", "0.50"))
    if not 0.0 <= threshold <= 1.0:
        raise ValueError("CONFIDENCE_THRESHOLD must be between 0 and 1")
    firestore_timeout = float(os.getenv("FIRESTORE_TIMEOUT_SECONDS", "5"))
    if not 0.1 <= firestore_timeout <= 30.0:
        raise ValueError("FIRESTORE_TIMEOUT_SECONDS must be between 0.1 and 30")
    rate_limit_requests = int(os.getenv("AI_RATE_LIMIT_REQUESTS", "30"))
    rate_limit_window = int(os.getenv("AI_RATE_LIMIT_WINDOW_SECONDS", "60"))
    if rate_limit_requests < 1:
        raise ValueError("AI_RATE_LIMIT_REQUESTS must be at least 1")
    if rate_limit_window < 1:
        raise ValueError("AI_RATE_LIMIT_WINDOW_SECONDS must be at least 1")
    return Settings(
        model_path=_resolve_path(
            os.getenv("MODEL_PATH"), backend_dir / "models" / "disease_model.pkl"
        ),
        feature_columns_path=_resolve_path(
            os.getenv("FEATURE_COLUMNS_PATH"),
            backend_dir / "models" / "feature_columns.json",
        ),
        confidence_threshold=threshold,
        google_application_credentials=os.getenv("GOOGLE_APPLICATION_CREDENTIALS"),
        firestore_timeout_seconds=firestore_timeout,
        model_version=os.getenv("MODEL_VERSION", "1.0.0"),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
        require_firebase_auth=_bool_env("AI_REQUIRE_FIREBASE_AUTH", True),
        require_app_check=_bool_env("AI_REQUIRE_APP_CHECK", True),
        check_revoked_tokens=_bool_env("AI_CHECK_REVOKED_TOKENS", True),
        ai_rate_limit_requests=rate_limit_requests,
        ai_rate_limit_window_seconds=rate_limit_window,
    )
