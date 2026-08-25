"""Train and evaluate the disease-prediction Random Forest model."""

from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    precision_recall_fscore_support,
)
from sklearn.model_selection import StratifiedGroupKFold, cross_validate

try:
    from evaluation_metrics import (
        exact_vector_ambiguity_summary,
        multiclass_calibration_summary,
        statistical_metric_summary,
        top_k_successes,
    )
except ModuleNotFoundError:  # pragma: no cover - supports package invocation
    from backend.app.evaluation_metrics import (
        exact_vector_ambiguity_summary,
        multiclass_calibration_summary,
        statistical_metric_summary,
        top_k_successes,
    )

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
MODEL_DIR = BACKEND_DIR / "models"
MODEL_PATH = MODEL_DIR / "disease_model.pkl"
TEMP_MODEL_PATH = MODEL_DIR / ".disease_model.pkl.tmp"
FEATURES_PATH = MODEL_DIR / "disease_model_features.json"
METRICS_PATH = MODEL_DIR / "training_metrics.json"
MODEL_METADATA_PATH = MODEL_DIR / "disease_model_v4.metadata.json"
MODEL_REGISTRY_PATH = MODEL_DIR / "model_registry.json"
MODEL_VERSION = "disease_model_v4"
DATASET_VERSION = "merged_dataset_v3"
REPORTS_DIR = BACKEND_DIR / "reports"
CONFUSION_MATRIX_PATH = REPORTS_DIR / "disease_model_confusion_matrix.csv"
CLASS_REPORT_PATH = REPORTS_DIR / "disease_model_per_class_report.csv"
TARGET = "diseases"
TEST_SIZE = 0.20
RANDOM_STATE = 42

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%H:%M:%S",
)
LOGGER = logging.getLogger(__name__)


def sha256_file(path: Path) -> str:
    """Return a reproducible checksum for a persisted artifact."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_training_data(path: Path = DATASET_PATH) -> tuple[pd.DataFrame, pd.Series]:
    """Load only the processed master dataset and validate its model schema."""
    if not path.exists():
        raise FileNotFoundError(
            f"Master dataset not found: {path}. Run scripts/merge_datasets.py first."
        )
    header = pd.read_csv(path, nrows=0)
    if TARGET not in header.columns:
        raise ValueError(f"Required target column '{TARGET}' is missing from {path}")
    dtype = {column: "uint8" for column in header.columns if column != TARGET}
    frame = pd.read_csv(path, dtype=dtype, low_memory=False)
    if frame.empty:
        raise ValueError("The processed master dataset is empty")
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")
    if labels.nunique() < 2:
        raise ValueError("Training requires at least two diseases")
    if labels.value_counts().min() < 2:
        raise ValueError(
            "Every disease needs at least two rows for stratified splitting"
        )
    if features.columns.duplicated().any():
        raise ValueError("Training features contain duplicate column names")
    feature_values = set(features.to_numpy().ravel().tolist())
    if not feature_values.issubset({0, 1}):
        raise ValueError(
            f"Training features must be binary; found values {sorted(feature_values)[:10]}"
        )
    if labels.isna().any() or labels.str.strip().eq("").any():
        raise ValueError("Training labels contain missing or blank values")
    return features, labels


def vector_group_ids(features: pd.DataFrame) -> np.ndarray:
    """Return a stable group id for each identical binary feature vector."""
    packed = np.packbits(features.to_numpy(dtype="uint8"), axis=1)
    return np.array(
        [
            hashlib.blake2b(row.tobytes(), digest_size=16).hexdigest()
            for row in packed
        ]
    )


def group_safe_split(
    features: pd.DataFrame,
    labels: pd.Series,
    groups: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    """Create a stratified split that keeps identical inputs together."""
    splitter = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=RANDOM_STATE,
    )
    train_idx, test_idx = next(splitter.split(features, labels, groups=groups))
    overlap = set(groups[train_idx]).intersection(set(groups[test_idx]))
    if overlap:
        raise RuntimeError(
            "Group-safe split failed: identical feature vectors cross the "
            f"train/test boundary ({len(overlap)} groups)."
        )
    return train_idx, test_idx


def build_estimator() -> RandomForestClassifier:
    """Return the candidate selected by the saved leakage-safe experiments."""
    return RandomForestClassifier(
        n_estimators=200,
        criterion="entropy",
        max_depth=28,
        min_samples_split=4,
        min_samples_leaf=2,
        max_features="log2",
        class_weight="balanced_subsample",
        bootstrap=True,
        random_state=RANDOM_STATE,
        n_jobs=-1,
    )


def train_model() -> RandomForestClassifier:
    """Fit, evaluate, and persist the verified production classifier.

    The split is grouped by exact feature-vector identity. This prevents a
    repeated symptom presentation from appearing in both training and test
    data, while retaining legitimately distinct labels for the same symptom
    presentation as an explicitly measurable ambiguity in the evaluation.
    """
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    LOGGER.info("Loading processed dataset from %s", DATASET_PATH)
    features, labels = load_training_data()
    groups = vector_group_ids(features)
    train_idx, test_idx = group_safe_split(features, labels, groups)
    x_train = features.iloc[train_idx]
    x_test = features.iloc[test_idx]
    y_train = labels.iloc[train_idx]
    y_test = labels.iloc[test_idx]
    LOGGER.info(
        "Training on %s records; evaluating on %s records with %s features",
        f"{len(x_train):,}",
        f"{len(x_test):,}",
        f"{features.shape[1]:,}",
    )

    model = build_estimator()
    model.fit(x_train, y_train)
    predictions = model.predict(x_test)
    probabilities = model.predict_proba(x_test)

    accuracy = accuracy_score(y_test, predictions)
    balanced_accuracy = balanced_accuracy_score(y_test, predictions)
    precision, recall, f1, _ = precision_recall_fscore_support(
        y_test, predictions, average="weighted", zero_division=0
    )
    macro_precision, macro_recall, macro_f1, _ = (
        precision_recall_fscore_support(
            y_test, predictions, average="macro", zero_division=0
        )
    )
    top1_success_count = top_k_successes(
        y_test, probabilities, model.classes_, k=1
    )
    top2_success_count = top_k_successes(
        y_test, probabilities, model.classes_, k=min(2, probabilities.shape[1])
    )
    top3_success_count = top_k_successes(
        y_test, probabilities, model.classes_, k=min(3, probabilities.shape[1])
    )
    top1_accuracy = top1_success_count / len(y_test)
    top2_accuracy = top2_success_count / len(y_test)
    top3_accuracy = top3_success_count / len(y_test)
    statistical_evaluation = statistical_metric_summary(
        total=len(y_test),
        top1_successes=top1_success_count,
        top2_successes=top2_success_count,
        top3_successes=top3_success_count,
        class_count=int(labels.nunique()),
        ambiguity=exact_vector_ambiguity_summary(features, labels),
    )
    calibration_evaluation = multiclass_calibration_summary(
        y_test,
        probabilities,
        model.classes_,
    )
    matrix = confusion_matrix(y_test, predictions, labels=model.classes_)
    report = classification_report(
        y_test,
        predictions,
        labels=model.classes_,
        output_dict=True,
        zero_division=0,
    )

    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=RANDOM_STATE,
    )
    cv_results = cross_validate(
        build_estimator(),
        x_train,
        y_train,
        groups=groups[train_idx],
        cv=cv,
        scoring={
            "accuracy": "accuracy",
            "f1_weighted": "f1_weighted",
            "f1_macro": "f1_macro",
        },
        n_jobs=1,
        return_train_score=False,
    )

    pd.DataFrame(matrix, index=model.classes_, columns=model.classes_).to_csv(
        CONFUSION_MATRIX_PATH,
        index_label=TARGET,
    )
    pd.DataFrame(report).T.to_csv(CLASS_REPORT_PATH, index_label="label")

    feature_group_overlap = len(
        set(groups[train_idx]).intersection(set(groups[test_idx]))
    )
    print(f"Accuracy:  {accuracy:.4f}")
    print(f"Balanced accuracy: {balanced_accuracy:.4f}")
    print(f"Precision: {precision:.4f}")
    print(f"Recall:    {recall:.4f}")
    print(f"F1-score:  {f1:.4f}")
    print(f"Top-1 accuracy: {top1_accuracy:.4f}")
    print(f"Top-2 coverage: {top2_accuracy:.4f}")
    print(f"Top-3 coverage: {top3_accuracy:.4f}")
    print(
        "Top-label ECE: "
        f"{calibration_evaluation['top_label_expected_calibration_error']:.4f}"
    )

    LOGGER.info("Saving trained model to %s", MODEL_PATH)
    # Bzip2 compression keeps the checked-in artifact below GitHub's regular
    # 100 MB file limit without changing the fitted estimator.
    joblib.dump(model, TEMP_MODEL_PATH, compress=("bz2", 9))
    TEMP_MODEL_PATH.replace(MODEL_PATH)
    FEATURES_PATH.write_text(
        json.dumps(list(features.columns), indent=2), encoding="utf-8"
    )
    metrics = {
        "model_version": MODEL_VERSION,
        "dataset_version": DATASET_VERSION,
        "dataset_path": str(DATASET_PATH),
        "dataset_sha256": sha256_file(DATASET_PATH),
        "model_sha256": sha256_file(MODEL_PATH),
        "dataset_records": int(len(features)),
        "dataset_classes": int(labels.nunique()),
        "dataset_features": int(features.shape[1]),
        "target": TARGET,
        "split_method": (
            "StratifiedGroupKFold(n_splits=5) first fold; "
            "groups=identical_feature_vector"
        ),
        "test_size_requested": TEST_SIZE,
        "random_state": RANDOM_STATE,
        "feature_vector_groups": int(pd.Series(groups).nunique()),
        "train_test_feature_vector_overlap_groups": feature_group_overlap,
        "accuracy": float(accuracy),
        "balanced_accuracy": float(balanced_accuracy),
        "precision_weighted": float(precision),
        "recall_weighted": float(recall),
        "f1_weighted": float(f1),
        "precision_macro": float(macro_precision),
        "recall_macro": float(macro_recall),
        "f1_macro": float(macro_f1),
        "top2_accuracy": float(top2_accuracy),
        "top3_accuracy": float(top3_accuracy),
        "top1_correct": int(top1_success_count),
        "top2_correct": int(top2_success_count),
        "top3_correct": int(top3_success_count),
        "statistical_evaluation": statistical_evaluation,
        "calibration_evaluation": calibration_evaluation,
        "training_records": int(len(x_train)),
        "test_records": int(len(x_test)),
        "features": int(features.shape[1]),
        "diseases": int(labels.nunique()),
        "class_distribution": {
            str(label): int(count)
            for label, count in labels.value_counts().sort_index().items()
        },
        "model_parameters": build_estimator().get_params(),
        "cross_validation": {
            "method": "StratifiedGroupKFold",
            "folds": 5,
            "scope": "training_partition_only",
            "accuracy": [float(value) for value in cv_results["test_accuracy"]],
            "f1_weighted": [
                float(value) for value in cv_results["test_f1_weighted"]
            ],
            "f1_macro": [float(value) for value in cv_results["test_f1_macro"]],
            "mean_accuracy": float(cv_results["test_accuracy"].mean()),
            "std_accuracy": float(cv_results["test_accuracy"].std(ddof=0)),
            "mean_f1_weighted": float(cv_results["test_f1_weighted"].mean()),
            "std_f1_weighted": float(cv_results["test_f1_weighted"].std(ddof=0)),
            "mean_f1_macro": float(cv_results["test_f1_macro"].mean()),
            "std_f1_macro": float(cv_results["test_f1_macro"].std(ddof=0)),
        },
        "artifacts": {
            "model": str(MODEL_PATH),
            "features": str(FEATURES_PATH),
            "confusion_matrix": str(CONFUSION_MATRIX_PATH),
            "per_class_report": str(CLASS_REPORT_PATH),
            "provenance": str(
                DATASET_PATH.parent / "row_provenance.csv"
            ),
        },
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    metadata = {
        "model_version": MODEL_VERSION,
        "artifact": str(MODEL_PATH),
        "artifact_sha256": metrics["model_sha256"],
        "dataset_version": DATASET_VERSION,
        "dataset": {
            "path": str(DATASET_PATH),
            "sha256": metrics["dataset_sha256"],
            "records": int(len(features)),
            "features": int(features.shape[1]),
            "classes": int(labels.nunique()),
            "target": TARGET,
            "provenance": str(DATASET_PATH.parent / "row_provenance.csv"),
        },
        "training": {
            "trained_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
            "hyperparameters": metrics["model_parameters"],
            "split_method": metrics["split_method"],
            "held_out_metrics": {
                key: metrics[key]
                for key in (
                    "accuracy",
                    "balanced_accuracy",
                    "precision_macro",
                    "recall_macro",
                    "f1_macro",
                    "precision_weighted",
                    "recall_weighted",
                    "f1_weighted",
                    "top2_accuracy",
                    "top3_accuracy",
                )
            },
            "cross_validation": metrics["cross_validation"],
            "calibration_evaluation": metrics["calibration_evaluation"],
        },
        "production_status": "offline artifact; /predict remains disabled",
        "certification_status": "No ISO certification claim",
    }
    MODEL_METADATA_PATH.write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )
    registry = {
        "current_model_version": MODEL_VERSION,
        "current_artifact": str(MODEL_PATH),
        "versions": [
            {
                "model_version": MODEL_VERSION,
                "artifact": str(MODEL_PATH),
                "metadata": str(MODEL_METADATA_PATH),
                "status": "current offline evaluation artifact",
            },
            {
                "model_version": "disease_model_v3",
                "artifact": "backend/models/disease_model.pkl at commit 7011a10",
                "metadata": "backend/models/disease_model_v3.metadata.json",
                "status": (
                    "historical validated artifact; 89.3138% held-out accuracy, "
                    "229 features (merged_dataset_v2). Superseded by v4 after a "
                    "duplicate-column preprocessing fix (regurgitation/"
                    "regurgitation.1 collapsed into one feature) reduced the "
                    "feature count to 228; see DATASET_QUALITY_REPORT.md."
                ),
            },
            {
                "model_version": "disease_model_v2",
                "artifact": "backend/models/disease_model.pkl at commit bddde4c",
                "metadata": "backend/models/disease_model_v2.metadata.json",
                "status": "historical validated artifact; 89.2713% held-out accuracy with min_samples_leaf=1",
            },
            {
                "model_version": "disease_model_v1_historical",
                "artifact": "backend/models/disease_model.pkl before 2026-08-11",
                "status": "historical metrics retained in MODEL_EVALUATION_REPORT.md",
            },
        ],
    }
    MODEL_REGISTRY_PATH.write_text(
        json.dumps(registry, indent=2),
        encoding="utf-8",
    )
    LOGGER.info("Training complete")
    return model


if __name__ == "__main__":
    train_model()
