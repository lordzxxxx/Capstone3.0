"""Cached Random Forest inference and exact binary feature-vector construction."""

from __future__ import annotations

import json
import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd

try:
    from .config import get_settings
    from .verified_artifact import ArtifactVerificationError, load_verified_joblib
except ImportError:  # Direct execution support.
    from config import get_settings
    from verified_artifact import ArtifactVerificationError, load_verified_joblib


class ArtifactLoadError(RuntimeError):
    """Raised when model inference artifacts are missing or incompatible."""


class NoRecognizedSymptomsError(ValueError):
    """Raised before inference when no submitted symptom matches the model."""

    def __init__(
        self,
        ignored_symptoms: list[str],
        normalized_symptoms: list[str] | None = None,
    ) -> None:
        super().__init__("No valid symptoms were recognized.")
        self.recognized_symptoms: list[str] = []
        self.ignored_symptoms = ignored_symptoms
        self.normalized_symptoms = normalized_symptoms or []


LOGGER = logging.getLogger("ai_dsuhis.api")
DEFAULT_ALIASES_PATH = (
    Path(__file__).resolve().parents[1] / "models" / "symptom_aliases.json"
)
DEFAULT_DISEASE_ALIASES_PATH = (
    Path(__file__).resolve().parents[1] / "models" / "disease_aliases.json"
)
DEFAULT_TRAINING_METRICS_PATH = (
    Path(__file__).resolve().parents[1] / "models" / "training_metrics.json"
)


def normalize_symptom(value: object) -> str:
    """Normalize user-entered symptoms for feature-name matching."""
    normalized = str(value).strip().lower().replace("_", " ").replace("-", " ")
    return re.sub(r"\s+", " ", normalized)


def normalize_symptom_name(value: object) -> str:
    """Backward-compatible alias for callers using the previous helper name."""
    return normalize_symptom(value)


@lru_cache(maxsize=4)
def _load_symptom_aliases_cached(alias_path_text: str) -> dict[str, str]:
    alias_path = Path(alias_path_text)
    if not alias_path.is_file():
        raise ArtifactLoadError(f"Symptom-alias file not found: {alias_path}")
    try:
        payload = json.loads(alias_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactLoadError(f"Could not load symptom aliases: {exc}") from exc
    if not isinstance(payload, dict):
        raise ArtifactLoadError("Symptom aliases JSON must contain an object")
    aliases: dict[str, str] = {}
    for raw_alias, raw_target in payload.items():
        alias = normalize_symptom(raw_alias)
        target = normalize_symptom(raw_target)
        if not alias or not target:
            raise ArtifactLoadError("Symptom aliases cannot be blank")
        if alias in aliases and aliases[alias] != target:
            raise ArtifactLoadError(f"Conflicting symptom alias: {raw_alias!r}")
        aliases[alias] = target
    return aliases


def load_symptom_aliases(alias_path: Path | None = None) -> dict[str, str]:
    """Load normalized symptom aliases once from the model metadata directory."""
    resolved_path = (alias_path or DEFAULT_ALIASES_PATH).resolve()
    return dict(_load_symptom_aliases_cached(str(resolved_path)))


@lru_cache(maxsize=4)
def _load_disease_aliases_cached(alias_path_text: str) -> dict[str, str]:
    alias_path = Path(alias_path_text)
    try:
        payload = json.loads(alias_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactLoadError(f"Could not load disease aliases: {exc}") from exc
    if not isinstance(payload, dict):
        raise ArtifactLoadError("Disease aliases JSON must contain an object")
    return {
        normalize_symptom(alias): normalize_symptom(target)
        for alias, target in payload.items()
        if normalize_symptom(alias) and normalize_symptom(target)
    }


def load_disease_aliases(alias_path: Path | None = None) -> dict[str, str]:
    resolved_path = (alias_path or DEFAULT_DISEASE_ALIASES_PATH).resolve()
    return dict(_load_disease_aliases_cached(str(resolved_path)))


def _validated_feature_lookup(features: Iterable[str]) -> dict[str, str]:
    """Validate canonical features and return normalized-to-original names."""
    lookup: dict[str, str] = {}
    for feature in features:
        if not isinstance(feature, str) or not feature.strip():
            raise ArtifactLoadError("Feature columns cannot contain blank names")
        normalized = normalize_symptom(feature)
        if normalized in lookup:
            raise ArtifactLoadError(
                "Duplicate feature after normalization: "
                f"{lookup[normalized]!r} and {feature!r}"
            )
        lookup[normalized] = feature
    return lookup


def validate_symptom_aliases(
    aliases: dict[str, str], feature_columns: Iterable[str]
) -> None:
    """Fail fast when an alias points outside the trained feature vocabulary."""
    lookup = _validated_feature_lookup(feature_columns)
    invalid = sorted(
        f"{alias} -> {target}" for alias, target in aliases.items() if target not in lookup
    )
    if invalid:
        raise ArtifactLoadError(
            "Symptom aliases target unknown features: " + ", ".join(invalid)
        )


@lru_cache(maxsize=4)
def _load_feature_columns_cached(feature_columns_path_text: str) -> tuple[str, ...]:
    """Load the recognition vocabulary without deserializing the model.

    Symptom recognition is part of the supported guidance API, while the
    Random Forest is an offline evaluation artifact. Keeping these concerns
    separate prevents a missing optional pickle from taking `/symptoms` and
    `/guidance` offline.
    """
    feature_path = Path(feature_columns_path_text)
    if not feature_path.is_file():
        raise ArtifactLoadError(f"Feature-columns file not found: {feature_path}")
    try:
        payload = json.loads(feature_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactLoadError(f"Could not load feature columns: {exc}") from exc
    if isinstance(payload, dict):
        payload = payload.get("featureColumns") or payload.get("features")
    if not isinstance(payload, list) or not all(
        isinstance(feature, str) and feature for feature in payload
    ):
        raise ArtifactLoadError("Feature-columns JSON must contain a string array")
    features = tuple(payload)
    _validated_feature_lookup(features)
    validate_symptom_aliases(load_symptom_aliases(), features)
    return features


def load_feature_columns(
    feature_columns_path: Path | None = None,
) -> tuple[str, ...]:
    """Return the validated ordered symptom vocabulary from JSON metadata."""
    settings = get_settings()
    resolved_path = (feature_columns_path or settings.feature_columns_path).resolve()
    return _load_feature_columns_cached(str(resolved_path))


@lru_cache(maxsize=4)
def _load_disease_labels_cached(metrics_path_text: str) -> tuple[str, ...]:
    """Load ordered condition labels from reproducible training metadata."""
    metrics_path = Path(metrics_path_text)
    if not metrics_path.is_file():
        raise ArtifactLoadError(f"Training metrics file not found: {metrics_path}")
    try:
        payload = json.loads(metrics_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactLoadError(f"Could not load training metrics: {exc}") from exc
    distribution = payload.get("class_distribution")
    if not isinstance(distribution, dict) or not distribution:
        raise ArtifactLoadError(
            "Training metrics must contain a non-empty class_distribution object"
        )
    labels = tuple(str(label) for label in distribution)
    lookup = _validated_feature_lookup(labels)
    aliases = load_disease_aliases()
    invalid_targets = sorted(
        target for target in aliases.values() if target not in lookup
    )
    if invalid_targets:
        raise ArtifactLoadError(
            "Disease aliases target unknown labels: " + ", ".join(invalid_targets)
        )
    return labels


def load_disease_labels(metrics_path: Path | None = None) -> tuple[str, ...]:
    """Return condition labels without loading the inference artifact."""
    resolved_path = (metrics_path or DEFAULT_TRAINING_METRICS_PATH).resolve()
    return _load_disease_labels_cached(str(resolved_path))


@lru_cache(maxsize=4)
def _load_artifacts_cached(
    model_path_text: str,
    feature_columns_path_text: str,
    expected_sha256: str,
) -> tuple[Any, tuple[str, ...]]:
    model_path = Path(model_path_text)
    feature_path = Path(feature_columns_path_text)
    try:
        model = load_verified_joblib(model_path, expected_sha256)
    except ArtifactVerificationError as exc:
        raise ArtifactLoadError(str(exc)) from exc
    features = _load_feature_columns_cached(str(feature_path))
    expected_count = getattr(model, "n_features_in_", len(features))
    if int(expected_count) != len(features):
        raise ArtifactLoadError(
            f"Model expects {expected_count} features but metadata contains "
            f"{len(features)}"
        )
    if not hasattr(model, "predict_proba") or not hasattr(model, "classes_"):
        raise ArtifactLoadError("Model must expose predict_proba() and classes_")
    return model, features


def load_artifacts(
    model_path: Path | None = None,
    feature_columns_path: Path | None = None,
    expected_sha256: str | None = None,
) -> tuple[Any, tuple[str, ...]]:
    """Load model/metadata once per resolved path pair."""
    settings = get_settings()
    resolved_model = (model_path or settings.model_path).resolve()
    resolved_features = (
        feature_columns_path or settings.feature_columns_path
    ).resolve()
    approved_sha256 = expected_sha256 or settings.model_expected_sha256
    return _load_artifacts_cached(
        str(resolved_model),
        str(resolved_features),
        approved_sha256,
    )


def clear_artifact_cache() -> None:
    """Clear cached artifacts for isolated tests or controlled deployments."""
    _load_artifacts_cached.cache_clear()
    _load_feature_columns_cached.cache_clear()
    _load_disease_labels_cached.cache_clear()
    _load_symptom_aliases_cached.cache_clear()
    _load_disease_aliases_cached.cache_clear()


def get_valid_symptoms() -> list[str]:
    """Return the ordered symptom vocabulary used by recognition/inference."""
    return list(load_feature_columns())


def get_valid_diseases() -> list[str]:
    """Return disease labels from metadata without running inference."""
    return list(load_disease_labels())


def recognize_diseases(values: Iterable[str]) -> dict[str, list[str]]:
    """Match explicitly entered condition names; never infer a condition."""
    diseases = get_valid_diseases()
    lookup = {normalize_symptom(disease): disease for disease in diseases}
    aliases = load_disease_aliases()
    invalid_targets = sorted(target for target in aliases.values() if target not in lookup)
    if invalid_targets:
        raise ArtifactLoadError(
            "Disease aliases target unknown labels: " + ", ".join(invalid_targets)
        )
    recognized: list[str] = []
    ignored: list[str] = []
    for value in values:
        raw = str(value).strip()
        normalized = normalize_symptom(raw)
        normalized = aliases.get(normalized, normalized)
        canonical = lookup.get(normalized)
        if canonical is None:
            if raw and raw not in ignored:
                ignored.append(raw)
        elif canonical not in recognized:
            recognized.append(canonical)
    return {"recognizedConditions": recognized, "ignoredKeywords": ignored}


def build_feature_vector(
    symptoms: Iterable[str],
    feature_columns: Iterable[str],
    aliases: dict[str, str] | None = None,
) -> tuple[pd.DataFrame, list[str], list[str]]:
    """Build one ordered binary row and report recognized/ignored symptoms."""
    features = tuple(feature_columns)
    lookup = _validated_feature_lookup(features)
    selected_aliases = aliases if aliases is not None else {}
    if aliases is not None:
        validate_symptom_aliases(selected_aliases, features)

    row = {feature: 0 for feature in features}
    recognized: list[str] = []
    ignored: list[str] = []
    for symptom in symptoms:
        normalized = normalize_symptom(symptom)
        normalized = selected_aliases.get(normalized, normalized)
        canonical = lookup.get(normalized)
        if canonical is None:
            if str(symptom).strip() and str(symptom).strip() not in ignored:
                ignored.append(str(symptom).strip())
            continue
        row[canonical] = 1
        if canonical not in recognized:
            recognized.append(canonical)
    sample = pd.DataFrame([row], columns=features, dtype="uint8")
    return sample, recognized, ignored


def recognize_symptoms(
    symptoms: Iterable[str], *, reject_if_empty: bool = True
) -> dict[str, Any]:
    """Normalize and match symptoms without running disease inference."""
    features = get_valid_symptoms()
    raw_symptoms = [str(symptom).strip() for symptom in symptoms]
    aliases = load_symptom_aliases()
    normalized_symptoms = [
        aliases.get(normalize_symptom(symptom), normalize_symptom(symptom))
        for symptom in raw_symptoms
    ]
    sample, recognized, ignored = build_feature_vector(
        raw_symptoms, features, aliases=aliases
    )
    feature_vector_count = int(sample.to_numpy().sum())
    LOGGER.debug(
        "Symptoms matched to model vocabulary",
        extra={
            "event": "symptom_matching",
            "incomingSymptoms": raw_symptoms,
            "normalizedSymptoms": normalized_symptoms,
            "recognizedSymptoms": recognized,
            "ignoredSymptoms": ignored,
            "featureVectorCount": feature_vector_count,
        },
    )
    if not recognized and reject_if_empty:
        raise NoRecognizedSymptomsError(ignored, normalized_symptoms)
    return {
        "recognizedSymptoms": recognized,
        "ignoredSymptoms": ignored,
        "normalizedSymptoms": normalized_symptoms,
        "featureVectorCount": feature_vector_count,
    }


def predict_top_diseases(
    symptoms: Iterable[str],
    top_k: int = 3,
) -> dict[str, Any]:
    """Return sorted Top-K disease probabilities and symptom match details."""
    if top_k < 1:
        raise ValueError("top_k must be at least 1")
    model, features = load_artifacts()
    recognition = recognize_symptoms(symptoms)
    aliases = load_symptom_aliases()
    sample, _, _ = build_feature_vector(
        recognition["recognizedSymptoms"], features, aliases=aliases
    )
    recognized = recognition["recognizedSymptoms"]
    ignored = recognition["ignoredSymptoms"]
    probabilities = np.asarray(model.predict_proba(sample)[0], dtype=float)
    classes = np.asarray(model.classes_, dtype=object)
    if probabilities.shape[0] != classes.shape[0]:
        raise ArtifactLoadError("Model probability output does not match its classes")
    indices = np.argsort(probabilities)[::-1][: min(top_k, len(classes))]
    predictions = [
        {
            "disease": str(classes[index]),
            "confidence": round(float(probabilities[index]) * 100.0, 2),
            "rank": rank,
        }
        for rank, index in enumerate(indices, start=1)
    ]
    LOGGER.debug(
        "Model probability ranking completed",
        extra={"event": "model_prediction", "topPredictions": predictions},
    )
    return {
        "topPredictions": predictions,
        "recognizedSymptoms": recognized,
        "ignoredSymptoms": ignored,
        "normalizedSymptoms": recognition["normalizedSymptoms"],
    }


def predict_disease(symptoms: Iterable[str]) -> dict[str, object]:
    """Backward-compatible single-result wrapper using cached Top-3 inference."""
    result = predict_top_diseases(symptoms, top_k=3)
    top_prediction = result["topPredictions"][0]
    return {
        "disease": top_prediction["disease"],
        "confidence": float(top_prediction["confidence"]) / 100.0,
        "recognized_symptoms": result["recognizedSymptoms"],
        "ignored_symptoms": result["ignoredSymptoms"],
        "top_predictions": result["topPredictions"],
    }
