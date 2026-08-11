"""Public API surface tests after disabling legacy disease prediction."""

from fastapi.testclient import TestClient

import api


def test_root_reports_service_status() -> None:
    response = TestClient(api.app).get("/")
    assert response.status_code == 200
    assert response.json()["status"] in {"running", "degraded"}


def test_symptom_catalog_returns_valid_unique_features() -> None:
    response = TestClient(api.app).get("/symptoms")
    assert response.status_code == 200
    payload = response.json()
    assert payload["total"] == 228
    assert len(payload["symptoms"]) == 228
    assert len(set(payload["symptoms"])) == 228
    assert "fever" in payload["symptoms"]


def test_legacy_prediction_endpoint_is_not_registered() -> None:
    response = TestClient(api.app).post(
        "/predict", json={"symptoms": ["fever"]}
    )
    assert response.status_code == 404
    assert "/predict" not in api.app.openapi()["paths"]


def teardown_module() -> None:
    api.app.dependency_overrides.clear()
