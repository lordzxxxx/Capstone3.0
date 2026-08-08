"""Safe, single-initialization access to Firebase Admin and Firestore."""

from __future__ import annotations

import json
import os
from pathlib import Path
from threading import Lock
from typing import Any, Callable

_INITIALIZE_LOCK = Lock()
_FIRESTORE_CLIENTS: dict[str, Any] = {}
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _load_project_environment() -> None:
    """Load the ignored project .env for API and standalone backend scripts."""
    try:
        from dotenv import load_dotenv

        load_dotenv(PROJECT_ROOT / ".env", override=False)
    except ImportError:
        pass


class FirebaseConfigurationError(RuntimeError):
    """Raised when Firebase Admin cannot obtain usable credentials."""


def get_firebase_app() -> Any:
    """Return the default Admin app, initializing it from safe credentials."""
    _load_project_environment()
    try:
        import firebase_admin
    except ImportError as exc:
        raise FirebaseConfigurationError(
            "firebase-admin is not installed; install backend/requirements.txt"
        ) from exc

    with _INITIALIZE_LOCK:
        try:
            return firebase_admin.get_app()
        except ValueError:
            if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
                raise FirebaseConfigurationError(
                    "GOOGLE_APPLICATION_CREDENTIALS is not set. Point it to a "
                    "service-account JSON file; never commit that file."
                )
            try:
                return firebase_admin.initialize_app()
            except Exception as exc:
                raise FirebaseConfigurationError(
                    f"Firebase Admin initialization failed: {exc}"
                ) from exc


def _configured_database_id() -> str | None:
    """Read a named database ID from the environment or firebase.json."""
    database_id = os.getenv("FIRESTORE_DATABASE_ID")
    if database_id:
        return database_id
    firebase_config = Path(__file__).resolve().parents[2] / "firebase.json"
    if not firebase_config.exists():
        return None
    try:
        payload = json.loads(firebase_config.read_text(encoding="utf-8"))
        firestore_config = payload.get("firestore")
        if isinstance(firestore_config, list) and firestore_config:
            configured = firestore_config[0].get("database")
            return str(configured) if configured else None
    except (OSError, ValueError, TypeError):
        return None
    return None


def get_firestore_client(
    client_factory: Callable[[], Any] | None = None,
    database_id: str | None = None,
) -> Any:
    """Return an injected client or initialize Firebase Admin exactly once."""
    _load_project_environment()
    if client_factory is not None:
        return client_factory()
    try:
        from firebase_admin import firestore
    except ImportError as exc:
        raise FirebaseConfigurationError(
            "firebase-admin is not installed; install backend/requirements.txt"
        ) from exc

    get_firebase_app()
    selected_database = database_id or _configured_database_id() or "(default)"
    with _INITIALIZE_LOCK:
        if selected_database in _FIRESTORE_CLIENTS:
            return _FIRESTORE_CLIENTS[selected_database]
        try:
            client = firestore.client(database_id=selected_database)
        except Exception as exc:
            raise FirebaseConfigurationError(
                f"Could not create the Firestore client: {exc}"
            ) from exc
        _FIRESTORE_CLIENTS[selected_database] = client
        return client
