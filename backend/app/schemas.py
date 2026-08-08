"""Pydantic request and response contracts shown in FastAPI Swagger docs."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PredictionRequest(BaseModel):
    """Symptom names supplied by Flutter."""

    symptoms: list[str] = Field(
        min_length=1,
        max_length=500,
        description="One or more symptom names, such as fever or cough.",
        examples=[["fever", "headache", "fatigue"]],
    )

    @field_validator("symptoms")
    @classmethod
    def validate_symptoms(cls, values: list[str]) -> list[str]:
        cleaned: list[str] = []
        for value in values:
            if not isinstance(value, str) or not value.strip():
                raise ValueError("Every symptom must be a non-empty string")
            cleaned.append(value.strip())
        return cleaned


class PredictionItem(BaseModel):
    disease: str
    confidence: float = Field(ge=0.0, le=100.0)
    rank: int = Field(ge=1)


class ReferenceInformation(BaseModel):
    model_config = ConfigDict(extra="ignore")

    organization: str
    title: str = ""
    url: str = ""
    accessedAt: str = ""


class DiseaseInformation(BaseModel):
    """Public Firestore knowledge fields safe to return to Flutter."""

    model_config = ConfigDict(extra="ignore")

    diseaseKey: str = ""
    name: str = ""
    category: str = ""
    description: str = ""
    commonSymptoms: list[str] = Field(default_factory=list)
    selfCareGuidance: list[str] = Field(default_factory=list)
    prevention: list[str] = Field(default_factory=list)
    riskFactors: list[str] = Field(default_factory=list)
    possibleComplications: list[str] = Field(default_factory=list)
    whenToSeeDoctor: list[str] = Field(default_factory=list)
    emergencyWarningSigns: list[str] = Field(default_factory=list)
    recommendedSpecialist: list[str] = Field(default_factory=list)
    references: list[ReferenceInformation] = Field(default_factory=list)


class PredictionResponse(BaseModel):
    prediction: PredictionItem
    topPredictions: list[PredictionItem]
    recognizedSymptoms: list[str]
    ignoredSymptoms: list[str]
    diseaseInformation: DiseaseInformation | None = None
    contentAvailable: bool
    confidenceThresholdMet: bool
    warning: str | None = None
    fallbackMessage: str | None = None
    disclaimer: str


class RootStatusResponse(BaseModel):
    status: str
    modelVersion: str
    loadedSuccessfully: bool


class HealthResponse(BaseModel):
    status: str
    modelLoaded: bool
    firestoreConfigured: bool


class SymptomCatalogResponse(BaseModel):
    total: int = Field(ge=1)
    symptoms: list[str]


class GuidanceReference(BaseModel):
    organization: str = ""
    title: str = ""
    url: str = ""


class SymptomGuidanceResponse(BaseModel):
    recognizedSymptoms: list[str]
    recognizedConditions: list[str]
    ignoredSymptoms: list[str]
    matchedGuidanceSymptoms: list[str]
    missingGuidanceSymptoms: list[str]
    matchedGuidanceConditions: list[str]
    missingGuidanceConditions: list[str]
    homeCare: list[str]
    precautions: list[str]
    whenToSeekCare: list[str]
    emergencyWarningSigns: list[str]
    references: list[GuidanceReference]
    contentAvailable: bool
    disclaimer: str
    suggestedHealthCategory: str
    categoryBasis: str
    categoryRequiresReview: bool
    categoryRuleVersion: str
    categoryMatchedConditions: list[str]
    categoryUnmappedConditions: list[str]
    categoryMatchedSymptoms: list[str]
    categoryUnmappedSymptoms: list[str]


class ErrorResponse(BaseModel):
    detail: str | None = None
    message: str | None = None
    recognizedSymptoms: list[str] | None = None
    ignoredSymptoms: list[str] | None = None
    context: dict[str, Any] | None = None
