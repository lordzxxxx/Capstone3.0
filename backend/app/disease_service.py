"""Read-only Firestore disease knowledge service."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Callable

BACKEND_DIR = Path(__file__).resolve().parents[1]
FIREBASE_DIR = BACKEND_DIR / "firebase"
if str(FIREBASE_DIR) not in sys.path:
    sys.path.insert(0, str(FIREBASE_DIR))

from disease_schema import normalize_disease_key  # noqa: E402

try:
    from .firebase_service import get_firestore_client
except ImportError:  # Direct execution support.
    from firebase_service import get_firestore_client


def _public_content(data: dict[str, Any], is_admin: bool) -> dict[str, Any]:
    result = dict(data)
    review = result.get("clinicalReview")
    if isinstance(review, dict) and not is_admin:
        result["clinicalReview"] = {"status": review.get("status", "needs_review")}
    return result


class DiseaseService:
    """Firestore-backed disease lookup with injectable clients for tests."""

    def __init__(
        self,
        db: Any | None = None,
        client_factory: Callable[[], Any] | None = None,
        timeout_seconds: float = 5.0,
    ) -> None:
        self._db = db
        self._client_factory = client_factory
        self._timeout_seconds = timeout_seconds

    @property
    def db(self) -> Any:
        if self._db is None:
            self._db = get_firestore_client(self._client_factory)
        return self._db

    def get_disease_by_key(
        self, disease_key: str, is_admin: bool = False
    ) -> dict[str, Any] | None:
        key = normalize_disease_key(disease_key)
        snapshot = self.db.collection("diseases").document(key).get(
            retry=None,
            timeout=self._timeout_seconds,
        )
        if not snapshot.exists:
            return None
        data = snapshot.to_dict() or {}
        if not data.get("isActive", False) and not is_admin:
            return None
        return _public_content(data, is_admin)

    @staticmethod
    def document_id_for_prediction(model_label: str) -> str:
        """Return the one deterministic Firestore document ID for a model label."""
        return normalize_disease_key(model_label)

    def get_disease_by_model_label(
        self, model_label: str, is_admin: bool = False
    ) -> dict[str, Any] | None:
        return self.get_disease_by_key(
            self.document_id_for_prediction(model_label), is_admin
        )

    def list_active_diseases(self, is_admin: bool = False) -> list[dict[str, Any]]:
        query = self.db.collection("diseases").where("isActive", "==", True)
        return [
            _public_content(snapshot.to_dict() or {}, is_admin)
            for snapshot in query.stream()
        ]

    def get_disease_content_for_prediction(
        self, model_label: str, is_admin: bool = False
    ) -> dict[str, Any] | None:
        return self.get_disease_by_model_label(model_label, is_admin)


def get_disease_by_key(disease_key: str) -> dict[str, Any] | None:
    return DiseaseService().get_disease_by_key(disease_key)


def get_disease_by_model_label(model_label: str) -> dict[str, Any] | None:
    return DiseaseService().get_disease_by_model_label(model_label)


def list_active_diseases() -> list[dict[str, Any]]:
    return DiseaseService().list_active_diseases()


def get_disease_content_for_prediction(
    model_label: str,
) -> dict[str, Any] | None:
    return DiseaseService().get_disease_content_for_prediction(model_label)
