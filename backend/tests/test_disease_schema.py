"""Disease document normalization and schema tests."""

from __future__ import annotations

import pytest

from disease_schema import (
    ClinicalReview,
    DiseaseRecord,
    DiseaseReference,
    ensure_unique_disease_keys,
    normalize_disease_key,
    validate_disease_record,
)


@pytest.mark.parametrize(
    ("label", "expected"),
    [
        ("Acute Kidney Injury", "acute_kidney_injury"),
        ("Benign Prostatic Hyperplasia (BPH)", "benign_prostatic_hyperplasia_bph"),
        (
            "Chronic Obstructive Pulmonary Disease (COPD)",
            "chronic_obstructive_pulmonary_disease_copd",
        ),
        ("  COVID__19  ", "covid_19"),
    ],
)
def test_normalize_disease_key(label: str, expected: str) -> None:
    assert normalize_disease_key(label) == expected


def test_duplicate_document_id_detection() -> None:
    with pytest.raises(ValueError, match="Duplicate normalized disease key"):
        ensure_unique_disease_keys(["heart-attack", "heart attack"])


def test_schema_and_firestore_serialization() -> None:
    record = DiseaseRecord(
        disease_key="influenza",
        name="Influenza",
        model_label="influenza",
        category="Communicable Disease",
        self_care_level="supportive",
        when_to_see_doctor=["Seek medical review if symptoms worsen."],
        references=[DiseaseReference(organization="MedlinePlus")],
        clinical_review=ClinicalReview(status="needs_review"),
    ).to_dict()
    errors, _ = validate_disease_record(record)
    assert errors == []
    assert record["createdAt"] == "__SERVER_TIMESTAMP__"
    assert "reviewedAt" not in record["clinicalReview"]


def test_serious_condition_cannot_be_supportive_only() -> None:
    record = DiseaseRecord(
        disease_key="heart_attack",
        name="Heart Attack",
        model_label="heart attack",
        category="Cardiovascular",
        self_care_level="supportive",
        emergency_warning_signs=["Call emergency services."],
        references=[DiseaseReference(organization="MedlinePlus")],
    ).to_dict()
    errors, _ = validate_disease_record(record)
    assert "serious disease must use emergency_evaluation" in errors


def test_prohibited_medical_claim_is_rejected() -> None:
    record = DiseaseRecord(
        disease_key="influenza",
        name="Influenza",
        model_label="influenza",
        category="Communicable Disease",
        description="This is a guaranteed cure.",
        self_care_level="supportive",
        when_to_see_doctor=["Seek medical advice if symptoms worsen."],
        references=[DiseaseReference(organization="MedlinePlus")],
    ).to_dict()
    errors, _ = validate_disease_record(record)
    assert any("prohibited medical claim" in error for error in errors)
