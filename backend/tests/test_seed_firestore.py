"""Offline Firestore seed planning tests."""

from __future__ import annotations

import json
from pathlib import Path

import seed_firestore
from seed_firestore import firestore_payload, prepare_batches, run_seed


def test_batch_preparation() -> None:
    records = [{"diseaseKey": str(index)} for index in range(205)]
    batches = list(prepare_batches(records, 100))
    assert [len(batch) for batch in batches] == [100, 100, 5]


def test_firestore_payload_timestamp_handling() -> None:
    record = {
        "diseaseKey": "influenza",
        "createdAt": "__SERVER_TIMESTAMP__",
        "updatedAt": "__SERVER_TIMESTAMP__",
    }
    created = firestore_payload(record, "SERVER_TIME", is_create=True)
    updated = firestore_payload(record, "SERVER_TIME", is_create=False)
    assert created["createdAt"] == "SERVER_TIME"
    assert created["updatedAt"] == "SERVER_TIME"
    assert "createdAt" not in updated


def test_dry_run_never_requests_firestore(
    tmp_path: Path, monkeypatch
) -> None:
    seed_path = tmp_path / "seed.json"
    seed_path.write_text(
        json.dumps([{"diseaseKey": "influenza"}]), encoding="utf-8"
    )
    monkeypatch.setattr(
        seed_firestore,
        "validate_seed_file",
        lambda _: {"valid": True, "criticalErrorCount": 0},
    )
    counts = run_seed(seed_path=seed_path, apply=False)
    assert counts.skipped == 1
    assert counts.created == 0
    assert counts.updated == 0
