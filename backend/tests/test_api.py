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


def test_symptom_catalog_failure_returns_safe_service_unavailable(monkeypatch) -> None:
    def unavailable_catalog():
        raise api.ArtifactLoadError("model artifact details must not reach clients")

    monkeypatch.setattr(api, "get_valid_symptoms", unavailable_catalog)
    response = TestClient(api.app).get("/symptoms")

    assert response.status_code == 503
    assert response.json() == {"detail": "Symptom vocabulary is unavailable."}


def test_legacy_prediction_endpoint_is_not_registered() -> None:
    response = TestClient(api.app).post(
        "/predict", json={"symptoms": ["fever"]}
    )
    assert response.status_code == 404
    assert "/predict" not in api.app.openapi()["paths"]


def test_production_api_does_not_expose_interactive_docs(
    monkeypatch,
) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("WEB_ALLOWED_ORIGINS", "https://www.ai-dsuhis.com")
    monkeypatch.setenv("API_ALLOWED_HOSTS", "api.ai-dsuhis.com")
    api.get_settings.cache_clear()
    try:
        production_app = api.create_app()
        paths = {route.path for route in production_app.routes}
        assert "/docs" not in paths
        assert "/redoc" not in paths
        assert "/openapi.json" not in paths
    finally:
        api.get_settings.cache_clear()


def teardown_module() -> None:
    api.app.dependency_overrides.clear()
