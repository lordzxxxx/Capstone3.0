"""Firestore-backed symptom guidance retrieval and deterministic aggregation."""

from __future__ import annotations

import re
from typing import Any, Callable, Iterable

try:
    from .firebase_service import get_firestore_client
except ImportError:  # Direct execution support.
    from firebase_service import get_firestore_client


def normalize_symptom_key(value: object) -> str:
    """Create a stable Firestore document ID from a canonical symptom name."""
    text = str(value).strip().lower().replace("_", " ").replace("-", " ")
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_")


def _strings(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _deduplicate(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        key = value.casefold()
        if key not in seen:
            seen.add(key)
            result.append(value)
    return result


class SymptomGuidanceService:
    """Read reviewed symptom guidance without making a disease prediction."""

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

    def get_by_key(self, key: str) -> dict[str, Any] | None:
        snapshot = (
            self.db.collection("symptom_guidance")
            .document(key)
            .get(retry=None, timeout=self._timeout_seconds)
        )
        if not snapshot.exists:
            return None
        data = snapshot.to_dict() or {}
        if data.get("isActive") is not True:
            return None
        return dict(data)

    def get_for_symptoms(self, symptoms: Iterable[str]) -> dict[str, Any]:
        """Merge default and symptom-specific guidance without diagnosis logic."""
        canonical = list(dict.fromkeys(str(item).strip() for item in symptoms))
        documents: list[dict[str, Any]] = []
        matched: list[str] = []
        missing: list[str] = []

        default = self.get_by_key("_default")
        if default is not None:
            documents.append(default)

        for symptom in canonical:
            document = self.get_by_key(normalize_symptom_key(symptom))
            if document is None:
                missing.append(symptom)
                continue
            documents.append(document)
            matched.append(symptom)

        def merged(field: str) -> list[str]:
            return _deduplicate(
                item for document in documents for item in _strings(document.get(field))
            )

        references: list[dict[str, str]] = []
        seen_urls: set[str] = set()
        for document in documents:
            raw_references = document.get("references")
            if not isinstance(raw_references, list):
                continue
            for raw in raw_references:
                if not isinstance(raw, dict):
                    continue
                url = str(raw.get("url", "")).strip()
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)
                references.append(
                    {
                        "organization": str(raw.get("organization", "")).strip(),
                        "title": str(raw.get("title", "")).strip(),
                        "url": url,
                    }
                )

        return {
            "matchedGuidanceSymptoms": matched,
            "missingGuidanceSymptoms": missing,
            "homeCare": merged("homeCare"),
            "precautions": merged("precautions"),
            "whenToSeekCare": merged("whenToSeekCare"),
            "emergencyWarningSigns": merged("emergencyWarningSigns"),
            "references": references,
            "contentAvailable": bool(documents),
        }
