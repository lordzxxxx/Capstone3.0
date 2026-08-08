"""Train and evaluate the disease-prediction Random Forest model."""

from __future__ import annotations

import json
import logging
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    precision_recall_fscore_support,
)
from sklearn.model_selection import train_test_split

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
MODEL_DIR = BACKEND_DIR / "models"
MODEL_PATH = MODEL_DIR / "disease_model.pkl"
FEATURES_PATH = MODEL_DIR / "disease_model_features.json"
METRICS_PATH = MODEL_DIR / "training_metrics.json"
TARGET = "diseases"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%H:%M:%S",
)
LOGGER = logging.getLogger(__name__)


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
    return features, labels


def train_model() -> RandomForestClassifier:
    """Fit, evaluate, and persist the requested 300-tree classifier."""
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    LOGGER.info("Loading processed dataset from %s", DATASET_PATH)
    features, labels = load_training_data()
    x_train, x_test, y_train, y_test = train_test_split(
        features,
        labels,
        test_size=0.20,
        random_state=42,
        stratify=labels,
    )
    LOGGER.info(
        "Training on %s records; evaluating on %s records with %s features",
        f"{len(x_train):,}",
        f"{len(x_test):,}",
        f"{features.shape[1]:,}",
    )
    model = RandomForestClassifier(
        n_estimators=300,
        random_state=42,
        n_jobs=-1,
        max_depth=24,
        max_leaf_nodes=4096,
        min_samples_leaf=2,
    )
    model.fit(x_train, y_train)
    predictions = model.predict(x_test)

    accuracy = accuracy_score(y_test, predictions)
    precision, recall, f1, _ = precision_recall_fscore_support(
        y_test, predictions, average="weighted", zero_division=0
    )
    matrix = confusion_matrix(y_test, predictions, labels=model.classes_)
    report = classification_report(y_test, predictions, zero_division=0)
    print(f"Accuracy:  {accuracy:.4f}")
    print(f"Precision: {precision:.4f}")
    print(f"Recall:    {recall:.4f}")
    print(f"F1-score:  {f1:.4f}")
    print("\nConfusion Matrix:")
    print(matrix)
    print("\nClassification Report:")
    print(report)

    LOGGER.info("Saving trained model to %s", MODEL_PATH)
    # Compression prevents the enormous uncompressed artifact produced by the
    # legacy trainer while retaining the exact requested estimator.
    joblib.dump(model, MODEL_PATH, compress=3)
    FEATURES_PATH.write_text(
        json.dumps(list(features.columns), indent=2), encoding="utf-8"
    )
    metrics = {
        "accuracy": accuracy,
        "precision_weighted": precision,
        "recall_weighted": recall,
        "f1_weighted": f1,
        "training_records": len(x_train),
        "test_records": len(x_test),
        "features": features.shape[1],
        "diseases": labels.nunique(),
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    LOGGER.info("Training complete")
    return model


if __name__ == "__main__":
    train_model()
