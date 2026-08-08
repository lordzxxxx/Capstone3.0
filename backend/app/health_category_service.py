"""Deterministic health-category suggestions without a trained dataset.

Explicit conditions provide the strongest mapping. Recognized symptom
keywords provide conservative administrative routing and never represent a
diagnosis; symptom-based results remain marked for clinical review.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any

RULE_VERSION = "condition-category-rules-v2"
NEEDS_REVIEW = "Needs Clinical Review"


def _normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.casefold()).strip()


COMMUNICABLE_CONDITIONS = {
    _normalize(value)
    for value in (
        "influenza",
        "common cold",
        "covid-19",
        "tuberculosis",
        "dengue fever",
        "malaria",
        "measles",
        "chickenpox",
        "cholera",
        "typhoid fever",
        "pertussis",
        "diphtheria",
        "hepatitis a",
        "hepatitis b",
        "hepatitis c",
        "hiv infection",
        "hand foot and mouth disease",
    )
}

NON_COMMUNICABLE_CONDITIONS = {
    _normalize(value)
    for value in (
        "hypertension",
        "type 1 diabetes",
        "type 2 diabetes",
        "diabetes mellitus",
        "asthma",
        "chronic obstructive pulmonary disease",
        "coronary artery disease",
        "heart failure",
        "stroke",
        "chronic kidney disease",
        "arthritis",
        "osteoarthritis",
        "migraine",
        "anxiety",
        "depression",
        "spinal stenosis",
    )
}

COMMUNICABLE_SYMPTOMS = {
    _normalize(value)
    for value in (
        "fever",
        "cough",
        "sore throat",
        "runny nose",
        "nasal congestion",
        "chills",
        "diarrhea",
        "skin rash",
        "loss of smell",
        "loss of taste",
    )
}

NON_COMMUNICABLE_SYMPTOMS = {
    _normalize(value)
    for value in (
        "high blood pressure",
        "elevated blood pressure",
        "chronic joint pain",
        "chronic back pain",
        "frequent urination",
        "excessive thirst",
        "persistent migraine",
    )
}


def suggest_health_category(
    recognized_conditions: Iterable[str],
    recognized_symptoms: Iterable[str] = (),
) -> dict[str, Any]:
    """Return a conservative category suggestion and an auditable basis."""
    conditions = [value.strip() for value in recognized_conditions if value.strip()]
    symptoms = [value.strip() for value in recognized_symptoms if value.strip()]
    communicable: list[str] = []
    non_communicable: list[str] = []
    unmapped: list[str] = []
    communicable_symptoms: list[str] = []
    non_communicable_symptoms: list[str] = []
    unmapped_symptoms: list[str] = []

    for condition in conditions:
        key = _normalize(condition)
        if key in COMMUNICABLE_CONDITIONS:
            communicable.append(condition)
        elif key in NON_COMMUNICABLE_CONDITIONS:
            non_communicable.append(condition)
        else:
            unmapped.append(condition)

    for symptom in symptoms:
        key = _normalize(symptom)
        if key in COMMUNICABLE_SYMPTOMS:
            communicable_symptoms.append(symptom)
        elif key in NON_COMMUNICABLE_SYMPTOMS:
            non_communicable_symptoms.append(symptom)
        else:
            unmapped_symptoms.append(symptom)

    if unmapped:
        category = NEEDS_REVIEW
        basis = "unmapped_explicit_condition"
    elif communicable and non_communicable:
        category = "Mixed"
        basis = "mixed_explicit_conditions"
    elif communicable:
        category = "Communicable"
        basis = "explicit_condition_mapping"
    elif non_communicable:
        category = "Non-Communicable"
        basis = "explicit_condition_mapping"
    elif communicable_symptoms and non_communicable_symptoms:
        category = "Mixed"
        basis = "mixed_symptom_keyword_mapping"
    elif communicable_symptoms:
        category = "Communicable"
        basis = "symptom_keyword_mapping"
    elif non_communicable_symptoms:
        category = "Non-Communicable"
        basis = "symptom_keyword_mapping"
    else:
        category = NEEDS_REVIEW
        basis = "symptom_only" if symptoms else "no_classifiable_input"

    return {
        "suggestedHealthCategory": category,
        "categoryBasis": basis,
        "categoryRequiresReview": basis != "explicit_condition_mapping",
        "categoryRuleVersion": RULE_VERSION,
        "categoryMatchedConditions": communicable + non_communicable,
        "categoryUnmappedConditions": unmapped,
        "categoryMatchedSymptoms": (
            communicable_symptoms + non_communicable_symptoms
        ),
        "categoryUnmappedSymptoms": unmapped_symptoms,
    }
