"""Environment-backed configuration for the disease inference API."""

from __future__ import annotations

import os
import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    """Validated runtime settings with repository-relative defaults."""

    model_path: Path
    model_expected_sha256: str
    feature_columns_path: Path
    confidence_threshold: float
    google_application_credentials: str | None
    firestore_timeout_seconds: float
    model_version: str
    log_level: str
    environment: str
    web_allowed_origins: tuple[str, ...]
    api_allowed_hosts: tuple[str, ...]
    allow_local_cors: bool
    require_firebase_auth: bool
    require_app_check: bool
    check_revoked_tokens: bool
    ai_rate_limit_requests: int
    ai_rate_limit_window_seconds: int
    api_rate_limit_requests: int
    api_rate_limit_window_seconds: int
    ocr_rate_limit_requests: int
    ocr_rate_limit_window_seconds: int


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


def _list_env(name: str, default: tuple[str, ...] = ()) -> tuple[str, ...]:
    """Read a comma-separated setting while preserving stable ordering."""
    raw = os.getenv(name)
    values = raw.split(",") if raw is not None else list(default)
    return tuple(dict.fromkeys(value.strip().rstrip("/") for value in values if value.strip()))


def _expected_model_sha256(backend_dir: Path) -> str:
    configured = os.getenv("MODEL_EXPECTED_SHA256", "").strip().lower()
    if configured:
        return configured
    metrics_path = backend_dir / "models" / "training_metrics.json"
    try:
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        expected = str(metrics.get("model_sha256", "")).strip().lower()
    except (OSError, json.JSONDecodeError):
        expected = ""
    if not expected:
        raise ValueError(
            "MODEL_EXPECTED_SHA256 is required when training_metrics.json "
            "does not declare model_sha256"
        )
    return expected


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load settings once; environment variables override safe defaults."""
    try:
        from dotenv import load_dotenv

        load_dotenv()
    except ImportError:
        pass
    backend_dir = Path(__file__).resolve().parents[1]
    environment = os.getenv("APP_ENV", "development").strip().casefold()
    if environment not in {"development", "test", "staging", "production"}:
        raise ValueError("APP_ENV must be development, test, staging, or production")
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
    api_rate_limit_requests = int(os.getenv("API_RATE_LIMIT_REQUESTS", "120"))
    api_rate_limit_window = int(os.getenv("API_RATE_LIMIT_WINDOW_SECONDS", "60"))
    if api_rate_limit_requests < 1:
        raise ValueError("API_RATE_LIMIT_REQUESTS must be at least 1")
    if api_rate_limit_window < 1:
        raise ValueError("API_RATE_LIMIT_WINDOW_SECONDS must be at least 1")
    ocr_rate_limit_requests = int(os.getenv("AI_OCR_RATE_LIMIT_REQUESTS", "10"))
    ocr_rate_limit_window = int(os.getenv("AI_OCR_RATE_LIMIT_WINDOW_SECONDS", "60"))
    if ocr_rate_limit_requests < 1:
        raise ValueError("AI_OCR_RATE_LIMIT_REQUESTS must be at least 1")
    if ocr_rate_limit_window < 1:
        raise ValueError("AI_OCR_RATE_LIMIT_WINDOW_SECONDS must be at least 1")

    web_allowed_origins = _list_env(
        "WEB_ALLOWED_ORIGINS",
        ()
        if environment == "production"
        else (
            "https://capstone-c98f9.web.app",
            "https://capstone-c98f9.firebaseapp.com",
        ),
    )
    api_allowed_hosts = _list_env(
        "API_ALLOWED_HOSTS",
        () if environment == "production" else ("localhost", "127.0.0.1", "testserver"),
    )
    allow_local_cors = _bool_env("AI_ALLOW_LOCAL_CORS", environment != "production")
    require_firebase_auth = _bool_env("AI_REQUIRE_FIREBASE_AUTH", True)
    require_app_check = _bool_env("AI_REQUIRE_APP_CHECK", True)
    check_revoked_tokens = _bool_env("AI_CHECK_REVOKED_TOKENS", True)
    if environment == "production":
        if not (require_firebase_auth and require_app_check and check_revoked_tokens):
            raise ValueError(
                "Production requires Firebase Auth, App Check, and revoked-token checks"
            )
        if not web_allowed_origins:
            raise ValueError("WEB_ALLOWED_ORIGINS is required in production")
        if any(not origin.startswith("https://") for origin in web_allowed_origins):
            raise ValueError("Production WEB_ALLOWED_ORIGINS must use HTTPS")
        if not api_allowed_hosts:
            raise ValueError("API_ALLOWED_HOSTS is required in production")
        if any(host == "*" for host in api_allowed_hosts):
            raise ValueError("API_ALLOWED_HOSTS cannot contain a wildcard in production")
        allow_local_cors = False
    return Settings(
        model_path=_resolve_path(
            os.getenv("MODEL_PATH"), backend_dir / "models" / "disease_model.pkl"
        ),
        model_expected_sha256=_expected_model_sha256(backend_dir),
        feature_columns_path=_resolve_path(
            os.getenv("FEATURE_COLUMNS_PATH"),
            backend_dir / "models" / "feature_columns.json",
        ),
        confidence_threshold=threshold,
        google_application_credentials=os.getenv("GOOGLE_APPLICATION_CREDENTIALS"),
        firestore_timeout_seconds=firestore_timeout,
        model_version=os.getenv("MODEL_VERSION", "1.0.0"),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
        environment=environment,
        web_allowed_origins=web_allowed_origins,
        api_allowed_hosts=api_allowed_hosts,
        allow_local_cors=allow_local_cors,
        require_firebase_auth=require_firebase_auth,
        require_app_check=require_app_check,
        check_revoked_tokens=check_revoked_tokens,
        ai_rate_limit_requests=rate_limit_requests,
        ai_rate_limit_window_seconds=rate_limit_window,
        api_rate_limit_requests=api_rate_limit_requests,
        api_rate_limit_window_seconds=api_rate_limit_window,
        ocr_rate_limit_requests=ocr_rate_limit_requests,
        ocr_rate_limit_window_seconds=ocr_rate_limit_window,
    )
