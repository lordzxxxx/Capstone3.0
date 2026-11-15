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
    rate_limit_backend: str
    turnstile_secret_key: str | None
    turnstile_hostnames: tuple[str, ...]
    rag_top_k: int
    rag_min_score: float
    llm_provider: str
    llm_endpoint: str | None
    llm_api_key: str | None
    llm_model: str
    llm_timeout_seconds: float
    llm_max_tokens: int


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


def _expected_sklearn_version(backend_dir: Path) -> str:
    metrics_path = backend_dir / "models" / "training_metrics.json"
    try:
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        expected = str(metrics.get("scikit_learn_version", "")).strip()
    except (OSError, json.JSONDecodeError):
        expected = ""
    if not expected:
        raise ValueError(
            "training_metrics.json must declare scikit_learn_version for "
            "the serialized model artifact"
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
    expected_sklearn_version = _expected_sklearn_version(backend_dir)
    try:
        import sklearn
    except ImportError as exc:
        raise ValueError(
            "scikit-learn is required to load the verified model artifact"
        ) from exc
    if sklearn.__version__ != expected_sklearn_version:
        raise ValueError(
            "scikit-learn runtime does not match the serialized model artifact: "
            f"expected {expected_sklearn_version}, found {sklearn.__version__}"
        )
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
    default_rate_limit_backend = (
        "firestore" if environment in {"staging", "production"} else "memory"
    )
    rate_limit_backend = os.getenv(
        "RATE_LIMIT_BACKEND", default_rate_limit_backend
    ).strip().casefold()
    if rate_limit_backend not in {"memory", "firestore"}:
        raise ValueError("RATE_LIMIT_BACKEND must be memory or firestore")
    turnstile_secret_key = os.getenv("TURNSTILE_SECRET_KEY", "").strip() or None
    turnstile_hostnames = _list_env(
        "TURNSTILE_HOSTNAMES",
        ("ai-dsuhis.com", "www.ai-dsuhis.com"),
    )
    rag_top_k = int(os.getenv("RAG_TOP_K", "8"))
    rag_min_score = float(os.getenv("RAG_MIN_SCORE", "0.12"))
    if not 1 <= rag_top_k <= 20:
        raise ValueError("RAG_TOP_K must be between 1 and 20")
    if not 0.0 <= rag_min_score <= 1.0:
        raise ValueError("RAG_MIN_SCORE must be between 0 and 1")
    llm_provider = os.getenv("LLM_PROVIDER", "disabled").strip().casefold()
    if llm_provider not in {"disabled", "http_json"}:
        raise ValueError("LLM_PROVIDER must be disabled or http_json")
    llm_endpoint = os.getenv("LLM_ENDPOINT", "").strip() or None
    llm_api_key = os.getenv("LLM_API_KEY", "").strip() or None
    llm_model = os.getenv("LLM_MODEL", "").strip() or "configured-model"
    llm_timeout_seconds = float(os.getenv("LLM_TIMEOUT_SECONDS", "8"))
    llm_max_tokens = int(os.getenv("LLM_MAX_TOKENS", "300"))
    if not 0.5 <= llm_timeout_seconds <= 30.0:
        raise ValueError("LLM_TIMEOUT_SECONDS must be between 0.5 and 30")
    if not 32 <= llm_max_tokens <= 2000:
        raise ValueError("LLM_MAX_TOKENS must be between 32 and 2000")
    if llm_provider == "http_json" and (not llm_endpoint or not llm_api_key):
        raise ValueError("LLM_ENDPOINT and LLM_API_KEY are required for http_json")
    if environment == "production" and llm_endpoint and not llm_endpoint.startswith("https://"):
        raise ValueError("Production LLM_ENDPOINT must use HTTPS")

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
        if rate_limit_backend != "firestore":
            raise ValueError("Production requires RATE_LIMIT_BACKEND=firestore")
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
        rate_limit_backend=rate_limit_backend,
        turnstile_secret_key=turnstile_secret_key,
        turnstile_hostnames=turnstile_hostnames,
        rag_top_k=rag_top_k,
        rag_min_score=rag_min_score,
        llm_provider=llm_provider,
        llm_endpoint=llm_endpoint,
        llm_api_key=llm_api_key,
        llm_model=llm_model,
        llm_timeout_seconds=llm_timeout_seconds,
        llm_max_tokens=llm_max_tokens,
    )
