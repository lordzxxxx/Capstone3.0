"""Evaluate conservative, data-derived feature variants without test tuning.

Feature variants are selected using only the training partition's
StratifiedGroupKFold cross-validation.  The selected variant is then evaluated
once on the locked group-safe test partition for evidence; no variant is
promoted or written to the offline model artifact by this script.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    top_k_accuracy_score,
)
from sklearn.model_selection import StratifiedGroupKFold, cross_validate

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
REPORT_PATH = BACKEND_DIR / "reports" / "feature_variant_evaluation.json"
TARGET = "diseases"
RANDOM_STATE = 42


def vector_group_ids(features: pd.DataFrame) -> np.ndarray:
    packed = np.packbits(features.to_numpy(dtype="uint8"), axis=1)
    return np.array(
        [hashlib.blake2b(row.tobytes(), digest_size=16).hexdigest() for row in packed]
    )


def estimator() -> RandomForestClassifier:
    return RandomForestClassifier(
        n_estimators=200,
        criterion="entropy",
        max_depth=28,
        min_samples_split=4,
        min_samples_leaf=1,
        max_features="log2",
        class_weight="balanced_subsample",
        bootstrap=True,
        random_state=RANDOM_STATE,
        n_jobs=-1,
    )


def variants(features: pd.DataFrame) -> dict[str, pd.DataFrame]:
    """Return only transformations with no invented clinical values."""
    base = features.copy()
    count_variant = base.copy()
    count_variant["__derived_symptom_count"] = count_variant.sum(axis=1).astype("uint16")

    # The current quality audit found no constant or near-zero-variance
    # columns. Keep this explicit control variant so the result documents that
    # the quality gate was tested rather than silently assumed.
    variable_columns = [
        column
        for column in base.columns
        if base[column].nunique(dropna=False) > 1
        and not (
            base[column].mean() <= 0.0005 or base[column].mean() >= 0.9995
        )
    ]
    quality_filtered = base[variable_columns].copy()
    return {
        "baseline_229_binary_symptoms": base,
        "baseline_plus_derived_symptom_count": count_variant,
        "quality_filtered_features": quality_filtered,
    }


def metric_row(
    name: str,
    features: pd.DataFrame,
    train_idx: np.ndarray,
    labels: pd.Series,
    groups: np.ndarray,
) -> dict[str, object]:
    x_train = features.iloc[train_idx]
    y_train = labels.iloc[train_idx]
    train_groups = groups[train_idx]
    cv = cross_validate(
        estimator(),
        x_train,
        y_train,
        groups=train_groups,
        cv=StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=RANDOM_STATE),
        scoring=["accuracy", "f1_macro", "f1_weighted"],
        n_jobs=1,
        return_train_score=False,
    )
    row: dict[str, object] = {
        "variant": name,
        "feature_count": int(features.shape[1]),
        "cv_scope": "training partition only; 3-fold StratifiedGroupKFold grouped by exact input vector",
        "cv_mean_accuracy": float(cv["test_accuracy"].mean()),
        "cv_std_accuracy": float(cv["test_accuracy"].std(ddof=0)),
        "cv_mean_f1_macro": float(cv["test_f1_macro"].mean()),
        "cv_mean_f1_weighted": float(cv["test_f1_weighted"].mean()),
    }

    return row


def evaluate_selected_on_locked_test(
    features: pd.DataFrame,
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    labels: pd.Series,
) -> dict[str, float]:
    """Evaluate only the CV-selected variant on the held-out partition."""
    model = estimator().fit(features.iloc[train_idx], labels.iloc[train_idx])
    predictions = model.predict(features.iloc[test_idx])
    probabilities = model.predict_proba(features.iloc[test_idx])
    y_test = labels.iloc[test_idx]
    return {
        "accuracy": float(accuracy_score(y_test, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(y_test, predictions)),
        "f1_macro": float(f1_score(y_test, predictions, average="macro", zero_division=0)),
        "f1_weighted": float(f1_score(y_test, predictions, average="weighted", zero_division=0)),
        "top2_accuracy": float(top_k_accuracy_score(y_test, probabilities, k=2, labels=model.classes_)),
        "top3_accuracy": float(top_k_accuracy_score(y_test, probabilities, k=3, labels=model.classes_)),
    }


def main() -> int:
    frame = pd.read_csv(DATASET_PATH, low_memory=False)
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")
    groups = vector_group_ids(features)
    train_idx, test_idx = next(
        StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE).split(
            features, labels, groups=groups
        )
    )

    candidate_features = variants(features)
    candidates = [
        metric_row(name, variant, train_idx, labels, groups)
        for name, variant in candidate_features.items()
    ]

    selected = max(
        candidates,
        key=lambda row: (float(row["cv_mean_f1_weighted"]), float(row["cv_mean_accuracy"])),
    )
    selected["locked_test_evaluation_after_cv_selection"] = evaluate_selected_on_locked_test(
        candidate_features[str(selected["variant"])], train_idx, test_idx, labels
    )
    report = {
        "generated_at": pd.Timestamp.now(tz="UTC").isoformat(),
        "purpose": "Training-only CV selection of conservative feature transformations; no production artifact changed.",
        "dataset_records": int(len(frame)),
        "base_feature_count": int(features.shape[1]),
        "train_records": int(len(train_idx)),
        "locked_test_records": int(len(test_idx)),
        "selected_by_training_cv": selected["variant"],
        "adoption_status": "not_promoted; production remains the validated 229-feature artifact",
        "variants": candidates,
        "interpretation": "Derived symptom count adds no new clinical information and cannot raise the exact-vector theoretical ceiling; it was tested only as a possible tree-model representation improvement. Quality filtering is expected to be identical because no constant/near-zero-variance features were found.",
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": str(REPORT_PATH),
        "selected_by_training_cv": selected["variant"],
        "variants": [
            {
                "variant": row["variant"],
                "cv_mean_f1_weighted": row["cv_mean_f1_weighted"],
                "cv_mean_accuracy": row["cv_mean_accuracy"],
                "locked_test_accuracy": (
                    row.get("locked_test_evaluation_after_cv_selection", {}).get("accuracy")
                ),
            }
            for row in candidates
        ],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
