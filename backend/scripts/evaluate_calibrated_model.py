"""Fit calibration on training OOF predictions, then evaluate test once.

The persisted Random Forest is externally provisioned and checksum-verified.
No rows are generated, copied, relabeled, or moved between the locked group-
safe training and test partitions.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

import numpy as np
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    precision_recall_fscore_support,
)
from sklearn.model_selection import StratifiedGroupKFold

BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_DIR = BACKEND_DIR / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from evaluation_metrics import (  # noqa: E402
    apply_temperature_scaling,
    fit_temperature_from_oof,
    multiclass_calibration_summary,
)
from train import (  # noqa: E402
    DATASET_PATH,
    RANDOM_STATE,
    build_estimator,
    group_safe_split,
    load_training_data,
    sha256_file,
    vector_group_ids,
)
from verified_artifact import load_verified_joblib  # noqa: E402

METRICS_PATH = BACKEND_DIR / "models" / "training_metrics.json"
CALIBRATION_PATH = BACKEND_DIR / "models" / "disease_model_v4.calibration.json"
REPORT_PATH = BACKEND_DIR / "reports" / "calibrated_model_evaluation.json"


def _classification_metrics(labels: Any, predictions: np.ndarray) -> dict[str, float]:
    weighted = precision_recall_fscore_support(
        labels, predictions, average="weighted", zero_division=0
    )
    macro = precision_recall_fscore_support(
        labels, predictions, average="macro", zero_division=0
    )
    return {
        "accuracy": float(accuracy_score(labels, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(labels, predictions)),
        "precision_weighted": float(weighted[0]),
        "recall_weighted": float(weighted[1]),
        "f1_weighted": float(weighted[2]),
        "precision_macro": float(macro[0]),
        "recall_macro": float(macro[1]),
        "f1_macro": float(macro[2]),
    }


def main() -> dict[str, Any]:
    metrics = json.loads(METRICS_PATH.read_text(encoding="utf-8"))
    model_path = Path(
        os.getenv("MODEL_PATH", BACKEND_DIR / "models" / "disease_model.pkl")
    ).expanduser().resolve()
    expected_sha256 = os.getenv(
        "MODEL_EXPECTED_SHA256", str(metrics.get("model_sha256", ""))
    )
    model = load_verified_joblib(model_path, expected_sha256)

    features, labels = load_training_data()
    groups = vector_group_ids(features)
    train_indices, test_indices = group_safe_split(features, labels, groups)
    x_train = features.iloc[train_indices]
    y_train = labels.iloc[train_indices]
    train_groups = groups[train_indices]
    x_test = features.iloc[test_indices]
    y_test = labels.iloc[test_indices]

    classes = np.asarray(model.classes_)
    class_index = {label: index for index, label in enumerate(classes)}
    oof_probabilities = np.zeros((len(x_train), len(classes)), dtype=float)
    oof_seen = np.zeros(len(x_train), dtype=np.uint8)
    fold_details: list[dict[str, int]] = []
    splitter = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=RANDOM_STATE,
    )
    for fold, (fit_indices, validation_indices) in enumerate(
        splitter.split(x_train, y_train, groups=train_groups), start=1
    ):
        overlap = set(train_groups[fit_indices]).intersection(
            set(train_groups[validation_indices])
        )
        if overlap:
            raise RuntimeError(f"Fold {fold} leaked {len(overlap)} vector groups")
        estimator = build_estimator()
        estimator.fit(x_train.iloc[fit_indices], y_train.iloc[fit_indices])
        fold_probabilities = estimator.predict_proba(
            x_train.iloc[validation_indices]
        )
        for source_column, label in enumerate(estimator.classes_):
            oof_probabilities[validation_indices, class_index[label]] = (
                fold_probabilities[:, source_column]
            )
        oof_seen[validation_indices] += 1
        fold_details.append(
            {
                "fold": fold,
                "training_records": int(len(fit_indices)),
                "validation_records": int(len(validation_indices)),
                "group_overlap": 0,
            }
        )
    if not np.all(oof_seen == 1):
        raise RuntimeError("Every training row must receive exactly one OOF prediction")

    temperature_fit = fit_temperature_from_oof(
        y_train,
        oof_probabilities,
        classes,
    )
    temperature = float(temperature_fit["temperature"])

    # The untouched test partition is accessed only after temperature is fixed.
    test_probabilities = model.predict_proba(x_test)
    calibrated_probabilities = apply_temperature_scaling(
        test_probabilities,
        temperature,
    )
    predictions_before = classes[np.argmax(test_probabilities, axis=1)]
    predictions_after = classes[np.argmax(calibrated_probabilities, axis=1)]
    before = {
        **_classification_metrics(y_test, predictions_before),
        **multiclass_calibration_summary(y_test, test_probabilities, classes),
    }
    after = {
        **_classification_metrics(y_test, predictions_after),
        **multiclass_calibration_summary(y_test, calibrated_probabilities, classes),
    }
    if not np.array_equal(predictions_before, predictions_after):
        raise RuntimeError("Temperature scaling unexpectedly changed class ranking")

    calibration = {
        "model_version": metrics.get("model_version"),
        "model_sha256": expected_sha256,
        "dataset_sha256": sha256_file(DATASET_PATH),
        "method": "single_temperature_log_probability_scaling",
        "temperature": temperature,
        "fit": temperature_fit,
        "folds": fold_details,
        "test_access_policy": (
            "Temperature selected from training-partition OOF predictions only; "
            "untouched group-safe test evaluated once after selection."
        ),
    }
    report = {
        "methodology": calibration,
        "training_records": int(len(train_indices)),
        "test_records": int(len(test_indices)),
        "train_test_exact_vector_overlap_groups": 0,
        "before_calibration": before,
        "after_calibration": after,
        "difference_after_minus_before": {
            key: float(after[key]) - float(before[key])
            for key in (
                "accuracy",
                "balanced_accuracy",
                "precision_weighted",
                "recall_weighted",
                "f1_weighted",
                "precision_macro",
                "recall_macro",
                "f1_macro",
                "multiclass_log_loss",
                "multiclass_brier_score",
                "top_label_expected_calibration_error",
            )
        },
        "clinical_validity_statement": (
            "Probability calibration on this dataset does not establish medical "
            "certainty, Philippine representativeness, or clinical validity."
        ),
    }
    CALIBRATION_PATH.write_text(json.dumps(calibration, indent=2), encoding="utf-8")
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return report


if __name__ == "__main__":
    main()
