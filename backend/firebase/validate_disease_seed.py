"""Validate disease seed coverage, schema, safety, and model-label matching."""

from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

FIREBASE_DIR = Path(__file__).resolve().parent
BACKEND_DIR = FIREBASE_DIR.parent
if str(FIREBASE_DIR) not in sys.path:
    sys.path.insert(0, str(FIREBASE_DIR))

from disease_schema import (  # noqa: E402
    ensure_unique_disease_keys,
    normalize_disease_key,
    validate_disease_record,
)
from generate_disease_seed import load_model_labels  # noqa: E402

LOGGER = logging.getLogger(__name__)
DEFAULT_SEED_PATH = FIREBASE_DIR / "disease_seed.json"
REPORT_PATH = BACKEND_DIR / "reports" / "disease_seed_validation.json"
MISSING_PATH = BACKEND_DIR / "reports" / "missing_disease_records.csv"
UNMATCHED_PATH = BACKEND_DIR / "reports" / "unmatched_disease_labels.csv"
EXPECTED_LABEL_COUNT = 100


def _write_single_column_csv(path: Path, header: str, values: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow([header])
        writer.writerows([[value] for value in values])


def _contains_supported_json_types(value: Any) -> bool:
    if value is None or isinstance(value, (str, int, float, bool)):
        return True
    if isinstance(value, list):
        return all(_contains_supported_json_types(item) for item in value)
    if isinstance(value, dict):
        return all(
            isinstance(key, str) and _contains_supported_json_types(item)
            for key, item in value.items()
        )
    return False


def validate_seed(
    records: list[dict[str, Any]], expected_labels: list[str]
) -> dict[str, Any]:
    """Return a complete machine-readable validation report."""
    critical_errors: list[str] = []
    warnings: list[str] = []
    record_results: list[dict[str, Any]] = []
    try:
        expected_keys = ensure_unique_disease_keys(expected_labels)
    except ValueError as exc:
        critical_errors.append(str(exc))
        expected_keys = {}

    if len(expected_labels) != EXPECTED_LABEL_COUNT:
        critical_errors.append(
            f"Expected {EXPECTED_LABEL_COUNT} model labels, "
            f"found {len(expected_labels)}"
        )
    if len(records) != EXPECTED_LABEL_COUNT:
        critical_errors.append(
            f"Expected {EXPECTED_LABEL_COUNT} seed records, found {len(records)}"
        )

    seed_keys = [str(record.get("diseaseKey", "")) for record in records]
    duplicate_keys = sorted({key for key in seed_keys if seed_keys.count(key) > 1})
    if duplicate_keys:
        critical_errors.append(f"Duplicate diseaseKey values: {duplicate_keys}")
    seed_labels = [str(record.get("modelLabel", "")) for record in records]
    expected_label_set = set(expected_labels)
    seed_label_set = set(seed_labels)
    missing_labels = sorted(expected_label_set - seed_label_set)
    unmatched_labels = sorted(seed_label_set - expected_label_set)
    if missing_labels:
        critical_errors.append(f"Missing model labels: {missing_labels}")
    if unmatched_labels:
        critical_errors.append(f"Unsupported seed labels: {unmatched_labels}")

    for index, record in enumerate(records):
        key = str(record.get("diseaseKey", f"record_{index}"))
        errors, record_warnings = validate_disease_record(record)
        model_label = str(record.get("modelLabel", ""))
        if model_label in expected_label_set:
            expected_key = normalize_disease_key(model_label)
            if key != expected_key:
                errors.append(
                    f"diseaseKey does not match modelLabel; expected {expected_key!r}"
                )
        if not _contains_supported_json_types(record):
            errors.append("record contains unsupported field types")
        if errors:
            critical_errors.extend(f"{key}: {error}" for error in errors)
        warnings.extend(f"{key}: {warning}" for warning in record_warnings)
        record_results.append(
            {"diseaseKey": key, "errors": errors, "warnings": record_warnings}
        )

    missing_keys = sorted(set(expected_keys) - set(seed_keys))
    unmatched_keys = sorted(set(seed_keys) - set(expected_keys))
    if missing_keys:
        critical_errors.append(f"Missing Firestore document IDs: {missing_keys}")
    if unmatched_keys:
        critical_errors.append(f"Unexpected Firestore document IDs: {unmatched_keys}")

    return {
        "validatedAt": datetime.now(timezone.utc).isoformat(),
        "expectedModelLabels": len(expected_labels),
        "seedRecords": len(records),
        "uniqueDiseaseKeys": len(set(seed_keys)),
        "matchedModelLabels": len(expected_label_set & seed_label_set),
        "missingModelLabels": missing_labels,
        "unmatchedModelLabels": unmatched_labels,
        "missingDiseaseKeys": missing_keys,
        "unmatchedDiseaseKeys": unmatched_keys,
        "criticalErrorCount": len(critical_errors),
        "warningCount": len(warnings),
        "valid": not critical_errors,
        "criticalErrors": critical_errors,
        "warnings": warnings,
        "records": record_results,
    }


def validate_seed_file(seed_path: Path = DEFAULT_SEED_PATH) -> dict[str, Any]:
    """Load seed/model labels, validate, and update all validation reports."""
    payload = json.loads(seed_path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not all(
        isinstance(record, dict) for record in payload
    ):
        raise ValueError("disease_seed.json must contain an array of objects")
    labels, label_source = load_model_labels()
    report = validate_seed(payload, labels)
    report["modelLabelSource"] = label_source
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    _write_single_column_csv(
        MISSING_PATH, "modelLabel", report["missingModelLabels"]
    )
    _write_single_column_csv(
        UNMATCHED_PATH, "modelLabel", report["unmatchedModelLabels"]
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED_PATH)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    try:
        report = validate_seed_file(args.seed)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        LOGGER.error("Validation could not run: %s", exc)
        return 2
    LOGGER.info(
        "Validated %d records against %d model labels",
        report["seedRecords"],
        report["expectedModelLabels"],
    )
    LOGGER.info("Warnings: %d", report["warningCount"])
    if not report["valid"]:
        for error in report["criticalErrors"]:
            LOGGER.error(error)
        return 1
    LOGGER.info("Disease seed is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
