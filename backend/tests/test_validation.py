"""Generated seed/model coverage tests."""

from __future__ import annotations

import json
from pathlib import Path

from generate_disease_seed import load_model_labels
from validate_disease_seed import validate_seed

BACKEND_DIR = Path(__file__).resolve().parents[1]


def test_generated_seed_matches_all_model_labels() -> None:
    records = json.loads(
        (BACKEND_DIR / "firebase" / "disease_seed.json").read_text(encoding="utf-8")
    )
    labels, _ = load_model_labels()
    report = validate_seed(records, labels)
    assert len(labels) == 100
    assert report["seedRecords"] == 100
    assert report["matchedModelLabels"] == 100
    assert report["criticalErrorCount"] == 0
