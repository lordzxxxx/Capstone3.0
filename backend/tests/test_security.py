"""Authentication and rate-limit tests for the private AI endpoint."""

from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
import pytest

import api
from config import get_settings
from security import SlidingWindowRateLimiter, require_ai_access


def test_guidance_rejects_missing_firebase_authentication() -> None:
    api.app.dependency_overrides.pop(api.require_ai_access, None)
    response = TestClient(api.app).post(
        "/guidance", json={"symptoms": ["fever"]}
    )
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


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
