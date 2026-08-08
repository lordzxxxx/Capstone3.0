"""Typed schema and validation helpers for Firestore disease documents."""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Any, Iterable
from urllib.parse import urlparse

SERVER_TIMESTAMP = "__SERVER_TIMESTAMP__"
SELF_CARE_LEVELS = {
    "supportive",
    "prompt_medical_evaluation",
    "emergency_evaluation",
}
REVIEW_STATUSES = {"needs_review", "approved", "rejected"}
SERIOUS_DISEASE_KEYS = {
    "acute_kidney_injury",
    "acute_bronchospasm",
    "gastrointestinal_hemorrhage",
    "heart_attack",
    "sepsis",
    "sickle_cell_crisis",
    "spontaneous_abortion",
    "threatened_pregnancy",
}
PROHIBITED_MEDICAL_PHRASES = {
    "guaranteed cure",
    "proven cure",
    "treatment replacement",
    "safe for everyone",
}


def normalize_disease_key(name: str) -> str:
    """Create a stable, Firestore-safe document ID from a model label."""
    text = unicodedata.normalize("NFKD", str(name)).encode("ascii", "ignore").decode()
    text = text.strip().lower().replace("_", " ")
    text = re.sub(r"\s+", " ", text)
    text = text.replace("/", " ").replace("\\", " ")
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_")


def split_semicolon_values(value: object) -> list[str]:
    """Convert semicolon-delimited source text to clean non-empty strings."""
    if value is None:
        return []
    return [part.strip() for part in str(value).split(";") if part.strip()]


@dataclass(frozen=True)
class DiseaseReference:
    """An authoritative reference or explicitly labeled search-hub link."""

    organization: str
    title: str = ""
    url: str = ""
    accessed_at: str = ""

    def to_dict(self) -> dict[str, str]:
        """Return Firestore camelCase fields."""
        return {
            "organization": self.organization,
            "title": self.title,
            "url": self.url,
            "accessedAt": self.accessed_at,
        }


@dataclass(frozen=True)
class ClinicalReview:
    """Human clinical-review state; generated content always needs review."""

    status: str = "needs_review"
    reviewed_by: str = ""
    reviewed_at: str | None = None
    notes: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Return Firestore fields, omitting an unset review timestamp."""
        result: dict[str, Any] = {
            "status": self.status,
            "reviewedBy": self.reviewed_by,
            "notes": self.notes,
        }
        if self.reviewed_at is not None:
            result["reviewedAt"] = self.reviewed_at
        return result


@dataclass(frozen=True)
class DiseaseRecord:
    """Complete disease knowledge document stored in ``diseases/{key}``."""

    disease_key: str
    name: str
    model_label: str
    category: str
    self_care_level: str
    aliases: list[str] = field(default_factory=list)
    description: str = ""
    common_symptoms: list[str] = field(default_factory=list)
    dataset_symptoms: list[str] = field(default_factory=list)
    self_care_guidance: list[str] = field(default_factory=list)
    avoid_or_caution: list[str] = field(default_factory=list)
    prevention: list[str] = field(default_factory=list)
    risk_factors: list[str] = field(default_factory=list)
    possible_complications: list[str] = field(default_factory=list)
    when_to_see_doctor: list[str] = field(default_factory=list)
    emergency_warning_signs: list[str] = field(default_factory=list)
    recommended_specialist: list[str] = field(default_factory=list)
    icd10_codes: list[str] = field(default_factory=list)
    references: list[DiseaseReference] = field(default_factory=list)
    clinical_review: ClinicalReview = field(default_factory=ClinicalReview)
    content_version: str = "1.0.0"
    is_active: bool = True

    def to_dict(self, include_timestamps: bool = True) -> dict[str, Any]:
        """Serialize this record using Firestore camelCase field names."""
        result: dict[str, Any] = {
            "diseaseKey": self.disease_key,
            "name": self.name,
            "modelLabel": self.model_label,
            "aliases": self.aliases,
            "category": self.category,
            "description": self.description,
            "commonSymptoms": self.common_symptoms,
            "datasetSymptoms": self.dataset_symptoms,
            "selfCareLevel": self.self_care_level,
            "selfCareGuidance": self.self_care_guidance,
            "avoidOrCaution": self.avoid_or_caution,
            "prevention": self.prevention,
            "riskFactors": self.risk_factors,
            "possibleComplications": self.possible_complications,
            "whenToSeeDoctor": self.when_to_see_doctor,
            "emergencyWarningSigns": self.emergency_warning_signs,
            "recommendedSpecialist": self.recommended_specialist,
            "icd10Codes": self.icd10_codes,
            "references": [reference.to_dict() for reference in self.references],
            "clinicalReview": self.clinical_review.to_dict(),
            "contentVersion": self.content_version,
            "isActive": self.is_active,
        }
        if include_timestamps:
            result["createdAt"] = SERVER_TIMESTAMP
            result["updatedAt"] = SERVER_TIMESTAMP
        return result


def ensure_unique_disease_keys(labels: Iterable[str]) -> dict[str, str]:
    """Map labels to keys and fail when normalization creates a collision."""
    mapped: dict[str, str] = {}
    for label in labels:
        key = normalize_disease_key(label)
        if not key:
            raise ValueError(f"Disease label produces an empty key: {label!r}")
        if key in mapped and mapped[key] != label:
            raise ValueError(
                f"Duplicate normalized disease key {key!r}: "
                f"{mapped[key]!r} and {label!r}"
            )
        mapped[key] = label
    return mapped


def _is_http_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def validate_disease_record(record: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Return critical errors and non-blocking warnings for one seed record."""
    errors: list[str] = []
    warnings: list[str] = []
    key = str(record.get("diseaseKey", ""))
    if not key or normalize_disease_key(key) != key or "/" in key:
        errors.append("diseaseKey is blank or not Firestore-safe")
    for field_name in ("name", "modelLabel", "category", "selfCareLevel"):
        if not str(record.get(field_name, "")).strip():
            errors.append(f"{field_name} is required")
    if record.get("selfCareLevel") not in SELF_CARE_LEVELS:
        errors.append("selfCareLevel is unsupported")
    review = record.get("clinicalReview")
    if not isinstance(review, dict):
        errors.append("clinicalReview must be an object")
    elif review.get("status") not in REVIEW_STATUSES:
        errors.append("clinicalReview.status is unsupported")
    if not str(record.get("contentVersion", "")).strip():
        errors.append("contentVersion is required")

    care_fields = ("whenToSeeDoctor", "emergencyWarningSigns")
    if not any(record.get(field_name) for field_name in care_fields):
        errors.append("at least one warning or medical-care field is required")
    string_arrays = (
        "aliases",
        "commonSymptoms",
        "datasetSymptoms",
        "selfCareGuidance",
        "avoidOrCaution",
        "prevention",
        "riskFactors",
        "possibleComplications",
        "whenToSeeDoctor",
        "emergencyWarningSigns",
        "recommendedSpecialist",
        "icd10Codes",
    )
    for field_name in string_arrays:
        value = record.get(field_name)
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in value
        ):
            errors.append(f"{field_name} must be an array of strings")

    references = record.get("references")
    if not isinstance(references, list) or not references:
        warnings.append("at least one reference is recommended")
    else:
        for index, reference in enumerate(references):
            if not isinstance(reference, dict):
                errors.append(f"references[{index}] must be an object")
                continue
            if not str(reference.get("organization", "")).strip():
                errors.append(f"references[{index}].organization is required")
            url = str(reference.get("url", "")).strip()
            if url and not _is_http_url(url):
                errors.append(f"references[{index}].url must use HTTP or HTTPS")
    if not record.get("icd10Codes"):
        warnings.append("ICD-10 codes unavailable; clinical mapping required")
    if key in SERIOUS_DISEASE_KEYS and record.get("selfCareLevel") != (
        "emergency_evaluation"
    ):
        errors.append("serious disease must use emergency_evaluation")
    serialized = json.dumps(record, ensure_ascii=False).lower()
    for phrase in PROHIBITED_MEDICAL_PHRASES:
        if phrase in serialized:
            errors.append(f"prohibited medical claim detected: {phrase!r}")
    return errors, warnings
