"""Cached model loading, ordered vectorization, and Top-3 inference tests."""

from __future__ import annotations

import csv
from pathlib import Path

import pytest

from predict import (
    ArtifactLoadError,
    NoRecognizedSymptomsError,
    build_feature_vector,
    get_valid_symptoms,
    load_artifacts,
    load_symptom_aliases,
    normalize_symptom,
    predict_top_diseases,
    recognize_diseases,
    validate_symptom_aliases,
)


def test_production_model_and_features_load_once() -> None:
    first_model, first_features = load_artifacts()
    second_model, second_features = load_artifacts()
    assert first_model is second_model
    assert first_features is second_features
    assert len(first_features) == 228
    assert int(first_model.n_features_in_) == len(first_features)
    assert len(first_features) == len(set(first_features))
    assert all(feature.strip() for feature in first_features)


def test_feature_columns_match_processed_training_dataset() -> None:
    training_path = (
        Path(__file__).resolve().parents[1]
        / "dataset"
        / "processed"
        / "merged_dataset.csv"
    )
    with training_path.open(encoding="utf-8-sig", newline="") as source:
        header = next(csv.reader(source))
    training_features = [column for column in header if column != "diseases"]
    assert training_features == get_valid_symptoms()


def test_missing_model_returns_clear_configuration_error(tmp_path: Path) -> None:
    with pytest.raises(ArtifactLoadError, match="Model file not found"):
        load_artifacts(
            model_path=tmp_path / "missing.pkl",
            feature_columns_path=tmp_path / "missing-features.json",
        )


def test_feature_vector_preserves_order_and_ignores_unknowns() -> None:
    frame, recognized, ignored = build_feature_vector(
        ["cough", "not-a-feature", "fever", "cough"],
        ["fever", "headache", "cough"],
    )
    assert list(frame.columns) == ["fever", "headache", "cough"]
    assert frame.iloc[0].tolist() == [1, 0, 1]
    assert recognized == ["cough", "fever"]
    assert ignored == ["not-a-feature"]


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (" Fever ", "fever"),
        ("Shortness_Of_Breath", "shortness of breath"),
        ("SHORTNESS OF BREATH", "shortness of breath"),
        ("head--ache", "head ache"),
        ("  repeated   spaces  ", "repeated spaces"),
    ],
)
def test_normalize_symptom(raw: str, expected: str) -> None:
    assert normalize_symptom(raw) == expected


@pytest.mark.parametrize(
    ("alias", "canonical"),
    [
        ("difficulty breathing", "shortness of breath"),
        ("runny nose", "nasal congestion"),
        ("high fever", "fever"),
        ("head ache", "headache"),
    ],
)
def test_aliases_match_existing_features(alias: str, canonical: str) -> None:
    features = get_valid_symptoms()
    aliases = load_symptom_aliases()
    frame, recognized, ignored = build_feature_vector(
        [alias], features, aliases=aliases
    )
    assert recognized == [canonical]
    assert ignored == []
    assert int(frame.to_numpy().sum()) == 1


def test_all_alias_targets_are_valid_model_features() -> None:
    validate_symptom_aliases(load_symptom_aliases(), get_valid_symptoms())


@pytest.mark.parametrize(
    "symptom",
    ["fever", "cough", "headache", "shortness of breath"],
)
def test_required_canonical_symptoms_are_recognized(symptom: str) -> None:
    result = predict_top_diseases([symptom])
    assert result["recognizedSymptoms"] == [symptom]
    assert result["ignoredSymptoms"] == []


@pytest.mark.parametrize(
    "symptoms",
    [
        ["unknown symptom"],
        ["urinary tract infection"],
        ["UTI"],
    ],
)
def test_prediction_rejects_zero_recognized_symptoms(symptoms: list[str]) -> None:
    with pytest.raises(NoRecognizedSymptomsError) as exc_info:
        predict_top_diseases(symptoms)
    assert exc_info.value.recognized_symptoms == []
    assert exc_info.value.ignored_symptoms == symptoms


@pytest.mark.parametrize(
    ("entered", "expected"),
    [
        ("UTI", "urinary tract infection"),
        ("BPH", "benign prostatic hyperplasia (bph)"),
        ("COPD", "chronic obstructive pulmonary disease (copd)"),
        ("pneumonia", "pneumonia"),
    ],
)
def test_explicit_disease_names_and_aliases_are_recognized(
    entered: str, expected: str
) -> None:
    result = recognize_diseases([entered])
    assert result["recognizedConditions"] == [expected]
    assert result["ignoredKeywords"] == []


def test_prediction_returns_sorted_top_three_and_unknown_symptoms() -> None:
    result = predict_top_diseases(
        ["fever", "cough", "unknown symptom"], top_k=3
    )
    predictions = result["topPredictions"]
    assert len(predictions) == 3
    assert [item["rank"] for item in predictions] == [1, 2, 3]
    assert predictions[0]["confidence"] >= predictions[1]["confidence"]
    assert predictions[1]["confidence"] >= predictions[2]["confidence"]
    assert result["ignoredSymptoms"] == ["unknown symptom"]
