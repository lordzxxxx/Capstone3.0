"""Transform the reviewed source draft into one seed per production model class."""

from __future__ import annotations

import argparse
import csv
import json
import logging
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any

import joblib
import pandas as pd

FIREBASE_DIR = Path(__file__).resolve().parent
BACKEND_DIR = FIREBASE_DIR.parent
if str(FIREBASE_DIR) not in sys.path:
    sys.path.insert(0, str(FIREBASE_DIR))

from disease_schema import (  # noqa: E402
    ClinicalReview,
    DiseaseRecord,
    DiseaseReference,
    ensure_unique_disease_keys,
    normalize_disease_key,
    split_semicolon_values,
)

LOGGER = logging.getLogger(__name__)
SOURCE_PATH = (
    BACKEND_DIR
    / "dataset"
    / "knowledge_base"
    / "AI_DSUHIS_Disease_Self_Care_Knowledge_Base.csv"
)
SEED_PATH = FIREBASE_DIR / "disease_seed.json"
FIRESTORE_SEED_PATH = FIREBASE_DIR / "disease_seed_firestore.json"
REPORTS_DIR = BACKEND_DIR / "reports"
MODEL_CANDIDATES = (
    BACKEND_DIR / "models" / "current" / "disease_model.pkl",
    BACKEND_DIR / "models" / "disease_model.pkl",
)


def load_model_labels() -> tuple[list[str], str]:
    """Load exact production labels using the required source priority."""
    for model_path in MODEL_CANDIDATES:
        if model_path.exists():
            model = joblib.load(model_path)
            classes = getattr(model, "classes_", None)
            if classes is not None:
                labels = [str(label) for label in classes]
                return labels, str(model_path)
    metadata_path = BACKEND_DIR / "models" / "model_metadata.json"
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        labels = metadata.get("classes") or metadata.get("diseaseLabels")
        if isinstance(labels, list):
            return [str(label) for label in labels], str(metadata_path)
    dataset_path = (
        BACKEND_DIR / "dataset" / "raw" / "Diseases_and_Symptoms_dataset.csv"
    )
    disease_column = pd.read_csv(dataset_path, usecols=["diseases"])["diseases"]
    labels = sorted(disease_column.unique())
    return [str(label) for label in labels], str(dataset_path)


def _dataset_symptoms(value: object) -> list[str]:
    symptoms: list[str] = []
    for item in split_semicolon_values(value):
        symptom = re.sub(r"\s*\(\d+(?:\.\d+)?%\)\s*$", "", item).strip().lower()
        if symptom:
            symptoms.append(symptom)
    return symptoms


def _care_level(value: object) -> str:
    normalized = str(value).strip().lower()
    if normalized.startswith("emergency"):
        return "emergency_evaluation"
    if normalized.startswith("supportive"):
        return "supportive"
    return "prompt_medical_evaluation"


def _specialists(category: str, care_level: str) -> list[str]:
    category_lower = category.lower()
    mappings = {
        "skin": "Dermatology",
        "respiratory": "Pulmonology",
        "cardiovascular": "Cardiology",
        "neurolog": "Neurology",
        "mental": "Psychiatry",
        "pregnancy": "Obstetrics and Gynecology",
        "gynec": "Obstetrics and Gynecology",
        "urinary": "Urology",
        "gastro": "Gastroenterology",
        "eye": "Ophthalmology",
        "ear": "Otolaryngology",
        "pediatric": "Pediatrics",
    }
    specialists = [
        specialist
        for fragment, specialist in mappings.items()
        if fragment in category_lower
    ]
    if not specialists:
        specialists.append("General Practitioner")
    if care_level == "emergency_evaluation":
        specialists.insert(0, "Emergency Medicine")
    return list(dict.fromkeys(specialists))


def transform_source(
    source_path: Path = SOURCE_PATH,
    accessed_at: str | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Transform source rows and report model/source mismatches."""
    labels, label_source = load_model_labels()
    key_to_label = ensure_unique_disease_keys(labels)
    source = pd.read_csv(source_path, dtype=str).fillna("")
    source_by_key: dict[str, dict[str, str]] = {}
    duplicate_source_keys: list[str] = []
    for row in source.to_dict(orient="records"):
        key = normalize_disease_key(row["disease_key"] or row["disease_name"])
        if key in source_by_key:
            duplicate_source_keys.append(key)
        source_by_key[key] = row
    if duplicate_source_keys:
        raise ValueError(f"Duplicate source disease keys: {duplicate_source_keys}")

    accessed = accessed_at or date.today().isoformat()
    records: list[dict[str, Any]] = []
    missing: list[str] = []
    for key, model_label in key_to_label.items():
        row = source_by_key.get(key)
        if row is None:
            missing.append(model_label)
            continue
        care_level = _care_level(row["self_care_level"])
        references = [
            DiseaseReference(
                organization="MedlinePlus",
                title=f"MedlinePlus search results for {row['disease_name']}",
                url=row["medlineplus_lookup_url"],
                accessed_at=accessed,
            ),
            DiseaseReference(
                organization="National Health Service",
                title=f"NHS search results for {row['disease_name']}",
                url=row["nhs_lookup_url"],
                accessed_at=accessed,
            ),
        ]
        record = DiseaseRecord(
            disease_key=key,
            name=row["disease_name"].strip(),
            model_label=model_label,
            category=row["category"].strip(),
            self_care_level=care_level,
            dataset_symptoms=_dataset_symptoms(row["dataset_top_symptoms"]),
            self_care_guidance=split_semicolon_values(row["safe_self_care_draft"]),
            avoid_or_caution=split_semicolon_values(row["avoid_or_caution"]),
            when_to_see_doctor=split_semicolon_values(
                row["when_to_seek_medical_care"]
            ),
            emergency_warning_signs=split_semicolon_values(
                row["general_emergency_warning_signs"]
            ),
            recommended_specialist=_specialists(row["category"], care_level),
            references=references,
            clinical_review=ClinicalReview(
                status="needs_review",
                notes=row["validation_note"].strip(),
            ),
        )
        records.append(record.to_dict())

    unmatched = sorted(set(source_by_key) - set(key_to_label))
    report = {
        "labelSource": label_source,
        "expectedModelLabels": len(labels),
        "generatedRecords": len(records),
        "missingModelLabels": missing,
        "unmatchedSourceKeys": unmatched,
    }
    return records, report


def _write_csv(path: Path, header: str, values: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow([header])
        writer.writerows([[value] for value in values])


def write_outputs(records: list[dict[str, Any]], report: dict[str, Any]) -> None:
    """Write list/map seed formats and mismatch reports."""
    FIREBASE_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    SEED_PATH.write_text(json.dumps(records, indent=2), encoding="utf-8")
    firestore_payload = {
        "diseases": {record["diseaseKey"]: record for record in records}
    }
    FIRESTORE_SEED_PATH.write_text(
        json.dumps(firestore_payload, indent=2), encoding="utf-8"
    )
    _write_csv(
        REPORTS_DIR / "missing_disease_records.csv",
        "modelLabel",
        report["missingModelLabels"],
    )
    _write_csv(
        REPORTS_DIR / "unmatched_disease_labels.csv",
        "sourceDiseaseKey",
        report["unmatchedSourceKeys"],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE_PATH)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    records, report = transform_source(args.source)
    write_outputs(records, report)
    LOGGER.info("Generated %d disease documents", len(records))
    LOGGER.info("Model-label source: %s", report["labelSource"])
    if report["missingModelLabels"] or report["unmatchedSourceKeys"]:
        LOGGER.error("Source/model mismatch detected: %s", report)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
