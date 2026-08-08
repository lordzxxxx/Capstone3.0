"""Mocked Firestore disease lookup tests."""

from __future__ import annotations

from typing import Any

from disease_service import DiseaseService


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

    def where(self, *_: Any) -> "FakeCollection":
        return self

    def stream(self) -> list[FakeSnapshot]:
        return [
            FakeSnapshot(data)
            for data in self._documents.values()
            if data.get("isActive") is True
        ]


class FakeDb:
    def __init__(self, documents: dict[str, dict[str, Any]]) -> None:
        self._documents = documents

    def collection(self, name: str) -> FakeCollection:
        assert name == "diseases"
        return FakeCollection(self._documents)


def test_content_exists_and_internal_notes_are_hidden() -> None:
    service = DiseaseService(
        db=FakeDb(
            {
                "influenza": {
                    "diseaseKey": "influenza",
                    "isActive": True,
                    "clinicalReview": {
                        "status": "needs_review",
                        "notes": "internal draft note",
                    },
                }
            }
        )
    )
    result = service.get_disease_by_model_label("Influenza")
    assert result is not None
    assert result["clinicalReview"] == {"status": "needs_review"}


def test_missing_content_returns_none() -> None:
    service = DiseaseService(db=FakeDb({}))
    assert service.get_disease_by_key("not present") is None


def test_prediction_uses_only_the_normalized_model_label_document() -> None:
    service = DiseaseService(
        db=FakeDb(
            {
                "urinary_tract_infection": {
                    "diseaseKey": "urinary_tract_infection",
                    "name": "Urinary Tract Infection",
                    "isActive": True,
                },
                "spinal_stenosis": {
                    "diseaseKey": "spinal_stenosis",
                    "name": "Spinal Stenosis",
                    "isActive": True,
                },
            }
        )
    )
    assert (
        service.document_id_for_prediction("Urinary Tract Infection")
        == "urinary_tract_infection"
    )
    result = service.get_disease_content_for_prediction(
        "Urinary Tract Infection"
    )
    assert result is not None
    assert result["diseaseKey"] == "urinary_tract_infection"
