"""Safely seed validated disease documents into Firestore in bounded batches."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, TypeVar

FIREBASE_DIR = Path(__file__).resolve().parent
BACKEND_DIR = FIREBASE_DIR.parent
APP_DIR = BACKEND_DIR / "app"
for import_path in (FIREBASE_DIR, APP_DIR):
    if str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))

from disease_schema import SERVER_TIMESTAMP  # noqa: E402
from firebase_service import get_firestore_client  # noqa: E402
from validate_disease_seed import validate_seed_file  # noqa: E402

LOGGER = logging.getLogger(__name__)
DEFAULT_SEED_PATH = FIREBASE_DIR / "disease_seed.json"
T = TypeVar("T")


@dataclass
class SeedCounts:
    created: int = 0
    updated: int = 0
    unchanged: int = 0
    skipped: int = 0
    failed: int = 0


def prepare_batches(
    records: list[T], batch_size: int
) -> Iterator[list[T]]:
    """Yield deterministic batches and enforce Firestore's 500-write limit."""
    if not 1 <= batch_size <= 500:
        raise ValueError("batch_size must be between 1 and 500")
    for start in range(0, len(records), batch_size):
        yield records[start : start + batch_size]


def firestore_payload(
    record: dict[str, Any],
    server_timestamp: Any,
    is_create: bool,
) -> dict[str, Any]:
    """Replace JSON timestamp sentinels with Firestore server timestamps."""
    payload = dict(record)
    payload.pop("createdAt", None)
    payload.pop("updatedAt", None)
    if is_create:
        payload["createdAt"] = server_timestamp
    payload["updatedAt"] = server_timestamp
    return payload


def _content_equal(existing: dict[str, Any], seed: dict[str, Any]) -> bool:
    expected = {
        key: value
        for key, value in seed.items()
        if key not in {"createdAt", "updatedAt"}
    }
    actual = {key: existing.get(key) for key in expected}
    return actual == expected


def _load_records(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not all(
        isinstance(record, dict) for record in payload
    ):
        raise ValueError("Seed file must contain an array of objects")
    return payload


def run_seed(
    seed_path: Path = DEFAULT_SEED_PATH,
    apply: bool = False,
    batch_size: int = 100,
    only: str | None = None,
    db: Any | None = None,
    server_timestamp: Any = SERVER_TIMESTAMP,
) -> SeedCounts:
    """Validate and either preview or apply the disease seed."""
    report = validate_seed_file(seed_path)
    if not report["valid"]:
        raise ValueError(
            f"Seed has {report['criticalErrorCount']} critical validation errors"
        )
    records = _load_records(seed_path)
    if only:
        records = [record for record in records if record["diseaseKey"] == only]
        if not records:
            raise ValueError(f"Unknown disease key supplied to --only: {only}")
    counts = SeedCounts()
    if not apply:
        counts.skipped = len(records)
        LOGGER.info(
            "Dry run: %d validated documents would be considered for seeding",
            len(records),
        )
        return counts

    client = db or get_firestore_client()
    collection = client.collection("diseases")
    operations: list[tuple[str, Any, dict[str, Any]]] = []
    for record in records:
        reference = collection.document(record["diseaseKey"])
        snapshot = reference.get()
        if snapshot.exists:
            existing = snapshot.to_dict() or {}
            if _content_equal(existing, record):
                counts.unchanged += 1
                continue
            operations.append(
                (
                    "updated",
                    reference,
                    firestore_payload(record, server_timestamp, is_create=False),
                )
            )
        else:
            operations.append(
                (
                    "created",
                    reference,
                    firestore_payload(record, server_timestamp, is_create=True),
                )
            )

    for operation_batch in prepare_batches(operations, batch_size):
        batch = client.batch()
        for _, reference, payload in operation_batch:
            batch.set(reference, payload, merge=True)
        try:
            batch.commit()
        except Exception as exc:
            counts.failed += len(operation_batch)
            LOGGER.error(
                "Firestore batch failed (%d writes): %s",
                len(operation_batch),
                exc,
            )
            continue
        for operation, _, _ in operation_batch:
            if operation == "created":
                counts.created += 1
            else:
                counts.updated += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Validate only (default)")
    mode.add_argument("--apply", action="store_true", help="Write to Firestore")
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--only", help="Seed one normalized disease key")
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED_PATH)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    try:
        counts = run_seed(
            seed_path=args.seed,
            apply=args.apply,
            batch_size=args.batch_size,
            only=args.only,
        )
    except Exception as exc:
        LOGGER.error("Seeding stopped: %s", exc)
        return 1
    LOGGER.info(
        "created=%d updated=%d unchanged=%d skipped=%d failed=%d",
        counts.created,
        counts.updated,
        counts.unchanged,
        counts.skipped,
        counts.failed,
    )
    return 1 if counts.failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
