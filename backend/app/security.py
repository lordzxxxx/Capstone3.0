"""Firebase authentication, App Check, and bounded AI API rate limiting."""

from __future__ import annotations

import hashlib
import logging
import math
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Any, Callable, Protocol

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

SECURITY_LOGGER = logging.getLogger("ai_dsuhis.api")

try:
    from .config import get_settings
    from .firebase_service import (
        FirebaseConfigurationError,
        get_firestore_client,
        get_firebase_app,
    )
except ImportError:  # Supports imports from backend/app on sys.path.
    from config import get_settings
    from firebase_service import (
        FirebaseConfigurationError,
        get_firestore_client,
        get_firebase_app,
    )


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str


class RateLimitBackendUnavailable(RuntimeError):
    """Raised when the configured distributed limiter cannot be reached."""


class RateLimiter(Protocol):
    def consume(self, key: str) -> int | None:
        """Record one request or return the seconds until another is allowed."""


class SlidingWindowRateLimiter:
    """Thread-safe in-process limiter suitable for the single laptop API."""

    def __init__(
        self,
        limit: int,
        window_seconds: int,
        clock: Callable[[], float] = time.monotonic,
        max_keys: int = 10_000,
    ) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._clock = clock
        self._max_keys = max_keys
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
            if not hits:
                self._hits.pop(key, None)
                hits = self._hits[key]
            if len(hits) >= self.limit:
                return max(1, math.ceil(hits[0] + self.window_seconds - now))
            hits.append(now)
            if len(self._hits) > self._max_keys:
                oldest_key = min(
                    self._hits,
                    key=lambda candidate: self._hits[candidate][-1]
                    if self._hits[candidate]
                    else float("-inf"),
                )
                if oldest_key != key:
                    self._hits.pop(oldest_key, None)
            return None


TransactionOperation = Callable[[Any], int | None]
TransactionRunner = Callable[[Any, TransactionOperation], int | None]


def _run_firestore_transaction(
    client: Any,
    operation: TransactionOperation,
) -> int | None:
    """Run a Firestore transaction without importing the SDK at module load."""
    from google.cloud.firestore_v1 import transactional

    transaction = client.transaction()

    @transactional
    def execute(active_transaction: Any) -> int | None:
        return operation(active_transaction)

    return execute(transaction)


class FirestoreRateLimiter:
    """Atomic cross-instance limiter backed by a Firestore transaction.

    Only a namespace-scoped digest of the caller key is persisted. The
    ``expiresAt`` field is intentionally included so the collection can use a
    Firestore TTL policy without retaining caller identifiers indefinitely.
    """

    def __init__(
        self,
        limit: int,
        window_seconds: int,
        *,
        namespace: str,
        clock: Callable[[], datetime] | None = None,
        client_factory: Callable[[], Any] = get_firestore_client,
        transaction_runner: TransactionRunner = _run_firestore_transaction,
        collection: str = "api_rate_limits",
    ) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self.namespace = namespace
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._client_factory = client_factory
        self._transaction_runner = transaction_runner
        self._collection = collection

    def _document_id(self, key: str) -> str:
        digest = hashlib.sha256(
            f"{self.namespace}:{key}".encode("utf-8")
        ).hexdigest()
        return f"{self.namespace}-{digest}"

    @staticmethod
    def _timestamp(value: object) -> datetime | None:
        if not isinstance(value, datetime):
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def consume(self, key: str) -> int | None:
        now = self._timestamp(self._clock())
        if now is None:
            raise RateLimitBackendUnavailable("The rate-limit clock is invalid.")
        document_id = self._document_id(key)
        try:
            client = self._client_factory()
            document = client.collection(self._collection).document(document_id)

            def operation(transaction: Any) -> int | None:
                snapshot = transaction.get(document)
                data = snapshot.to_dict() if getattr(snapshot, "exists", False) else {}
                started = self._timestamp(data.get("windowStarted"))
                count = int(data.get("count", 0) or 0)
                window_end = (
                    started + timedelta(seconds=self.window_seconds)
                    if started is not None
                    else None
                )
                if window_end is not None and now < window_end:
                    if count >= self.limit:
                        return max(1, math.ceil((window_end - now).total_seconds()))
                else:
                    started = now
                    count = 0

                if started is None:
                    started = now
                    count = 0
                transaction.set(
                    document,
                    {
                        "namespace": self.namespace,
                        "keyDigest": document_id.split("-", 1)[1],
                        "count": count + 1,
                        "windowStarted": started,
                        "expiresAt": started + timedelta(seconds=self.window_seconds),
                    },
                    merge=True,
                )
                return None

            return self._transaction_runner(client, operation)
        except RateLimitBackendUnavailable:
            raise
        except Exception as exc:
            SECURITY_LOGGER.error(
                "Distributed rate-limit backend unavailable",
                extra={"event": "rate_limit_backend_unavailable"},
            )
            raise RateLimitBackendUnavailable(
                "The distributed rate-limit backend is unavailable."
            ) from exc


_bearer = HTTPBearer(auto_error=False)
_limiter: RateLimiter | None = None
_limiter_config: tuple[str, int, int] | None = None
_ocr_limiter: RateLimiter | None = None
_ocr_limiter_config: tuple[str, int, int] | None = None
_api_limiter: RateLimiter | None = None
_api_limiter_config: tuple[str, int, int] | None = None
_limiter_lock = Lock()


def _build_rate_limiter(
    backend: str,
    limit: int,
    window_seconds: int,
    *,
    namespace: str,
) -> RateLimiter:
    if backend == "firestore":
        return FirestoreRateLimiter(
            limit,
            window_seconds,
            namespace=namespace,
        )
    return SlidingWindowRateLimiter(limit, window_seconds)


def _rate_limiter() -> RateLimiter:
    global _limiter, _limiter_config
    settings = get_settings()
    config = (
        settings.rate_limit_backend,
        settings.ai_rate_limit_requests,
        settings.ai_rate_limit_window_seconds,
    )
    with _limiter_lock:
        if _limiter is None or _limiter_config != config:
            _limiter = _build_rate_limiter(
                settings.rate_limit_backend,
                settings.ai_rate_limit_requests,
                settings.ai_rate_limit_window_seconds,
                namespace="ai",
            )
            _limiter_config = config
        return _limiter


def _ocr_rate_limiter() -> RateLimiter:
    global _ocr_limiter, _ocr_limiter_config
    settings = get_settings()
    config = (
        settings.rate_limit_backend,
        settings.ocr_rate_limit_requests,
        settings.ocr_rate_limit_window_seconds,
    )
    with _limiter_lock:
        if _ocr_limiter is None or _ocr_limiter_config != config:
            _ocr_limiter = _build_rate_limiter(
                settings.rate_limit_backend,
                settings.ocr_rate_limit_requests,
                settings.ocr_rate_limit_window_seconds,
                namespace="ocr",
            )
            _ocr_limiter_config = config
        return _ocr_limiter


def _api_rate_limiter() -> RateLimiter:
    global _api_limiter, _api_limiter_config
    settings = get_settings()
    config = (
        settings.rate_limit_backend,
        settings.api_rate_limit_requests,
        settings.api_rate_limit_window_seconds,
    )
    with _limiter_lock:
        if _api_limiter is None or _api_limiter_config != config:
            _api_limiter = _build_rate_limiter(
                settings.rate_limit_backend,
                settings.api_rate_limit_requests,
                settings.api_rate_limit_window_seconds,
                namespace="api",
            )
            _api_limiter_config = config
        return _api_limiter


def _consume_or_fail_closed(limiter: RateLimiter, key: str) -> int | None:
    try:
        return limiter.consume(key)
    except RateLimitBackendUnavailable:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Request protection is temporarily unavailable.",
        ) from None


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

    retry_after = _consume_or_fail_closed(_rate_limiter(), uid)
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


def enforce_ocr_rate_limit(user: AuthenticatedUser) -> None:
    """Apply a tighter limit to OCR because it invokes a costly ML model."""
    retry_after = _consume_or_fail_closed(_ocr_rate_limiter(), user.uid)
    if retry_after is not None:
        SECURITY_LOGGER.warning(
            "OCR request rate limit exceeded",
            extra={"event": "ocr_rate_limited", "uid": user.uid},
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many OCR requests. Please try again shortly.",
            headers={"Retry-After": str(retry_after)},
        )


def enforce_api_rate_limit(client_key: str) -> None:
    """Limit unauthenticated API traffic by client address before parsing."""
    retry_after = _consume_or_fail_closed(_api_rate_limiter(), client_key)
    if retry_after is not None:
        SECURITY_LOGGER.warning(
            "API request rate limit exceeded",
            extra={"event": "api_rate_limited"},
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many API requests. Please try again shortly.",
            headers={"Retry-After": str(retry_after)},
        )
