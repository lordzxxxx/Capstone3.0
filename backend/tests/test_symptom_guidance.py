"""Recognition-only API and Firestore symptom-guidance aggregation tests."""

from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient

import api
from symptom_guidance_service import SymptomGuidanceService, normalize_symptom_key


class FakeSnapshot:
    def __init__(self, data: dict[str, Any] | None) -> None:
        self.exists = data is not None
        self._data = data

    def to_dict(self) -> dict[str, Any] | None:
        return self._data


class FakeDocument:
    def __init__(self, data: dict[str, Any] | None) -> None:
        self._data = data

    def get(self, **_: object) -> FakeSnapshot:
        return FakeSnapshot(self._data)


class FakeCollection:
    def __init__(self, documents: dict[str, dict[str, Any]]) -> None:
        self._documents = documents

    def document(self, key: str) -> FakeDocument:
        return FakeDocument(self._documents.get(key))


class FakeDb:
    def __init__(self, documents: dict[str, dict[str, Any]]) -> None:
        self._documents = documents

    def collection(self, name: str) -> FakeCollection:
        assert name == "symptom_guidance"
        return FakeCollection(self._documents)


class FakeDiseaseService:
    def __init__(self, documents: dict[str, dict[str, Any]] | None = None) -> None:
        self.documents = documents or {}

    def get_disease_content_for_prediction(
        self, condition: str
    ) -> dict[str, Any] | None:
        return self.documents.get(condition)


def _document(**overrides: Any) -> dict[str, Any]:
    return {
        "isActive": True,
        "homeCare": [],
        "precautions": [],
        "whenToSeekCare": [],
        "emergencyWarningSigns": [],
        "references": [],
        **overrides,
    }


def test_normalize_symptom_key() -> None:
    assert normalize_symptom_key("Shortness Of Breath") == "shortness_of_breath"


def test_guidance_aggregation_merges_and_deduplicates() -> None:
    service = SymptomGuidanceService(
        db=FakeDb(
            {
                "_default": _document(
                    homeCare=["Rest"], emergencyWarningSigns=["Trouble breathing"]
                ),
                "fever": _document(
                    homeCare=["Rest", "Drink fluids"],
                    whenToSeekCare=["Persistent fever"],
                ),
                "cough": _document(precautions=["Avoid smoke"]),
            }
        )
    )
    result = service.get_for_symptoms(["fever", "cough", "headache"])
    assert result["homeCare"] == ["Rest", "Drink fluids"]
    assert result["precautions"] == ["Avoid smoke"]
    assert result["matchedGuidanceSymptoms"] == ["fever", "cough"]
    assert result["missingGuidanceSymptoms"] == ["headache"]
    assert result["contentAvailable"] is True


def test_guidance_endpoint_returns_no_disease_prediction_fields() -> None:
    service = SymptomGuidanceService(
        db=FakeDb(
            {
                "_default": _document(homeCare=["Rest and monitor symptoms"]),
                "fever": _document(
                    homeCare=["Drink fluids"],
                    emergencyWarningSigns=["Fever with a seizure"],
                ),
                "cough": _document(precautions=["Avoid smoke"]),
            }
        )
    )
    api.app.dependency_overrides[api.get_symptom_guidance_service] = lambda: service
    api.app.dependency_overrides[api.get_disease_service] = lambda: (
        FakeDiseaseService()
    )
    client = TestClient(api.app)
    response = client.post("/guidance", json={"symptoms": ["fever", "cough"]})
    assert response.status_code == 200
    payload = response.json()
    assert payload["recognizedSymptoms"] == ["fever", "cough"]
    assert payload["contentAvailable"] is True
    assert payload["homeCare"] == ["Rest and monitor symptoms", "Drink fluids"]
    assert "prediction" not in payload
    assert "topPredictions" not in payload
    assert "confidence" not in payload
    assert payload["suggestedHealthCategory"] == "Communicable"
    assert payload["categoryBasis"] == "symptom_keyword_mapping"
    assert payload["categoryRequiresReview"] is True


def test_guidance_endpoint_accepts_explicit_disease_without_predicting() -> None:
    api.app.dependency_overrides[api.get_symptom_guidance_service] = lambda: (
        SymptomGuidanceService(db=FakeDb({}))
    )
    api.app.dependency_overrides[api.get_disease_service] = lambda: (
        FakeDiseaseService(
            {
                "urinary tract infection": {
                    "selfCareGuidance": ["Rest and maintain hydration"],
                    "avoidOrCaution": ["Do not use leftover antibiotics"],
                    "whenToSeeDoctor": ["Seek prompt clinical advice"],
                    "emergencyWarningSigns": ["Confusion or marked drowsiness"],
                    "references": [],
                }
            }
        )
    )
    client = TestClient(api.app)
    response = client.post("/guidance", json={"symptoms": ["UTI"]})
    assert response.status_code == 200
    payload = response.json()
    assert payload["recognizedSymptoms"] == []
    assert payload["recognizedConditions"] == ["urinary tract infection"]
    assert payload["matchedGuidanceConditions"] == ["urinary tract infection"]
    assert payload["ignoredSymptoms"] == []
    assert "prediction" not in payload
    assert payload["homeCare"] == ["Rest and maintain hydration"]
    assert payload["precautions"] == []
    assert payload["suggestedHealthCategory"] == "Needs Clinical Review"
    assert payload["categoryBasis"] == "unmapped_explicit_condition"


def test_guidance_filters_medication_wording_but_preserves_emergency_warnings() -> None:
    service = SymptomGuidanceService(
        db=FakeDb(
            {
                "_default": _document(
                    homeCare=[
                        "Rest and monitor symptoms.",
                        "Take antibiotics for three days.",
                    ],
                    precautions=["Ask about medication safety."],
                    emergencyWarningSigns=["Difficulty breathing requires urgent care."],
                ),
                "fever": _document(
                    emergencyWarningSigns=["Fever with confusion or seizure."],
                ),
            }
        )
    )
    api.app.dependency_overrides[api.get_symptom_guidance_service] = lambda: service
    api.app.dependency_overrides[api.get_disease_service] = lambda: (
        FakeDiseaseService()
    )

    response = TestClient(api.app).post(
        "/guidance", json={"symptoms": ["fever"]}
    )

    assert response.status_code == 200
    payload = response.json()
    returned_text = " ".join(
        item
        for field in (
            "homeCare",
            "precautions",
            "whenToSeekCare",
            "emergencyWarningSigns",
        )
        for item in payload[field]
    ).casefold()
    assert "antibiotic" not in returned_text
    assert "medication" not in returned_text
    assert "difficulty breathing" in returned_text
    assert "confusion or seizure" in returned_text


def test_guidance_rejects_unknown_input_without_fabricating_content() -> None:
    response = TestClient(api.app).post(
        "/guidance", json={"symptoms": ["made-up symptom"]}
    )

    assert response.status_code == 422
    payload = response.json()
    assert payload["recognizedSymptoms"] == []
    assert payload["recognizedConditions"] == []
    assert payload["ignoredSymptoms"] == ["made-up symptom"]


def test_local_flutter_web_origin_is_allowed_by_cors() -> None:
    client = TestClient(api.app)
    response = client.options(
        "/guidance",
        headers={
            "Origin": "http://localhost:54321",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == (
        "http://localhost:54321"
    )


def test_oversized_request_body_is_rejected() -> None:
    client = TestClient(api.app)
    response = client.post(
        "/guidance",
        content=("x" * (64 * 1024 + 1)).encode(),
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 413


def test_overlong_symptom_value_is_rejected() -> None:
    client = TestClient(api.app)
    response = client.post("/guidance", json={"symptoms": ["x" * 129]})
    assert response.status_code == 422


def teardown_module() -> None:
    api.app.dependency_overrides.clear()
