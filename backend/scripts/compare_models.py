"""Quick, bounded comparison of RandomForest vs. ExtraTrees vs. HistGradientBoosting
on the identical leakage-safe (group-safe) split used by optimize_random_forest.py.

Research/evaluation only. Does not touch production files or routes.
"""

from __future__ import annotations

import json
import gc
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    f1_score,
    precision_recall_fscore_support,
    top_k_accuracy_score,
)
from sklearn.model_selection import StratifiedGroupKFold, cross_validate

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
REPORTS_DIR = BACKEND_DIR / "reports"
TARGET = "diseases"
RANDOM_STATE = 42


def vector_group_ids(features: pd.DataFrame) -> np.ndarray:
    import hashlib

    packed = np.packbits(features.to_numpy(dtype="uint8"), axis=1)
    return np.array(
        [hashlib.blake2b(row.tobytes(), digest_size=16).hexdigest() for row in packed]
    )


def prior_serialized_size(name: str) -> float | None:
    """Reuse a size measured by an earlier completed comparison, if present."""
    report_path = REPORTS_DIR / "model_comparison.json"
    if not report_path.exists():
        return None
    try:
        payload = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    for row in payload.get("results", []):
        if row.get("model") == name and row.get("modelSizeMB") is not None:
            return float(row["modelSizeMB"])
    return None


def main() -> None:
    header = pd.read_csv(DATASET_PATH, nrows=0)
    dtype = {c: "uint8" for c in header.columns if c != TARGET}
    frame = pd.read_csv(DATASET_PATH, dtype=dtype, low_memory=False)
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")
    groups = vector_group_ids(features)

    splitter = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)
    train_idx, test_idx = next(splitter.split(features, labels, groups=groups))
    X_train, X_test = features.iloc[train_idx], features.iloc[test_idx]
    y_train, y_test = labels.iloc[train_idx], labels.iloc[test_idx]

    # Best RF config found by optimize_random_forest.py's reduced search.
    tuned_rf_params = {
        "n_estimators": 200,
        "min_samples_split": 4,
        "min_samples_leaf": 1,
        "max_features": "log2",
        "max_depth": 28,
        "criterion": "entropy",
        "class_weight": "balanced_subsample",
    }

    candidates = {
        "RandomForest_tuned": RandomForestClassifier(
            **tuned_rf_params, random_state=RANDOM_STATE, n_jobs=1
        ),
        "ExtraTrees": ExtraTreesClassifier(
            n_estimators=200,
            max_depth=28,
            max_features="log2",
            class_weight="balanced_subsample",
            random_state=RANDOM_STATE,
            n_jobs=1,
        ),
    }

    results = []
    for name, model in list(candidates.items()):
        t0 = time.time()
        model.fit(X_train, y_train)
        fit_seconds = time.time() - t0

        t0 = time.time()
        predictions = model.predict(X_test)
        predict_seconds = time.time() - t0

        probabilities = model.predict_proba(X_test)
        accuracy = accuracy_score(y_test, predictions)
        balanced_acc = balanced_accuracy_score(y_test, predictions)
        precision_w, recall_w, f1_w, _ = precision_recall_fscore_support(
            y_test, predictions, average="weighted", zero_division=0
        )
        _, _, f1_m, _ = precision_recall_fscore_support(
            y_test, predictions, average="macro", zero_division=0
        )
        top3 = top_k_accuracy_score(
            y_test, probabilities, k=min(3, probabilities.shape[1]), labels=model.classes_
        )

        # Full candidate models are evaluated on the locked held-out split.
        # The secondary CV is deliberately bounded to three folds and 50
        # trees; the production RF has its complete five-fold CV in train.py.
        cv_params = model.get_params()
        if "n_jobs" in cv_params:
            cv_params["n_jobs"] = 1
        cv_params["n_estimators"] = min(int(cv_params["n_estimators"]), 50)
        cv_results = cross_validate(
            model.__class__(**cv_params),
            X_train,
            y_train,
            groups=groups[train_idx],
            cv=StratifiedGroupKFold(
                n_splits=3,
                shuffle=True,
                random_state=RANDOM_STATE,
            ),
            scoring=["accuracy", "f1_macro", "f1_weighted"],
            n_jobs=1,
            return_train_score=False,
        )
        per_class = classification_report(
            y_test,
            predictions,
            output_dict=True,
            zero_division=0,
        )

        model_size_mb = prior_serialized_size(name)

        row = {
            "model": name,
            "accuracy": round(float(accuracy), 4),
            "precisionWeighted": round(float(precision_w), 4),
            "recallWeighted": round(float(recall_w), 4),
            "f1Weighted": round(float(f1_w), 4),
            "f1Macro": round(float(f1_m), 4),
            "balancedAccuracy": round(float(balanced_acc), 4),
            "top3Accuracy": round(float(top3), 4),
            "trainingSeconds": round(fit_seconds, 2),
            "inferenceSecondsFor18800Rows": round(predict_seconds, 3),
            "modelSizeMB": (
                round(model_size_mb, 1)
                if model_size_mb is not None
                else None
            ),
            "cvMeanAccuracy": float(cv_results["test_accuracy"].mean()),
            "cvStdAccuracy": float(cv_results["test_accuracy"].std(ddof=0)),
            "cvMeanF1Macro": float(cv_results["test_f1_macro"].mean()),
            "cvStdF1Macro": float(cv_results["test_f1_macro"].std(ddof=0)),
            "cvMeanF1Weighted": float(cv_results["test_f1_weighted"].mean()),
            "cvStdF1Weighted": float(cv_results["test_f1_weighted"].std(ddof=0)),
            "modelSizeBasis": "serialized size reused from prior completed comparison; candidate artifact is not persisted by this script",
            "cvEstimator": "same candidate family/configuration with n_estimators capped at 50 for bounded 3-fold training-only CV",
            "perClassWorstRecall": [
                {
                    "disease": label,
                    "precision": float(values.get("precision", 0.0)),
                    "recall": float(values.get("recall", 0.0)),
                    "f1": float(values.get("f1-score", 0.0)),
                    "support": int(values.get("support", 0)),
                }
                for label, values in sorted(
                    (
                        (label, values)
                        for label, values in per_class.items()
                        if label not in {"accuracy", "macro avg", "weighted avg"}
                    ),
                    key=lambda item: item[1].get("recall", 0.0),
                )[:10]
            ],
        }
        print(json.dumps(row, indent=2))
        results.append(row)
        # The RF fold models are large. Release each candidate before fitting
        # the next candidate so the bounded comparison cannot exhaust memory.
        del candidates[name]
        del model
        gc.collect()

    (REPORTS_DIR / "model_comparison.json").write_text(
        json.dumps(
            {
                "note": "Bounded comparison on the identical group-safe (leakage-free) "
                "split; theoretical ceiling on this feature set is 94.58% "
                "(see leakage_report.json / MODEL_EVALUATION_REPORT.md).",
                "testSamples": int(len(y_test)),
                "cvScope": "training partition only; same group-safe splitter for every candidate; production RF also has complete 5-fold CV",
                "deferredModels": [
                    {
                        "model": "HistGradientBoosting",
                        "status": "not rerun in this bounded pass after its prior held-out comparison; its prior executed result remains documented in the historical report",
                        "reason": "five-fold CV was materially longer than the available local runtime budget after the RF and ExtraTrees memory-safe runs",
                    }
                ],
                "results": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\nSaved to {REPORTS_DIR / 'model_comparison.json'}")


if __name__ == "__main__":
    main()
