"""Validate and optionally seed symptom-guidance documents into Firestore."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

FIREBASE_DIR = Path(__file__).resolve().parent
APP_DIR = FIREBASE_DIR.parent / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from firebase_service import get_firestore_client  # noqa: E402
from symptom_guidance_service import normalize_symptom_key  # noqa: E402

SEED_PATH = FIREBASE_DIR / "symptom_guidance_seed.json"
LIST_FIELDS = (
    "homeCare",
    "precautions",
    "whenToSeekCare",
    "emergencyWarningSigns",
    "references",
)


def load_and_validate(path: Path = SEED_PATH) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not payload:
        raise ValueError("Symptom guidance seed must be a non-empty array")
    keys: set[str] = set()
    records: list[dict[str, Any]] = []
    for index, value in enumerate(payload):
        if not isinstance(value, dict):
            raise ValueError(f"Record {index} must be an object")
        record = dict(value)
        key = str(record.get("symptomKey", "")).strip()
        symptom = str(record.get("symptom", "")).strip()
        if not key or not symptom:
            raise ValueError(f"Record {index} requires symptomKey and symptom")
        if key != "_default" and key != normalize_symptom_key(symptom):
            raise ValueError(f"Invalid symptom key {key!r} for {symptom!r}")
        if key in keys:
            raise ValueError(f"Duplicate symptom key: {key}")
        keys.add(key)
        for field in LIST_FIELDS:
            if not isinstance(record.get(field), list):
                raise ValueError(f"{key}.{field} must be an array")
        if record.get("isActive") is not True:
            raise ValueError(f"{key} must explicitly set isActive=true")
        records.append(record)
    if "_default" not in keys:
        raise ValueError("Seed must include the _default guidance document")
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    records = load_and_validate()
    if not args.apply:
        print(f"Validated {len(records)} symptom-guidance documents (dry run).")
        return 0
    db = get_firestore_client()
    batch = db.batch()
    collection = db.collection("symptom_guidance")
    for record in records:
        batch.set(collection.document(record["symptomKey"]), record, merge=True)
    batch.commit()
    print(f"Applied {len(records)} symptom-guidance documents.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
