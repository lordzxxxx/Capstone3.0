"""Quick, bounded comparison of RandomForest vs. ExtraTrees vs. HistGradientBoosting
on the identical leakage-safe (group-safe) split used by optimize_random_forest.py.

Research/evaluation only. Does not touch production files or routes.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import (
    ExtraTreesClassifier,
    HistGradientBoostingClassifier,
    RandomForestClassifier,
)
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    precision_recall_fscore_support,
    top_k_accuracy_score,
)
from sklearn.model_selection import StratifiedGroupKFold

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
            **tuned_rf_params, random_state=RANDOM_STATE, n_jobs=-1
        ),
        "ExtraTrees": ExtraTreesClassifier(
            n_estimators=200,
            max_depth=28,
            max_features="log2",
            class_weight="balanced_subsample",
            random_state=RANDOM_STATE,
            n_jobs=-1,
        ),
        "HistGradientBoosting": HistGradientBoostingClassifier(
            max_depth=None,
            max_iter=200,
            random_state=RANDOM_STATE,
        ),
    }

    results = []
    for name, model in candidates.items():
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

        import joblib
        import io

        buffer = io.BytesIO()
        joblib.dump(model, buffer, compress=3)
        model_size_mb = len(buffer.getvalue()) / (1024 * 1024)

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
            "modelSizeMB": round(model_size_mb, 1),
        }
        print(json.dumps(row, indent=2))
        results.append(row)

    (REPORTS_DIR / "model_comparison.json").write_text(
        json.dumps(
            {
                "note": "Bounded comparison on the identical group-safe (leakage-free) "
                "split; theoretical ceiling on this feature set is 94.58% "
                "(see leakage_report.json / MODEL_EVALUATION_REPORT.md).",
                "testSamples": int(len(y_test)),
                "results": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\nSaved to {REPORTS_DIR / 'model_comparison.json'}")


if __name__ == "__main__":
    main()
