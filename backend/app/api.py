"""Production FastAPI endpoints for disease inference and Firestore enrichment."""

from __future__ import annotations

import json
import logging
import time
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

try:
    from .config import Settings, get_settings
    from .disease_service import DiseaseService
    from .health_category_service import suggest_health_category
    from .predict import (
        ArtifactLoadError,
        NoRecognizedSymptomsError,
        get_valid_symptoms,
        load_artifacts,
        normalize_symptom,
        predict_top_diseases,
        recognize_diseases,
        recognize_symptoms,
    )
    from .symptom_guidance_service import SymptomGuidanceService
    from .security import AuthenticatedUser, require_ai_access
    from .schemas import (
        DiseaseInformation,
        ErrorResponse,
        HealthResponse,
        PredictionRequest,
        PredictionResponse,
        RootStatusResponse,
        SymptomCatalogResponse,
        SymptomGuidanceResponse,
    )
except ImportError:  # Supports ``uvicorn app.api:app`` from backend/.
    from config import Settings, get_settings
    from disease_service import DiseaseService
    from health_category_service import suggest_health_category
    from predict import (
        ArtifactLoadError,
        NoRecognizedSymptomsError,
        get_valid_symptoms,
        load_artifacts,
        normalize_symptom,
        predict_top_diseases,
        recognize_diseases,
        recognize_symptoms,
    )
    from symptom_guidance_service import SymptomGuidanceService
    from security import AuthenticatedUser, require_ai_access
    from schemas import (
        DiseaseInformation,
        ErrorResponse,
        HealthResponse,
        PredictionRequest,
        PredictionResponse,
        RootStatusResponse,
        SymptomCatalogResponse,
        SymptomGuidanceResponse,
    )

DISCLAIMER = (
    "This application provides educational decision support only. It is not a "
    "medical diagnosis. Consult a licensed healthcare professional."
)
LOW_CONFIDENCE_WARNING = "The prediction confidence is low."


class JsonLogFormatter(logging.Formatter):
    """Emit concise structured logs without credentials or stack traces."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key in (
            "event",
            "disease",
            "confidence",
            "latencyMs",
            "unknownSymptoms",
            "firestoreLookupMs",
            "contentAvailable",
            "incomingSymptoms",
            "normalizedSymptoms",
            "recognizedSymptoms",
            "ignoredSymptoms",
            "featureVectorCount",
            "topPredictions",
            "firestoreDocumentId",
            "firestoreLookupFound",
            "totalFeatures",
            "firstFeatures",
        ):
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(settings: Settings | None = None) -> None:
    """Configure the API logger once with JSON output."""
    selected = settings or get_settings()
    logger = logging.getLogger("ai_dsuhis.api")
    logger.setLevel(selected.log_level)
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(JsonLogFormatter())
        logger.addHandler(handler)
    logger.propagate = False


configure_logging()
LOGGER = logging.getLogger("ai_dsuhis.api")


def get_disease_service() -> DiseaseService:
    """FastAPI dependency that shares the cached Firebase client."""
    settings = get_settings()
    return DiseaseService(
        timeout_seconds=settings.firestore_timeout_seconds,
    )


def get_symptom_guidance_service() -> SymptomGuidanceService:
    settings = get_settings()
    return SymptomGuidanceService(
        timeout_seconds=settings.firestore_timeout_seconds,
    )


def model_loaded_successfully() -> bool:
    """Return model readiness without exposing internal loading errors."""
    try:
        load_artifacts()
        return True
    except ArtifactLoadError:
        return False


def _public_disease_information(
    content: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if content is None:
        return None
    return DiseaseInformation.model_validate(content).model_dump()


def build_prediction_response(
    inference: dict[str, Any],
    disease_information: dict[str, Any] | None,
    confidence_threshold: float,
) -> dict[str, Any]:
    """Build the stable Flutter response contract from inference and Firestore."""
    top_predictions = inference["topPredictions"]
    top_prediction = top_predictions[0]
    threshold_met = float(top_prediction["confidence"]) >= (
        confidence_threshold * 100.0
    )
    content = _public_disease_information(disease_information)
    response: dict[str, Any] = {
        "prediction": top_prediction,
        "topPredictions": top_predictions,
        "recognizedSymptoms": inference["recognizedSymptoms"],
        "ignoredSymptoms": inference["ignoredSymptoms"],
        "diseaseInformation": content,
        "contentAvailable": content is not None,
        "confidenceThresholdMet": threshold_met,
        "warning": None if threshold_met else LOW_CONFIDENCE_WARNING,
        "fallbackMessage": None,
        "disclaimer": DISCLAIMER,
    }
    if content is None:
        response["fallbackMessage"] = (
            "Educational information for this predicted condition is currently "
            "unavailable. Consult a licensed healthcare professional."
        )
    return response


def create_app() -> FastAPI:
    """Create the documented API application without loading artifacts twice."""
    application = FastAPI(
        title="AI-DSUHIS Symptom Guidance API",
        version=get_settings().model_version,
        description=(
            "Keyword-based self-care and emergency guidance retrieved from "
            "reviewed Firestore content. This API does not provide a diagnosis."
        ),
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "https://capstone-c98f9.web.app",
            "https://capstone-c98f9.firebaseapp.com",
        ],
        allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=[
            "Content-Type",
            "Accept",
            "Authorization",
            "X-Firebase-AppCheck",
        ],
    )

    @application.get(
        "/",
        response_model=RootStatusResponse,
        summary="API and model status",
    )
    def root() -> RootStatusResponse:
        settings = get_settings()
        loaded = model_loaded_successfully()
        return RootStatusResponse(
            status="running" if loaded else "degraded",
            modelVersion=settings.model_version,
            loadedSuccessfully=loaded,
        )

    @application.get(
        "/health",
        response_model=HealthResponse,
        summary="Health and dependency readiness",
    )
    def health() -> HealthResponse:
        settings = get_settings()
        loaded = model_loaded_successfully()
        return HealthResponse(
            status="healthy" if loaded else "unhealthy",
            modelLoaded=loaded,
            firestoreConfigured=bool(settings.google_application_credentials),
        )

    @application.get(
        "/symptoms",
        response_model=SymptomCatalogResponse,
        summary="List every valid model symptom",
    )
    def symptoms() -> SymptomCatalogResponse:
        valid_symptoms = get_valid_symptoms()
        LOGGER.debug(
            "Validated model symptom catalog loaded",
            extra={
                "event": "symptom_catalog",
                "totalFeatures": len(valid_symptoms),
                "firstFeatures": valid_symptoms[:50],
            },
        )
        return SymptomCatalogResponse(
            total=len(valid_symptoms), symptoms=valid_symptoms
        )

    @application.post(
        "/guidance",
        response_model=SymptomGuidanceResponse,
        responses={
            401: {"model": ErrorResponse, "description": "Authentication required"},
            403: {"model": ErrorResponse, "description": "App Check rejected"},
            429: {"model": ErrorResponse, "description": "Rate limit exceeded"},
            422: {"model": ErrorResponse, "description": "Invalid symptoms"},
            503: {"model": ErrorResponse, "description": "Guidance unavailable"},
        },
        summary="Retrieve symptom-based self-care and emergency guidance",
    )
    def guidance_endpoint(
        request: PredictionRequest,
        _authenticated_user: AuthenticatedUser = Depends(require_ai_access),
        guidance_service: SymptomGuidanceService = Depends(
            get_symptom_guidance_service
        ),
        disease_service: DiseaseService = Depends(get_disease_service),
    ) -> dict[str, Any] | JSONResponse:
        started = time.perf_counter()
        try:
            recognition = recognize_symptoms(
                request.symptoms, reject_if_empty=False
            )
            condition_recognition = recognize_diseases(
                recognition["ignoredSymptoms"]
            )
        except ArtifactLoadError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Symptom vocabulary is unavailable.",
            ) from exc

        recognized_symptoms = recognition["recognizedSymptoms"]
        recognized_conditions = condition_recognition["recognizedConditions"]
        ignored_keywords = condition_recognition["ignoredKeywords"]
        if not recognized_symptoms and not recognized_conditions:
            return JSONResponse(
                status_code=422,
                content={
                    "message": "No valid symptoms or known conditions were recognized.",
                    "recognizedSymptoms": [],
                    "recognizedConditions": [],
                    "ignoredSymptoms": ignored_keywords,
                },
            )

        if recognized_symptoms:
            try:
                guidance = guidance_service.get_for_symptoms(recognized_symptoms)
            except Exception:
                LOGGER.error(
                    "Firestore symptom guidance lookup unavailable",
                    extra={"event": "symptom_guidance_firestore_error"},
                )
                guidance = {
                    "matchedGuidanceSymptoms": [],
                    "missingGuidanceSymptoms": recognized_symptoms,
                    "homeCare": [],
                    "precautions": [],
                    "whenToSeekCare": [],
                    "emergencyWarningSigns": [],
                    "references": [],
                    "contentAvailable": False,
                }
        else:
            guidance = {
                "matchedGuidanceSymptoms": [],
                "missingGuidanceSymptoms": [],
                "homeCare": [],
                "precautions": [],
                "whenToSeekCare": [],
                "emergencyWarningSigns": [],
                "references": [],
                "contentAvailable": False,
            }

        condition_documents: list[dict[str, Any]] = []
        matched_conditions: list[str] = []
        missing_conditions: list[str] = []
        try:
            for condition in recognized_conditions:
                content = disease_service.get_disease_content_for_prediction(condition)
                if content is None:
                    missing_conditions.append(condition)
                else:
                    matched_conditions.append(condition)
                    condition_documents.append(content)
        except Exception:
            LOGGER.error(
                "Firestore entered-condition guidance lookup unavailable",
                extra={"event": "condition_guidance_firestore_error"},
            )
            missing_conditions = list(recognized_conditions)
            condition_documents = []
            matched_conditions = []

        def merged_strings(current: list[str], field: str) -> list[str]:
            values = list(current)
            for document in condition_documents:
                raw = document.get(field)
                if isinstance(raw, list):
                    values.extend(str(item).strip() for item in raw if str(item).strip())
            seen: set[str] = set()
            deduplicated: list[str] = []
            for value in values:
                key = value.casefold()
                if key not in seen:
                    seen.add(key)
                    deduplicated.append(value)
            return deduplicated

        guidance["homeCare"] = merged_strings(
            guidance["homeCare"], "selfCareGuidance"
        )
        guidance["precautions"] = merged_strings(
            guidance["precautions"], "avoidOrCaution"
        )
        guidance["whenToSeekCare"] = merged_strings(
            guidance["whenToSeekCare"], "whenToSeeDoctor"
        )
        guidance["emergencyWarningSigns"] = merged_strings(
            guidance["emergencyWarningSigns"], "emergencyWarningSigns"
        )
        references = list(guidance["references"])
        for document in condition_documents:
            raw_references = document.get("references")
            if isinstance(raw_references, list):
                references.extend(item for item in raw_references if isinstance(item, dict))
        guidance["references"] = references
        guidance["contentAvailable"] = bool(
            guidance["contentAvailable"] or condition_documents
        )

        response = {
            "recognizedSymptoms": recognized_symptoms,
            "recognizedConditions": recognized_conditions,
            "ignoredSymptoms": ignored_keywords,
            "matchedGuidanceConditions": matched_conditions,
            "missingGuidanceConditions": missing_conditions,
            **guidance,
            **suggest_health_category(
                recognized_conditions,
                recognized_symptoms,
            ),
            "disclaimer": DISCLAIMER,
        }
        LOGGER.info(
            "Symptom guidance completed",
            extra={
                "event": "symptom_guidance",
                "latencyMs": round((time.perf_counter() - started) * 1000, 2),
                "recognizedSymptoms": recognized_symptoms,
                "ignoredSymptoms": ignored_keywords,
                "contentAvailable": guidance["contentAvailable"],
            },
        )
        return response

    # Kept temporarily as an unregistered function for response-contract history.
    # There is intentionally no route decorator: POST /predict now returns 404.
    def _disabled_legacy_prediction_endpoint(
        request: PredictionRequest,
        disease_service: DiseaseService = Depends(get_disease_service),
    ) -> dict[str, Any] | JSONResponse:
        started = time.perf_counter()
        settings = get_settings()
        LOGGER.debug(
            "Prediction request received",
            extra={
                "event": "prediction_request",
                "incomingSymptoms": request.symptoms,
                "normalizedSymptoms": [
                    normalize_symptom(symptom) for symptom in request.symptoms
                ],
            },
        )
        try:
            inference = predict_top_diseases(request.symptoms, top_k=3)
        except NoRecognizedSymptomsError as exc:
            LOGGER.info(
                "Prediction rejected because no symptoms were recognized",
                extra={
                    "event": "no_recognized_symptoms",
                    "incomingSymptoms": request.symptoms,
                    "normalizedSymptoms": exc.normalized_symptoms,
                    "recognizedSymptoms": exc.recognized_symptoms,
                    "ignoredSymptoms": exc.ignored_symptoms,
                    "featureVectorCount": 0,
                },
            )
            return JSONResponse(
                status_code=422,
                content={
                    "message": str(exc),
                    "recognizedSymptoms": exc.recognized_symptoms,
                    "ignoredSymptoms": exc.ignored_symptoms,
                },
            )
        except ArtifactLoadError as exc:
            LOGGER.error(
                "Prediction artifacts unavailable",
                extra={"event": "artifact_error"},
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Prediction model is unavailable.",
            ) from exc
        except (TypeError, ValueError) as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Symptoms could not be processed.",
            ) from exc

        top_prediction = inference["topPredictions"][0]
        firestore_document_id = DiseaseService.document_id_for_prediction(
            str(top_prediction["disease"])
        )
        lookup_started = time.perf_counter()
        disease_content: dict[str, Any] | None = None
        try:
            disease_content = disease_service.get_disease_content_for_prediction(
                str(top_prediction["disease"])
            )
        except Exception:
            LOGGER.error(
                "Firestore disease lookup unavailable",
                extra={
                    "event": "firestore_error",
                    "disease": top_prediction["disease"],
                },
            )
        lookup_ms = round((time.perf_counter() - lookup_started) * 1000.0, 2)
        LOGGER.debug(
            "Firestore disease lookup completed",
            extra={
                "event": "firestore_lookup",
                "disease": top_prediction["disease"],
                "firestoreDocumentId": firestore_document_id,
                "firestoreLookupFound": disease_content is not None,
                "firestoreLookupMs": lookup_ms,
            },
        )
        response = build_prediction_response(
            inference,
            disease_content,
            confidence_threshold=settings.confidence_threshold,
        )
        latency_ms = round((time.perf_counter() - started) * 1000.0, 2)
        LOGGER.info(
            "Prediction completed",
            extra={
                "event": "prediction",
                "disease": top_prediction["disease"],
                "confidence": top_prediction["confidence"],
                "latencyMs": latency_ms,
                "unknownSymptoms": inference["ignoredSymptoms"],
                "firestoreLookupMs": lookup_ms,
                "contentAvailable": response["contentAvailable"],
                "recognizedSymptoms": inference["recognizedSymptoms"],
                "ignoredSymptoms": inference["ignoredSymptoms"],
                "topPredictions": inference["topPredictions"],
                "firestoreDocumentId": firestore_document_id,
                "firestoreLookupFound": disease_content is not None,
            },
        )
        return response

    return application


app = create_app()
