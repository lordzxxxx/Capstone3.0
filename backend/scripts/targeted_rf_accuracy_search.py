"""Run a small Random Forest search scored for accuracy on training data only."""

from __future__ import annotations

import json
import sys
from pathlib import Path

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
REPORT_PATH = BACKEND_DIR / "reports" / "rf_accuracy_targeted_search.json"
TARGET = "diseases"
RANDOM_STATE = 42

sys.path.insert(0, str(BACKEND_DIR / "app"))


def estimator(params: dict[str, object]) -> RandomForestClassifier:
    return RandomForestClassifier(
        **params,
        bootstrap=True,
        random_state=RANDOM_STATE,
        n_jobs=-1,
    )


def main() -> int:
    from train import group_safe_split, vector_group_ids

    frame = pd.read_csv(DATASET_PATH, low_memory=False)
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")
    groups = vector_group_ids(features)
    train_idx, test_idx = group_safe_split(features, labels, groups)
    x_train = features.iloc[train_idx]
    y_train = labels.iloc[train_idx]

    candidates: list[dict[str, object]] = [
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 300,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 200,
            "criterion": "gini",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 32,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 2,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "sqrt",
            "class_weight": "balanced_subsample",
        },
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 1,
            "max_features": "log2",
            "class_weight": None,
        },
        {
            "n_estimators": 200,
            "criterion": "entropy",
            "max_depth": 28,
            "min_samples_split": 4,
            "min_samples_leaf": 2,
            "max_features": "log2",
            "class_weight": "balanced_subsample",
        },
    ]

    cv = StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=RANDOM_STATE)
    rows: list[dict[str, object]] = []
    for params in candidates:
        result = cross_validate(
            estimator(params),
            x_train,
            y_train,
            groups=groups[train_idx],
            cv=cv,
            scoring=["accuracy", "f1_macro", "f1_weighted", "balanced_accuracy"],
            n_jobs=1,
            return_train_score=False,
        )
        rows.append(
            {
                "params": params,
                "cv_mean_accuracy": float(result["test_accuracy"].mean()),
                "cv_std_accuracy": float(result["test_accuracy"].std(ddof=0)),
                "cv_mean_balanced_accuracy": float(result["test_balanced_accuracy"].mean()),
                "cv_mean_f1_macro": float(result["test_f1_macro"].mean()),
                "cv_mean_f1_weighted": float(result["test_f1_weighted"].mean()),
            }
        )

    selected = max(
        rows,
        key=lambda row: (
            float(row["cv_mean_accuracy"]),
            float(row["cv_mean_f1_weighted"]),
        ),
    )
    selected_model = estimator(selected["params"]).fit(x_train, y_train)
    predictions = selected_model.predict(features.iloc[test_idx])
    probabilities = selected_model.predict_proba(features.iloc[test_idx])
    y_test = labels.iloc[test_idx]
    selected["locked_test_evaluation_after_cv_selection"] = {
        "accuracy": float(accuracy_score(y_test, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(y_test, predictions)),
        "f1_macro": float(f1_score(y_test, predictions, average="macro", zero_division=0)),
        "f1_weighted": float(f1_score(y_test, predictions, average="weighted", zero_division=0)),
        "top2_accuracy": float(top_k_accuracy_score(y_test, probabilities, k=2, labels=selected_model.classes_)),
        "top3_accuracy": float(top_k_accuracy_score(y_test, probabilities, k=3, labels=selected_model.classes_)),
    }
    report = {
        "generated_at": pd.Timestamp.now(tz="UTC").isoformat(),
        "purpose": "Training-only accuracy-scored targeted RF search; no production artifact changed.",
        "dataset_records": int(len(frame)),
        "feature_count": int(features.shape[1]),
        "train_records": int(len(train_idx)),
        "locked_test_records": int(len(test_idx)),
        "cv": "3-fold StratifiedGroupKFold on training partition only",
        "selection_metric": "cv_mean_accuracy, then cv_mean_f1_weighted",
        "selected": selected,
        "all_candidates": rows,
        "adoption_status": "not promoted; production remains the previously validated RF artifact",
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": str(REPORT_PATH),
        "selected_params": selected["params"],
        "cv_mean_accuracy": selected["cv_mean_accuracy"],
        "locked_test_accuracy": selected["locked_test_evaluation_after_cv_selection"]["accuracy"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
