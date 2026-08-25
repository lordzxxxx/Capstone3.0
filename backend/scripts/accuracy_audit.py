"""Audit reported model metrics without retraining or changing the artifact.

This is intentionally separate from the trainer. It gives reviewers a fast,
reproducible statistical readout even when the large model binary is stored
outside the working copy. It uses the checked-in training metrics for held-out
hit counts and recomputes the identical-vector ambiguity ceiling from the
processed dataset.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

import joblib
import pandas as pd

APP_DIR = Path(__file__).resolve().parents[1] / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from evaluation_metrics import (  # noqa: E402
    exact_vector_ambiguity_summary,
    multiclass_calibration_summary,
    statistical_metric_summary,
    top_k_successes,
)
from train import group_safe_split, vector_group_ids  # noqa: E402

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
METRICS_PATH = BACKEND_DIR / "models" / "training_metrics.json"
DEFAULT_MODEL_PATH = BACKEND_DIR / "models" / "disease_model.pkl"
MODEL_PATH = Path(os.getenv("MODEL_PATH", DEFAULT_MODEL_PATH)).expanduser().resolve()
OUTPUT_PATH = BACKEND_DIR / "reports" / "accuracy_statistics_audit.json"
TARGET = "diseases"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _reported_successes(
    metrics: dict[str, object],
    key: str,
    total: int,
) -> tuple[int, float]:
    """Recover an exact integer count from a persisted proportion."""
    value = float(metrics[key])
    successes = round(value * total)
    reconstructed = successes / total
    if abs(value - reconstructed) > 1e-8:
        raise ValueError(
            f"{key}={value} cannot be represented by an integer count over "
            f"test_records={total}"
        )
    return successes, value


def main() -> dict[str, object]:
    metrics = json.loads(METRICS_PATH.read_text(encoding="utf-8"))
    header = pd.read_csv(DATASET_PATH, nrows=0)
    dtype = {column: "uint8" for column in header.columns if column != TARGET}
    frame = pd.read_csv(DATASET_PATH, dtype=dtype, low_memory=False)
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")

    test_records = int(metrics["test_records"])
    top1_successes, recorded_top1 = _reported_successes(
        metrics, "accuracy", test_records
    )
    top2_successes, recorded_top2 = _reported_successes(
        metrics, "top2_accuracy", test_records
    )
    top3_successes, recorded_top3 = _reported_successes(
        metrics, "top3_accuracy", test_records
    )
    ambiguity = exact_vector_ambiguity_summary(features, labels)
    evaluation = statistical_metric_summary(
        total=test_records,
        top1_successes=top1_successes,
        top2_successes=top2_successes,
        top3_successes=top3_successes,
        class_count=int(labels.nunique()),
        ambiguity=ambiguity,
    )

    if MODEL_PATH.is_file():
        artifact_sha256 = _sha256(MODEL_PATH)
        groups = vector_group_ids(features)
        train_indices, test_indices = group_safe_split(features, labels, groups)
        model = joblib.load(MODEL_PATH)
        held_out_features = features.iloc[test_indices]
        held_out_labels = labels.iloc[test_indices]
        probabilities = model.predict_proba(held_out_features)
        recomputed_counts = {
            "top1": top_k_successes(
                held_out_labels,
                probabilities,
                model.classes_,
                1,
            ),
            "top2": top_k_successes(
                held_out_labels,
                probabilities,
                model.classes_,
                2,
            ),
            "top3": top_k_successes(
                held_out_labels,
                probabilities,
                model.classes_,
                3,
            ),
        }
        expected_counts = {
            "top1": top1_successes,
            "top2": top2_successes,
            "top3": top3_successes,
        }
        artifact_evaluation: dict[str, object] = {
            "status": "recomputed_from_saved_artifact",
            "artifact_sha256": artifact_sha256,
            "matches_persisted_artifact_sha256": artifact_sha256
            == metrics.get("model_sha256"),
            "training_records": int(len(train_indices)),
            "test_records": int(len(test_indices)),
            "train_test_exact_vector_overlap_groups": int(
                len(set(groups[train_indices]).intersection(groups[test_indices]))
            ),
            "recomputed_correct_counts": recomputed_counts,
            "matches_persisted_correct_counts": recomputed_counts == expected_counts,
            "calibration": multiclass_calibration_summary(
                held_out_labels,
                probabilities,
                model.classes_,
            ),
        }
    else:
        artifact_evaluation = {
            "status": "not_computed",
            "reason": (
                "The model artifact is absent. Accuracy uncertainty and dataset "
                "ambiguity remain auditable, but calibration requires saved "
                "held-out probabilities or the exact model artifact."
            ),
        }

    report: dict[str, object] = {
        "report": "accuracy_statistics_audit",
        "source": {
            "metrics": str(METRICS_PATH),
            "dataset": str(DATASET_PATH),
            "model_artifact_present": MODEL_PATH.exists(),
            "model_artifact": str(MODEL_PATH),
            "note": (
                "Held-out hit counts are reconstructed from the persisted "
                "proportions and test-record count; no retraining occurs."
            ),
        },
        "dataset_checks": {
            "records": int(len(frame)),
            "features": int(features.shape[1]),
            "classes": int(labels.nunique()),
            "matches_training_metrics": {
                "records": int(len(frame)) == int(metrics["dataset_records"]),
                "features": int(features.shape[1]) == int(metrics["dataset_features"]),
                "classes": int(labels.nunique()) == int(metrics["dataset_classes"]),
            },
        },
        "recorded_proportions": {
            "top1_accuracy": recorded_top1,
            "top2_coverage": recorded_top2,
            "top3_coverage": recorded_top3,
        },
        "evaluation": evaluation,
        "artifact_evaluation": artifact_evaluation,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return report


if __name__ == "__main__":
    main()
