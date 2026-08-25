"""Firebase authentication, App Check, and bounded AI API rate limiting."""

from __future__ import annotations

import math
import logging
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from threading import Lock
from typing import Callable

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

SECURITY_LOGGER = logging.getLogger("ai_dsuhis.api")

try:
    from .config import get_settings
    from .firebase_service import FirebaseConfigurationError, get_firebase_app
except ImportError:  # Supports imports from backend/app on sys.path.
    from config import get_settings
    from firebase_service import FirebaseConfigurationError, get_firebase_app


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str


class SlidingWindowRateLimiter:
    """Thread-safe in-process limiter suitable for the single laptop API."""

    def __init__(
        self,
        limit: int,
        window_seconds: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def consume(self, key: str) -> int | None:
        """Record one request or return the seconds until another is allowed."""
        now = self._clock()
        cutoff = now - self.window_seconds
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= cutoff:
                hits.popleft()
            if len(hits) >= self.limit:
                return max(1, math.ceil(hits[0] + self.window_seconds - now))
            hits.append(now)
            return None


_bearer = HTTPBearer(auto_error=False)
_limiter: SlidingWindowRateLimiter | None = None
_limiter_config: tuple[int, int] | None = None
_limiter_lock = Lock()


def _rate_limiter() -> SlidingWindowRateLimiter:
    global _limiter, _limiter_config
    settings = get_settings()
    config = (
        settings.ai_rate_limit_requests,
        settings.ai_rate_limit_window_seconds,
    )
    with _limiter_lock:
        if _limiter is None or _limiter_config != config:
            _limiter = SlidingWindowRateLimiter(*config)
            _limiter_config = config
        return _limiter


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_ai_access(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    app_check_token: str | None = Header(
        default=None, alias="X-Firebase-AppCheck"
    ),
) -> AuthenticatedUser:
    """Require a real Firebase user, valid app instance, and rate allowance."""
    settings = get_settings()
    uid = "local-security-disabled"

    if settings.require_firebase_auth:
        if credentials is None or credentials.scheme.casefold() != "bearer":
            SECURITY_LOGGER.warning(
                "AI request rejected without Firebase authentication",
                extra={"event": "ai_authentication_missing"},
            )
            raise _unauthorized("A Firebase ID token is required.")
        try:
            from firebase_admin import auth

            decoded = auth.verify_id_token(
                credentials.credentials,
                app=get_firebase_app(),
                check_revoked=settings.check_revoked_tokens,
            )
        except (ValueError, FirebaseConfigurationError):
            SECURITY_LOGGER.warning(
                "AI request rejected with an invalid Firebase token",
                extra={"event": "ai_authentication_invalid"},
            )
            raise _unauthorized("The Firebase ID token is invalid.") from None
        except Exception:
            SECURITY_LOGGER.warning(
                "AI request token verification failed",
                extra={"event": "ai_authentication_verification_error"},
            )
            raise _unauthorized("The Firebase ID token could not be verified.") from None
        uid = str(decoded.get("uid") or decoded.get("sub") or "").strip()
        if not uid:
            raise _unauthorized("The Firebase ID token has no user identity.")

    if settings.require_app_check:
        if not app_check_token:
            SECURITY_LOGGER.warning(
                "AI request rejected without App Check",
                extra={"event": "ai_app_check_missing", "uid": uid},
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="A Firebase App Check token is required.",
            )
        try:
            from firebase_admin import app_check

            app_check.verify_token(app_check_token, app=get_firebase_app())
        except Exception:
            SECURITY_LOGGER.warning(
                "AI request rejected with invalid App Check",
                extra={"event": "ai_app_check_invalid", "uid": uid},
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="The Firebase App Check token is invalid.",
            ) from None

    retry_after = _rate_limiter().consume(uid)
    if retry_after is not None:
        SECURITY_LOGGER.warning(
            "AI request rate limit exceeded",
            extra={"event": "ai_rate_limited", "uid": uid},
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many AI guidance requests. Please try again shortly.",
            headers={"Retry-After": str(retry_after)},
        )
    return AuthenticatedUser(uid=uid)
