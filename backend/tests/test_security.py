"""Authentication and rate-limit tests for the private AI endpoint."""

import io
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
from PIL import Image
import pytest

import api
from config import get_settings
from security import (
    FirestoreRateLimiter,
    RateLimitBackendUnavailable,
    SlidingWindowRateLimiter,
    _consume_or_fail_closed,
    enforce_api_rate_limit,
    require_ai_access,
)


class _FakeSnapshot:
    def __init__(self, data: dict[str, object] | None) -> None:
        self._data = data
        self.exists = data is not None

    def to_dict(self) -> dict[str, object]:
        return dict(self._data or {})


class _FakeDocument:
    def __init__(self, store: dict[str, dict[str, object]], document_id: str) -> None:
        self._store = store
        self.document_id = document_id


class _FakeCollection:
    def __init__(self, store: dict[str, dict[str, object]]) -> None:
        self._store = store

    def document(self, document_id: str) -> _FakeDocument:
        return _FakeDocument(self._store, document_id)


class _FakeTransaction:
    def __init__(self, store: dict[str, dict[str, object]]) -> None:
        self._store = store

    def get(self, document: _FakeDocument) -> _FakeSnapshot:
        return _FakeSnapshot(self._store.get(document.document_id))

    def set(
        self,
        document: _FakeDocument,
        data: dict[str, object],
        *,
        merge: bool,
    ) -> None:
        assert merge is True
        current = self._store.get(document.document_id, {})
        self._store[document.document_id] = {**current, **data}


class _FakeFirestoreClient:
    def __init__(self) -> None:
        self.store: dict[str, dict[str, object]] = {}

    def collection(self, _name: str) -> _FakeCollection:
        return _FakeCollection(self.store)


def _run_fake_transaction(
    client: _FakeFirestoreClient,
    operation,
) -> int | None:
    return operation(_FakeTransaction(client.store))


def test_guidance_rejects_missing_firebase_authentication() -> None:
    api.app.dependency_overrides.pop(api.require_ai_access, None)
    response = TestClient(api.app).post(
        "/guidance", json={"symptoms": ["fever"]}
    )
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_guidance_rejects_invalid_firebase_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from firebase_admin import auth

    api.app.dependency_overrides.pop(api.require_ai_access, None)
    monkeypatch.setattr("security.get_firebase_app", lambda: object())

    def reject_token(*_args: object, **_kwargs: object) -> None:
        raise ValueError("invalid test token")

    monkeypatch.setattr(auth, "verify_id_token", reject_token)
    response = TestClient(api.app).post(
        "/guidance",
        headers={"Authorization": "Bearer invalid-test-token"},
        json={"symptoms": ["fever"]},
    )
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_guidance_rejects_invalid_app_check_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from firebase_admin import app_check, auth

    api.app.dependency_overrides.pop(api.require_ai_access, None)
    monkeypatch.setattr("security.get_firebase_app", lambda: object())
    monkeypatch.setattr(auth, "verify_id_token", lambda *_args, **_kwargs: {"uid": "u2"})

    def reject_app_check(*_args: object, **_kwargs: object) -> None:
        raise ValueError("invalid test app check")

    monkeypatch.setattr(app_check, "verify_token", reject_app_check)
    response = TestClient(api.app).post(
        "/guidance",
        headers={
            "Authorization": "Bearer valid-test-token",
            "X-Firebase-AppCheck": "invalid-test-app-check",
        },
        json={"symptoms": ["fever"]},
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "The Firebase App Check token is invalid."


def test_app_check_is_required_after_valid_user_token(monkeypatch: pytest.MonkeyPatch) -> None:
    from firebase_admin import auth

    monkeypatch.setattr(auth, "verify_id_token", lambda *args, **kwargs: {"uid": "u1"})
    monkeypatch.setattr("security.get_firebase_app", lambda: object())
    with pytest.raises(Exception) as error:
        require_ai_access(
            credentials=HTTPAuthorizationCredentials(
                scheme="Bearer", credentials="valid-test-token"
            ),
            app_check_token=None,
        )
    assert error.value.status_code == 403


def test_sliding_window_rate_limiter_returns_retry_after() -> None:
    now = [100.0]
    limiter = SlidingWindowRateLimiter(2, 60, clock=lambda: now[0])
    assert limiter.consume("user-1") is None
    assert limiter.consume("user-1") is None
    assert limiter.consume("user-1") == 60
    now[0] = 161.0
    assert limiter.consume("user-1") is None


def test_firestore_rate_limiter_is_atomic_and_does_not_store_raw_key() -> None:
    client = _FakeFirestoreClient()
    now = [datetime(2026, 1, 1, tzinfo=timezone.utc)]
    limiter = FirestoreRateLimiter(
        2,
        60,
        namespace="ai",
        clock=lambda: now[0],
        client_factory=lambda: client,
        transaction_runner=_run_fake_transaction,
    )

    assert limiter.consume("user-1") is None
    assert limiter.consume("user-1") is None
    assert limiter.consume("user-1") == 60
    assert len(client.store) == 1
    document = next(iter(client.store.values()))
    assert document["namespace"] == "ai"
    assert document["keyDigest"] != "user-1"
    assert document["expiresAt"] == now[0] + timedelta(seconds=60)

    now[0] += timedelta(seconds=61)
    assert limiter.consume("user-1") is None


def test_firestore_rate_limiter_fails_closed_when_backend_is_unavailable() -> None:
    limiter = FirestoreRateLimiter(
        1,
        60,
        namespace="ai",
        client_factory=lambda: (_ for _ in ()).throw(RuntimeError("offline")),
    )

    with pytest.raises(RateLimitBackendUnavailable):
        limiter.consume("user-1")


def test_rate_limit_backend_failure_returns_safe_503() -> None:
    class FailingLimiter:
        def consume(self, _key: str) -> int | None:
            raise RateLimitBackendUnavailable("test-only backend failure")

    with pytest.raises(HTTPException) as error:
        _consume_or_fail_closed(FailingLimiter(), "user-1")
    assert error.value.status_code == 503
    assert error.value.detail == "Request protection is temporarily unavailable."


def test_security_defaults_fail_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    for key in (
        "AI_REQUIRE_FIREBASE_AUTH",
        "AI_REQUIRE_APP_CHECK",
        "AI_CHECK_REVOKED_TOKENS",
    ):
        monkeypatch.delenv(key, raising=False)
    get_settings.cache_clear()
    settings = get_settings()
    assert settings.require_firebase_auth is True
    assert settings.require_app_check is True
    assert settings.check_revoked_tokens is True
    assert settings.rate_limit_backend == "memory"


def test_model_runtime_version_mismatch_fails_closed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import sklearn

    monkeypatch.setattr(sklearn, "__version__", "0.0.0")
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="does not match the serialized model"):
        get_settings()
    get_settings.cache_clear()


def test_production_requires_distributed_rate_limiting(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("WEB_ALLOWED_ORIGINS", "https://example.test")
    monkeypatch.setenv("API_ALLOWED_HOSTS", "api.example.test")
    monkeypatch.setenv("RATE_LIMIT_BACKEND", "memory")
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="RATE_LIMIT_BACKEND=firestore"):
        get_settings()
    get_settings.cache_clear()


def test_production_requires_explicit_network_settings(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("WEB_ALLOWED_ORIGINS", raising=False)
    monkeypatch.delenv("API_ALLOWED_HOSTS", raising=False)
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="WEB_ALLOWED_ORIGINS"):
        get_settings()
    get_settings.cache_clear()


def test_ocr_rejects_missing_authentication() -> None:
    api.app.dependency_overrides.pop(api.require_ai_access, None)
    response = TestClient(api.app).post("/api/v1/ocr/handwriting")
    assert response.status_code == 401


def test_ocr_rejects_non_image_upload() -> None:
    response = TestClient(api.app).post(
        "/api/v1/ocr/handwriting",
        data={"field_id": "patient_name"},
        files={"file": ("payload.txt", b"not an image", "text/plain")},
    )
    assert response.status_code == 415


def _valid_ocr_image() -> bytes:
    image = Image.new("RGB", (32, 32), "white")
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def test_ocr_fails_closed_when_model_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        api.TrOCRHandwritingEngine,
        "get_instance",
        lambda: type("UnavailableEngine", (), {"is_ready": False})(),
    )
    response = TestClient(api.app).post(
        "/api/v1/ocr/handwriting",
        data={"field_id": "patient_name"},
        files={"file": ("form.png", _valid_ocr_image(), "image/png")},
    )
    assert response.status_code == 503
    assert response.json()["detail"] == (
        "Handwriting recognition is temporarily unavailable."
    )


def test_ocr_hides_model_errors_from_clients(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FailingEngine:
        is_ready = True

        def recognize_single(self, _content: bytes) -> tuple[str, float]:
            raise RuntimeError("internal model details")

    monkeypatch.setattr(
        api.TrOCRHandwritingEngine, "get_instance", lambda: FailingEngine()
    )
    response = TestClient(api.app).post(
        "/api/v1/ocr/handwriting",
        data={"field_id": "patient_name"},
        files={"file": ("form.png", _valid_ocr_image(), "image/png")},
    )
    assert response.status_code == 503
    assert "internal model details" not in response.text


def test_api_sets_no_store_security_headers() -> None:
    response = TestClient(api.app).get("/health")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["content-security-policy"].startswith("default-src")


def test_api_returns_a_correlation_id_without_logging_payloads() -> None:
    response = TestClient(api.app).get(
        "/health", headers={"X-Request-ID": "qa-health-01"}
    )
    assert response.status_code == 200
    assert response.headers["x-request-id"] == "qa-health-01"


def test_health_is_liveness_only_and_does_not_load_the_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(api, "artifacts_cache_is_warm", lambda: False)

    def model_load_must_not_run() -> bool:
        raise AssertionError("health must not synchronously load the model")

    monkeypatch.setattr(api, "model_loaded_successfully", model_load_must_not_run)
    response = TestClient(api.app).get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert response.json()["modelLoaded"] is False


def test_readiness_fails_closed_when_firebase_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(api, "model_loaded_successfully", lambda: True)

    def unavailable_firebase() -> None:
        raise api.FirebaseConfigurationError("test-only failure")

    monkeypatch.setattr(api, "get_firebase_app", unavailable_firebase)
    response = TestClient(api.app).get("/ready")
    assert response.status_code == 503
    assert response.json()["detail"] == "The AI service is not ready."


def test_api_rejects_unconfigured_host() -> None:
    response = TestClient(api.app).get(
        "/health", headers={"host": "untrusted.example"}
    )
    assert response.status_code == 400


def test_api_rate_limiter_returns_retry_after(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("API_RATE_LIMIT_REQUESTS", "1")
    get_settings.cache_clear()
    key = "api-rate-test-client"
    enforce_api_rate_limit(key)
    with pytest.raises(Exception) as error:
        enforce_api_rate_limit(key)
    assert error.value.status_code == 429
    assert error.value.headers["Retry-After"]
    get_settings.cache_clear()
