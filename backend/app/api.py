"""Production FastAPI endpoints for disease inference and Firestore enrichment."""

from __future__ import annotations

import json
import io
import logging
import re
import time
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request as UrlRequest
from urllib.request import urlopen

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware
from PIL import Image, UnidentifiedImageError

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
    from .security import (
        AuthenticatedUser,
        enforce_api_rate_limit,
        enforce_ocr_rate_limit,
        require_ai_access,
    )
    from .schemas import (
        DiseaseInformation,
        ErrorResponse,
        HealthResponse,
        OCRBatchResponse,
        OCRFieldResult,
        PredictionRequest,
        PredictionResponse,
        RootStatusResponse,
        SymptomCatalogResponse,
        SymptomGuidanceResponse,
        TurnstileVerifyRequest,
        TurnstileVerifyResponse,
    )
    from .ocr_service import TrOCRHandwritingEngine
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
    from security import (
        AuthenticatedUser,
        enforce_api_rate_limit,
        enforce_ocr_rate_limit,
        require_ai_access,
    )
    from schemas import (
        DiseaseInformation,
        ErrorResponse,
        HealthResponse,
        OCRBatchResponse,
        OCRFieldResult,
        PredictionRequest,
        PredictionResponse,
        RootStatusResponse,
        SymptomCatalogResponse,
        SymptomGuidanceResponse,
        TurnstileVerifyRequest,
        TurnstileVerifyResponse,
    )
    from ocr_service import TrOCRHandwritingEngine

DISCLAIMER = (
    "This application provides educational decision support only. It is not a "
    "medical diagnosis. Consult a licensed healthcare professional."
)
LOW_CONFIDENCE_WARNING = "The prediction confidence is low."
_MEDICATION_GUIDANCE_PATTERN = re.compile(
    r"\b(medications?|medicines?|dosage|prescription|prescribed|"
    r"antibiotics?|inhaler)\b",
    re.IGNORECASE,
)
_MAX_REQUEST_BYTES = 64 * 1024
_MAX_OCR_REQUEST_BYTES = 20 * 1024 * 1024
_MAX_OCR_FILE_BYTES = 5 * 1024 * 1024
_MAX_OCR_FILES = 10
_MAX_OCR_DIMENSION = 4096
_ALLOWED_OCR_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
_FIELD_ID_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


class _RequestTooLarge(Exception):
    """Internal signal used to stop streaming request bodies at the limit."""


def _validate_field_id(value: Any) -> str:
    field_id = str(value).strip()
    if not _FIELD_ID_PATTERN.fullmatch(field_id):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="field_id must contain only letters, numbers, dots, underscores, or hyphens.",
        )
    return field_id


async def _read_validated_ocr_upload(file_upload: Any) -> bytes:
    """Validate declared and actual image data before it reaches the ML model."""
    content_type = str(getattr(file_upload, "content_type", "") or "").casefold()
    if content_type not in _ALLOWED_OCR_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="OCR accepts JPEG, PNG, or WebP images only.",
        )
    content = await file_upload.read(_MAX_OCR_FILE_BYTES + 1)
    if len(content) > _MAX_OCR_FILE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail="Each OCR image must be 5 MB or smaller.",
        )
    try:
        with Image.open(io.BytesIO(content)) as image:
            image.verify()
        with Image.open(io.BytesIO(content)) as image:
            expected_formats = {
                "image/jpeg": {"JPEG"},
                "image/png": {"PNG"},
                "image/webp": {"WEBP"},
            }
            if image.format not in expected_formats[content_type]:
                raise HTTPException(
                    status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                    detail="The declared image type does not match the file contents.",
                )
            width, height = image.size
            if (
                width < 1
                or height < 1
                or width > _MAX_OCR_DIMENSION
                or height > _MAX_OCR_DIMENSION
                or width * height > 16_000_000
            ):
                raise HTTPException(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    detail="OCR images exceed the supported dimensions.",
                )
    except (UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The uploaded file is not a valid image.",
        ) from None
    return content


def _safe_guidance_strings(values: list[str]) -> list[str]:
    """Keep active guidance supportive; never return medication instructions."""
    return [
        value
        for value in values
        if not _MEDICATION_GUIDANCE_PATTERN.search(str(value))
    ]


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
            "recognizedSymptomCount",
            "ignoredSymptomCount",
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
    settings = get_settings()
    application = FastAPI(
        title="AI-DSUHIS Symptom Guidance API",
        version=settings.model_version,
        description=(
            "Keyword-based self-care and emergency guidance retrieved from "
            "reviewed Firestore content. This API does not provide a diagnosis."
        ),
    )
    application.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=list(settings.api_allowed_hosts),
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.web_allowed_origins),
        allow_origin_regex=(
            r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
            if settings.allow_local_cors
            else None
        ),
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=[
            "Content-Type",
            "Accept",
            "Authorization",
            "X-Firebase-AppCheck",
        ],
    )

    @application.middleware("http")
    async def _request_size_limit(request: Request, call_next):
        """Reject oversized bodies before parsing or processing them."""
        if request.method != "OPTIONS" and request.url.path not in {"/", "/health"}:
            client_key = request.client.host if request.client else "unknown"
            try:
                enforce_api_rate_limit(client_key)
            except HTTPException as exc:
                return JSONResponse(
                    status_code=exc.status_code,
                    content={"detail": exc.detail},
                    headers=exc.headers,
                )

        max_request_bytes = (
            _MAX_OCR_REQUEST_BYTES
            if request.url.path.startswith("/api/v1/ocr/")
            else _MAX_REQUEST_BYTES
        )
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > max_request_bytes:
                    return JSONResponse(
                        status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                        content={"detail": "Request body is too large."},
                    )
            except ValueError:
                return JSONResponse(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    content={"detail": "Invalid Content-Length header."},
                )

        if request.method not in {"POST", "PUT", "PATCH"}:
            return await call_next(request)

        original_receive = request._receive
        received_bytes = 0

        async def limited_receive():
            nonlocal received_bytes
            message = await original_receive()
            if message.get("type") == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > max_request_bytes:
                    raise _RequestTooLarge
            return message

        request._receive = limited_receive
        try:
            return await call_next(request)
        except _RequestTooLarge:
            return JSONResponse(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                content={"detail": "Request body is too large."},
            )

    @application.middleware("http")
    async def _security_headers(request: Request, call_next):
        """Baseline hardening headers for every response.

        This API only ever returns JSON. The no-store policy prevents
        authenticated guidance and OCR responses from being cached by
        browsers or intermediary proxies.
        """
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Permitted-Cross-Domain-Policies"] = "none"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
        )
        response.headers["Permissions-Policy"] = (
            "geolocation=(), camera=(), microphone=(), payment=()"
        )
        response.headers["Strict-Transport-Security"] = (
            "max-age=63072000; includeSubDomains"
        )
        return response

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

    @application.post(
        "/security/turnstile/verify",
        response_model=TurnstileVerifyResponse,
        responses={
            400: {"model": ErrorResponse, "description": "Invalid Turnstile token"},
            429: {"model": ErrorResponse, "description": "Rate limit exceeded"},
            503: {"model": ErrorResponse, "description": "Turnstile is not configured"},
        },
        summary="Verify a Cloudflare Turnstile token for web authentication",
    )
    def verify_turnstile(
        payload: TurnstileVerifyRequest,
        request: Request,
    ) -> TurnstileVerifyResponse:
        """Validate the one-use browser token before Firebase Auth actions."""
        client_key = (
            request.client.host
            if request.client and request.client.host
            else "unknown"
        )
        enforce_api_rate_limit(f"turnstile:{client_key}")
        settings = get_settings()
        if not settings.turnstile_secret_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Cloudflare Turnstile is not configured.",
            )

        fields = {
            "secret": settings.turnstile_secret_key,
            "response": payload.token,
        }
        if request.client and request.client.host:
            fields["remoteip"] = request.client.host
        try:
            body = urlencode(fields).encode("utf-8")
            verification_request = UrlRequest(
                "https://challenges.cloudflare.com/turnstile/v0/siteverify",
                data=body,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                method="POST",
            )
            with urlopen(verification_request, timeout=5) as response:
                result = json.loads(response.read().decode("utf-8"))
        except Exception:
            LOGGER.warning(
                "Cloudflare Turnstile verification request failed",
                extra={"event": "turnstile_verification_unavailable"},
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Cloudflare verification is temporarily unavailable.",
            ) from None

        hostname = str(result.get("hostname", "")).strip().casefold()
        action = str(result.get("action", "")).strip()
        if (
            result.get("success") is not True
            or action != payload.action
            or hostname not in {value.casefold() for value in settings.turnstile_hostnames}
        ):
            LOGGER.warning(
                "Cloudflare Turnstile verification rejected",
                extra={"event": "turnstile_verification_rejected"},
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cloudflare verification failed. Please try again.",
            )
        return TurnstileVerifyResponse(success=True)

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
        # Firestore guidance is reviewed reference content, but older documents
        # may still contain medication wording. Enforce the clinical boundary
        # at the API response so active AI output stays limited to supportive
        # care, precautions, warning signs, monitoring, and referral prompts.
        for field in (
            "homeCare",
            "precautions",
            "whenToSeekCare",
            "emergencyWarningSigns",
        ):
            guidance[field] = _safe_guidance_strings(guidance[field])
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
                "recognizedSymptomCount": len(recognized_symptoms),
                "ignoredSymptomCount": len(ignored_keywords),
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

    @application.post(
        "/api/v1/ocr/handwriting",
        response_model=OCRFieldResult,
        summary="Extract handwritten text from an image ROI crop",
        tags=["OCR"],
    )
    async def recognize_single_handwriting(
        request: Request,
        authenticated_user: AuthenticatedUser = Depends(require_ai_access),
    ) -> OCRFieldResult:
        """Transcribes a single cropped handwritten image ROI using TrOCR."""
        enforce_ocr_rate_limit(authenticated_user)
        form = await request.form()
        file_upload = form.get("file")
        field_id = _validate_field_id(form.get("field_id", "field"))

        if file_upload is None or not hasattr(file_upload, "read"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Form field 'file' containing image bytes is required.",
            )

        content = await _read_validated_ocr_upload(file_upload)
        engine = TrOCRHandwritingEngine.get_instance()
        started = time.perf_counter()
        
        # Async offload to threadpool
        import asyncio
        text, confidence = await asyncio.to_thread(engine.recognize_single, content)
        elapsed_ms = round((time.perf_counter() - started) * 1000.0, 2)

        return OCRFieldResult(
            field_id=field_id,
            text=text,
            confidence=confidence,
            processing_time_ms=elapsed_ms,
        )

    @application.post(
        "/api/v1/ocr/handwriting/batch",
        response_model=OCRBatchResponse,
        summary="Extract handwritten text from multiple image ROIs concurrently",
        tags=["OCR"],
    )
    async def recognize_batch_handwriting(
        request: Request,
        authenticated_user: AuthenticatedUser = Depends(require_ai_access),
    ) -> OCRBatchResponse:
        """Batch transcribes multiple cropped handwritten image ROIs."""
        enforce_ocr_rate_limit(authenticated_user)
        form = await request.form()
        files = form.getlist("files")
        field_ids = form.getlist("field_ids")

        if not files:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="At least one image in 'files' is required.",
            )

        if len(files) > _MAX_OCR_FILES:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail=f"OCR batches are limited to {_MAX_OCR_FILES} images.",
            )
        if len(field_ids) > len(files):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="There cannot be more field_ids than files.",
            )

        contents: list[bytes] = []
        total_bytes = 0
        for file_upload in files:
            if not hasattr(file_upload, "read"):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Every OCR batch item must be an image upload.",
                )
            content = await _read_validated_ocr_upload(file_upload)
            total_bytes += len(content)
            if total_bytes > _MAX_OCR_REQUEST_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    detail="The total OCR batch must be 20 MB or smaller.",
                )
            contents.append(content)
        validated_field_ids = [
            _validate_field_id(field_id) for field_id in field_ids
        ]
        engine = TrOCRHandwritingEngine.get_instance()
        started = time.perf_counter()

        import asyncio
        batch_results = await asyncio.to_thread(engine.recognize_batch, contents)
        elapsed_ms = round((time.perf_counter() - started) * 1000.0, 2)

        results: list[OCRFieldResult] = []
        for idx, (text, conf) in enumerate(batch_results):
            fid = (
                validated_field_ids[idx]
                if idx < len(validated_field_ids)
                else f"field_{idx}"
            )
            results.append(
                OCRFieldResult(
                    field_id=fid,
                    text=text,
                    confidence=conf,
                    processing_time_ms=elapsed_ms,
                )
            )

        return OCRBatchResponse(
            success=True,
            processing_time_ms=elapsed_ms,
            results=results,
        )

    return application


app = create_app()
