"""Small, deterministic retrieval primitives for grounded guidance.

The active guidance corpus is intentionally small and Firestore-backed. This
module provides a bounded hybrid lexical/metadata retriever rather than
pretending that the existing classifier is a semantic search system. It keeps
retrieval separate from both disease classification and optional LLM output.
"""

from __future__ import annotations

import hashlib
import re
from typing import Any, Iterable

from sklearn.feature_extraction.text import TfidfVectorizer

_TOKEN_PATTERN = re.compile(r"[a-z0-9]+")
_TEXT_FIELDS = (
    "symptom",
    "title",
    "description",
    "homeCare",
    "precautions",
    "whenToSeekCare",
    "emergencyWarningSigns",
    "commonSymptoms",
    "selfCareGuidance",
    "avoidOrCaution",
    "whenToSeeDoctor",
)


def _tokens(value: object) -> set[str]:
    return set(_TOKEN_PATTERN.findall(str(value).casefold().replace("_", " ")))


def _flatten_text(document: dict[str, Any]) -> str:
    parts: list[str] = []
    for field in _TEXT_FIELDS:
        value = document.get(field)
        if isinstance(value, list):
            parts.extend(str(item).strip() for item in value if str(item).strip())
        elif value is not None and str(value).strip():
            parts.append(str(value).strip())
    return " ".join(parts)


def _first_reference(document: dict[str, Any]) -> dict[str, str]:
    references = document.get("references")
    if not isinstance(references, list):
        return {}
    for reference in references:
        if not isinstance(reference, dict):
            continue
        url = str(reference.get("url", "")).strip()
        if url:
            return {
                "organization": str(reference.get("organization", "")).strip(),
                "title": str(reference.get("title", "")).strip(),
                "url": url,
            }
    return {}


def _citation_id(source_id: str, version: str, url: str) -> str:
    digest = hashlib.sha256(
        f"{source_id}|{version}|{url}".encode("utf-8")
    ).hexdigest()[:12]
    return f"ref-{digest}"


def build_evidence_sources(
    documents: Iterable[dict[str, Any]],
    *,
    source_prefix: str,
    matched_terms: Iterable[str] = (),
) -> list[dict[str, Any]]:
    """Convert active knowledge records into citation-bearing source chunks."""
    terms = [str(term).strip() for term in matched_terms if str(term).strip()]
    sources: list[dict[str, Any]] = []
    for index, raw_document in enumerate(documents):
        document = dict(raw_document)
        if document.get("isActive", True) is not True:
            continue
        key = str(
            document.get("symptomKey")
            or document.get("diseaseKey")
            or document.get("key")
            or index
        ).strip()
        source_id = f"{source_prefix}:{key}"
        version = str(
            document.get("contentVersion")
            or document.get("version")
            or "unversioned"
        ).strip()
        reference = _first_reference(document)
        url = reference.get("url", "")
        review = document.get("clinicalReview")
        review_status = (
            str(review.get("status", "needs_review")).strip()
            if isinstance(review, dict)
            else "needs_review"
        )
        context_text = _flatten_text(document)
        sources.append(
            {
                "citationId": _citation_id(source_id, version, url),
                "sourceId": source_id,
                "title": str(
                    document.get("title")
                    or document.get("name")
                    or document.get("symptom")
                    or document.get("diseaseKey")
                    or key
                ).strip(),
                "organization": reference.get("organization", ""),
                "version": version,
                "publicationDate": str(
                    document.get("publicationDate")
                    or document.get("publishedAt")
                    or ""
                ).strip(),
                "reviewStatus": review_status or "needs_review",
                "url": url,
                "matchedTerms": list(terms),
                "contextText": context_text[:4000],
                "_documentKey": key,
            }
        )
    return sources


def rank_evidence(
    query_terms: Iterable[str],
    sources: Iterable[dict[str, Any]],
    *,
    top_k: int = 8,
    minimum_score: float = 0.12,
) -> list[dict[str, Any]]:
    """Rank source chunks using bounded keyword overlap and metadata matches.

    The score is deliberately explainable: exact source-key matches carry the
    most weight, followed by token overlap. A default guidance source is
    retained at a small score so it can provide baseline safety warnings, but
    it cannot outrank a directly matched source.
    """
    terms = [str(term).strip() for term in query_terms if str(term).strip()]
    source_list = [dict(source) for source in sources]
    query_tokens = _tokens(" ".join(terms))
    vector_similarities = [0.0] * len(source_list)
    if query_tokens and source_list:
        try:
            vectorizer = TfidfVectorizer(
                lowercase=True,
                ngram_range=(1, 2),
                token_pattern=r"(?u)\b[a-zA-Z0-9][a-zA-Z0-9_]+\b",
            )
            matrix = vectorizer.fit_transform(
                [" ".join(terms)]
                + [str(source.get("contextText", "")) for source in source_list]
            )
            vector_similarities = matrix[0].dot(matrix[1:].T).toarray()[0].tolist()
        except ValueError:
            # An empty or underspecified corpus still receives deterministic
            # keyword scoring; retrieval must never fail because vectorization
            # has no vocabulary.
            vector_similarities = [0.0] * len(source_list)
    ranked: list[dict[str, Any]] = []
    for index, source in enumerate(source_list):
        source_copy = dict(source)
        source_key = str(
            source_copy.get("_documentKey")
            or str(source_copy.get("sourceId", "")).rsplit(":", 1)[-1]
        ).casefold()
        source_tokens = _tokens(
            " ".join(
                (
                    str(source_copy.get("title", "")),
                    str(source_copy.get("contextText", "")),
                )
            )
        )
        overlap = len(query_tokens & source_tokens)
        overlap_ratio = overlap / max(1, len(query_tokens))
        exact = any(
            term.casefold().replace(" ", "_") == source_key
            or term.casefold() == str(source_copy.get("title", "")).casefold()
            for term in terms
        )
        is_default = source_key in {"_default", "default"}
        vector_similarity = float(vector_similarities[index])
        score = (
            (0.62 if exact else 0.0)
            + min(0.2, overlap_ratio * 0.2)
            + min(0.18, vector_similarity * 0.18)
        )
        if is_default and score == 0.0:
            score = 0.12
        if score < minimum_score:
            continue
        source_copy["relevanceScore"] = round(min(1.0, score), 4)
        source_copy["vectorSimilarity"] = round(vector_similarity, 4)
        source_copy.pop("_documentKey", None)
        ranked.append(source_copy)

    ranked.sort(
        key=lambda item: (
            -float(item.get("relevanceScore", 0.0)),
            str(item.get("citationId", "")),
        )
    )
    return ranked[: max(1, top_k)]

