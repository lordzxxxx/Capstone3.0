"""Integrity checks for the small manually labeled AI safety set."""

from __future__ import annotations

import json
from pathlib import Path


VALIDATION_PATH = (
    Path(__file__).resolve().parents[1] / "validation" / "ai_manual_validation.json"
)
EXPECTED_CATEGORIES = {
    "Communicable",
    "Non-Communicable",
    "Emergency",
    "Prenatal Care",
    "Needs Clinical Review",
}


def test_manual_validation_set_has_required_safety_coverage() -> None:
    payload = json.loads(VALIDATION_PATH.read_text(encoding="utf-8"))
    cases = payload["cases"]

    assert payload["schemaVersion"] == 1
    assert payload["reviewStatus"] == "pending_qualified_health_professional_review"
    assert len(cases) >= 10
    assert len({case["id"] for case in cases}) == len(cases)
    assert {case["expectedCategory"] for case in cases} == EXPECTED_CATEGORIES
    assert any(case["emergencyWarningExpected"] for case in cases)
    assert any(case["medicationPrompt"] for case in cases)
    assert any(case["unknownInput"] for case in cases)
    assert all(case["reference"].strip() for case in cases)
