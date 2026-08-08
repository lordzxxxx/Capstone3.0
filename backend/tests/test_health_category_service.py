from backend.app.health_category_service import (
    NEEDS_REVIEW,
    suggest_health_category,
)


def test_communicable_symptom_keywords_receive_a_reviewable_category() -> None:
    result = suggest_health_category([], ["fever", "cough"])
    assert result["suggestedHealthCategory"] == "Communicable"
    assert result["categoryBasis"] == "symptom_keyword_mapping"
    assert result["categoryRequiresReview"] is True
    assert result["categoryMatchedSymptoms"] == ["fever", "cough"]


def test_non_communicable_symptom_keywords_receive_a_reviewable_category() -> None:
    result = suggest_health_category([], ["high blood pressure"])
    assert result["suggestedHealthCategory"] == "Non-Communicable"
    assert result["categoryRequiresReview"] is True


def test_explicit_mapped_conditions_receive_deterministic_suggestions() -> None:
    communicable = suggest_health_category(["tuberculosis"])
    non_communicable = suggest_health_category(["hypertension"])
    assert communicable["suggestedHealthCategory"] == "Communicable"
    assert non_communicable["suggestedHealthCategory"] == "Non-Communicable"
    assert communicable["categoryRequiresReview"] is False


def test_mixed_and_unmapped_conditions_require_review() -> None:
    mixed = suggest_health_category(["influenza", "asthma"])
    unmapped = suggest_health_category(["urinary tract infection"])
    assert mixed["suggestedHealthCategory"] == "Mixed"
    assert unmapped["suggestedHealthCategory"] == NEEDS_REVIEW
    assert unmapped["categoryUnmappedConditions"] == [
        "urinary tract infection"
    ]


def test_unmapped_symptoms_remain_for_clinical_review() -> None:
    result = suggest_health_category([], ["fatigue"])
    assert result["suggestedHealthCategory"] == NEEDS_REVIEW
    assert result["categoryUnmappedSymptoms"] == ["fatigue"]
