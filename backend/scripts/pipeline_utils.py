"""Shared utilities for the reusable medical dataset pipeline."""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

import pandas as pd


BACKEND_DIR = Path(__file__).resolve().parents[1]
RAW_DIR = BACKEND_DIR / "dataset" / "raw"
PROCESSED_DIR = BACKEND_DIR / "dataset" / "processed"
MAPPINGS_DIR = BACKEND_DIR / "dataset" / "mappings"
MODELS_DIR = BACKEND_DIR / "models"
DISEASE_COLUMN = "diseases"

# These aliases occur in the supplied datasets. ``Name`` is accepted only when
# a symptom field is also present, preventing remedy/catalog files from being
# mistaken for supervised-learning data.
DISEASE_ALIASES = {"disease", "diseases", "label"}
NON_FEATURE_COLUMNS = {
    "code",
    "frequency",
    "index",
    "unnamed: 0",
    "treatment",
    "treatments",
    "remedy",
}


def ensure_directories() -> None:
    """Create all pipeline output directories when they do not exist."""
    for directory in (RAW_DIR, PROCESSED_DIR, MAPPINGS_DIR, MODELS_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def configure_logging(name: str) -> logging.Logger:
    """Return a consistently formatted console logger."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%H:%M:%S",
    )
    return logging.getLogger(name)


def load_mapping(path: Path) -> dict[str, str]:
    """Load and normalize a JSON synonym mapping."""
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        values: dict[str, Any] = json.load(handle)
    return {
        basic_normalize(str(source)): basic_normalize(str(target))
        for source, target in values.items()
    }


def basic_normalize(value: str) -> str:
    """Normalize whitespace, case, separators, and a leading symptom prefix."""
    text = str(value).strip().lower().replace("_", " ")
    text = re.sub(r"^symptom\s+", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def normalize_disease(value: object, mapping: dict[str, str]) -> str:
    """Normalize a disease label and apply configured synonyms."""
    normalized = basic_normalize(str(value))
    return mapping.get(normalized, normalized)


def normalize_symptom(value: object, mapping: dict[str, str]) -> str:
    """Normalize a symptom label, including UMLS-prefixed column names."""
    normalized = basic_normalize(str(value))
    normalized = re.sub(r"^umls:c[0-9]+\s*", "", normalized).strip()
    return mapping.get(normalized, normalized)


def detect_disease_column(columns: list[object]) -> object | None:
    """Find the disease target using safe, case-insensitive aliases."""
    normalized = {basic_normalize(str(column)): column for column in columns}
    for alias in DISEASE_ALIASES:
        if alias in normalized:
            return normalized[alias]
    if "name" in normalized and ({"symptom", "symptoms"} & normalized.keys()):
        return normalized["name"]
    return None


def detect_text_symptom_column(columns: list[object]) -> object | None:
    """Find a column containing a symptom list or symptom narrative."""
    normalized = {basic_normalize(str(column)): column for column in columns}
    for candidate in ("symptoms", "symptom", "text"):
        if candidate in normalized:
            return normalized[candidate]
    return None


def collapse_duplicate_columns(frame: pd.DataFrame) -> pd.DataFrame:
    """Combine columns that normalize to the same symptom using logical OR."""
    if not frame.columns.duplicated().any():
        return frame
    disease = frame[DISEASE_COLUMN]
    features = frame.drop(columns=[DISEASE_COLUMN])
    features = features.T.groupby(level=0, sort=False).max().T
    features.insert(0, DISEASE_COLUMN, disease)
    return features


def prepare_wide_dataset(
    frame: pd.DataFrame,
    disease_column: object,
    disease_mapping: dict[str, str],
    symptom_mapping: dict[str, str],
) -> pd.DataFrame:
    """Convert a wide disease/binary-symptom table to the canonical schema."""
    disease = frame[disease_column].map(
        lambda value: normalize_disease(value, disease_mapping)
    )
    features: dict[str, pd.Series] = {}
    for column in frame.columns:
        if column == disease_column:
            continue
        raw_name = basic_normalize(str(column))
        if raw_name in NON_FEATURE_COLUMNS:
            continue
        symptom = normalize_symptom(column, symptom_mapping)
        if not symptom:
            continue
        numeric = pd.to_numeric(frame[column], errors="coerce").fillna(0)
        binary = numeric.ne(0).astype("uint8")
        features[symptom] = (
            features[symptom].combine(binary, max)
            if symptom in features
            else binary
        )
    result = pd.DataFrame(features, index=frame.index)
    result.insert(0, DISEASE_COLUMN, disease)
    return result


def prepare_text_dataset(
    frame: pd.DataFrame,
    disease_column: object,
    text_column: object,
    disease_mapping: dict[str, str],
    symptom_mapping: dict[str, str],
    known_symptoms: set[str],
    explicit_list: bool = False,
) -> pd.DataFrame:
    """Convert comma-separated or narrative symptoms into binary features."""
    records: list[dict[str, object]] = []
    searchable = sorted(known_symptoms, key=len, reverse=True)
    for disease_value, text_value in zip(
        frame[disease_column], frame[text_column], strict=False
    ):
        text = basic_normalize(str(text_value))
        row: dict[str, object] = {
            DISEASE_COLUMN: normalize_disease(disease_value, disease_mapping)
        }
        # Explicit lists preserve symptoms that do not occur in a wide dataset.
        # Free-text narratives are intentionally limited to known phrases so a
        # complete sentence never becomes a one-off feature.
        if explicit_list:
            for token in re.split(r"[,;|]", text):
                symptom = normalize_symptom(token, symptom_mapping)
                if symptom and len(symptom) <= 80:
                    row[symptom] = 1
        # Narrative datasets are encoded using phrases learned from wide/list data.
        for symptom in searchable:
            if symptom and symptom in text:
                row[symptom] = 1
        records.append(row)
    result = pd.DataFrame.from_records(records).fillna(0)
    for column in result.columns:
        if column != DISEASE_COLUMN:
            result[column] = result[column].astype("uint8")
    return result


def remove_empty_labels(frame: pd.DataFrame) -> pd.DataFrame:
    """Remove missing labels and common string representations of missing data."""
    invalid = {"", "nan", "none", "null"}
    return frame.loc[~frame[DISEASE_COLUMN].isin(invalid)].copy()
