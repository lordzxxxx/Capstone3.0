"""Firestore-backed symptom guidance retrieval and deterministic aggregation."""

from __future__ import annotations

import re
from typing import Any, Callable, Iterable

try:
    from .firebase_service import get_firestore_client
    from .rag_service import build_evidence_sources, rank_evidence
except ImportError:  # Direct execution support.
    from firebase_service import get_firestore_client
    from rag_service import build_evidence_sources, rank_evidence


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
        rag_top_k: int = 8,
        rag_min_score: float = 0.12,
    ) -> None:
        self._db = db
        self._client_factory = client_factory
        self._timeout_seconds = timeout_seconds
        self._rag_top_k = rag_top_k
        self._rag_min_score = rag_min_score

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

    def _get_active_documents(self, keys: Iterable[str]) -> dict[str, dict[str, Any]]:
        """Read guidance documents in one Firestore batch when supported.

        The small fallback keeps the service compatible with the lightweight
        database doubles used by tests and with older injected clients. The
        production Firebase Admin client exposes ``get_all`` and avoids one
        network round trip per recognized symptom.
        """
        unique_keys = list(dict.fromkeys(keys))
        if not unique_keys:
            return {}

        collection = self.db.collection("symptom_guidance")
        get_all = getattr(self.db, "get_all", None)
        if not callable(get_all):
            return {
                key: document
                for key in unique_keys
                if (document := self.get_by_key(key)) is not None
            }

        references = [collection.document(key) for key in unique_keys]
        snapshots = get_all(
            references,
            retry=None,
            timeout=self._timeout_seconds,
        )
        documents: dict[str, dict[str, Any]] = {}
        for key, snapshot in zip(unique_keys, snapshots):
            if not snapshot.exists:
                continue
            data = snapshot.to_dict() or {}
            if data.get("isActive") is True:
                documents[key] = dict(data)
        return documents

    def _get_all_active_documents(self) -> dict[str, dict[str, Any]]:
        """Load the small active corpus for local vector ranking when possible."""
        collection = self.db.collection("symptom_guidance")
        where = getattr(collection, "where", None)
        if not callable(where):
            return {}
        query = where("isActive", "==", True)
        stream = getattr(query, "stream", None)
        if not callable(stream):
            return {}
        documents: dict[str, dict[str, Any]] = {}
        for snapshot in stream(timeout=self._timeout_seconds):
            data = snapshot.to_dict() or {}
            if data.get("isActive") is not True:
                continue
            key = str(
                data.get("symptomKey") or getattr(snapshot, "id", "")
            ).strip()
            if key:
                documents[key] = dict(data)
        return documents

    def get_for_symptoms(self, symptoms: Iterable[str]) -> dict[str, Any]:
        """Merge default and symptom-specific guidance without diagnosis logic."""
        canonical = list(dict.fromkeys(str(item).strip() for item in symptoms))
        documents: list[dict[str, Any]] = []
        evidence_documents: list[dict[str, Any]] = []
        matched: list[str] = []
        missing: list[str] = []

        symptom_keys = [normalize_symptom_key(symptom) for symptom in canonical]
        loaded = self._get_active_documents(["_default", *symptom_keys])
        try:
            loaded.update(self._get_all_active_documents())
        except Exception:
            # Exact-key retrieval remains the safe compatibility path for
            # test doubles and older Firestore clients.
            pass
        default = loaded.get("_default")
        if default is not None:
            documents.append(default)

        for symptom, key in zip(canonical, symptom_keys):
            document = loaded.get(key)
            if document is None:
                missing.append(symptom)
                continue
            documents.append(document)
            matched.append(symptom)

        evidence_documents = [
            {**document, "symptomKey": key}
            for key, document in loaded.items()
            if document.get("isActive") is True
        ]

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

        retrieved_evidence = rank_evidence(
            canonical,
            build_evidence_sources(
                evidence_documents,
                source_prefix="symptom_guidance",
                matched_terms=matched,
            ),
            top_k=self._rag_top_k,
            minimum_score=self._rag_min_score,
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
            "retrievedEvidence": retrieved_evidence,
            "retrievalMethod": "local_tfidf_keyword_metadata_v1",
        }
