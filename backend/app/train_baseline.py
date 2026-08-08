from pathlib import Path
import time

import joblib
import pandas as pd

from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split


BASE_DIR = Path(__file__).resolve().parent
BACKEND_DIR = BASE_DIR.parent

DATASET_PATH = (
    BACKEND_DIR
    / "dataset"
    / "raw"
    / "Diseases_and_Symptoms_dataset.csv"
)

MODEL_DIR = BACKEND_DIR / "models" / "experiments"
MODEL_DIR.mkdir(parents=True, exist_ok=True)

MODEL_PATH = MODEL_DIR / "raw_baseline.pkl"


def main() -> None:
    print("Loading raw baseline dataset...")

    df = pd.read_csv(DATASET_PATH, low_memory=False)

    if "diseases" not in df.columns:
        raise ValueError("The dataset does not contain a 'diseases' column.")

    df["diseases"] = (
        df["diseases"]
        .astype(str)
        .str.strip()
        .str.lower()
    )

    X = df.drop(columns=["diseases"])
    y = df["diseases"]

    if not all(dtype.kind in "biufc" for dtype in X.dtypes):
        non_numeric = X.select_dtypes(exclude="number").columns.tolist()
        raise ValueError(
            f"Non-numeric feature columns found: {non_numeric[:10]}"
        )

    print(f"Records: {len(df):,}")
    print(f"Diseases: {y.nunique():,}")
    print(f"Symptoms: {X.shape[1]:,}")

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.20,
        random_state=42,
        stratify=y,
    )

    model = RandomForestClassifier(
        n_estimators=300,
        random_state=42,
        n_jobs=-1,
    )

    print("Training raw baseline model...")
    start = time.perf_counter()

    model.fit(X_train, y_train)

    elapsed = time.perf_counter() - start

    predictions = model.predict(X_test)

    accuracy = accuracy_score(y_test, predictions)
    balanced_accuracy = balanced_accuracy_score(y_test, predictions)
    macro_precision = precision_score(
        y_test,
        predictions,
        average="macro",
        zero_division=0,
    )
    macro_recall = recall_score(
        y_test,
        predictions,
        average="macro",
        zero_division=0,
    )
    macro_f1 = f1_score(
        y_test,
        predictions,
        average="macro",
        zero_division=0,
    )

    print("\nEvaluation")
    print("=" * 50)
    print(f"Accuracy:          {accuracy:.4f}")
    print(f"Balanced accuracy: {balanced_accuracy:.4f}")
    print(f"Macro precision:   {macro_precision:.4f}")
    print(f"Macro recall:      {macro_recall:.4f}")
    print(f"Macro F1:          {macro_f1:.4f}")
    print(f"Training time:     {elapsed:.2f} seconds")

    print("\nClassification report:")
    print(
        classification_report(
            y_test,
            predictions,
            zero_division=0,
        )
    )

    joblib.dump(model, MODEL_PATH)

    print(f"\nBaseline model saved to: {MODEL_PATH}")


if __name__ == "__main__":
    main()