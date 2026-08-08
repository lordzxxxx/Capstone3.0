"""Run controlled dataset experiments without replacing the baseline model."""

from __future__ import annotations

import json
import logging
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split

from pipeline_utils import (
    BACKEND_DIR,
    DISEASE_COLUMN,
    MAPPINGS_DIR,
    RAW_DIR,
    configure_logging,
    load_mapping,
    prepare_wide_dataset,
)

LOGGER = configure_logging(__name__)
ORIGINAL_PATH = RAW_DIR / "Diseases_and_Symptoms_dataset.csv"
LEGACY_MERGED_PATH = (
    BACKEND_DIR / "dataset" / "excluded" / "legacy_merged_dataset.csv"
)
REPORTS_DIR = BACKEND_DIR / "reports"
EXPERIMENT_MODELS_DIR = BACKEND_DIR / "models" / "experiments"
CSV_REPORT_PATH = REPORTS_DIR / "dataset_comparison.csv"
JSON_REPORT_PATH = REPORTS_DIR / "dataset_comparison.json"
KAGGLE_ROWS = 100_000
TEST_SIZE = 0.20
RANDOM_STATE = 42
TARGET = DISEASE_COLUMN

MISSING_FEATURE_LIMITATION = (
    "For union features, a source without a symptom column is encoded as 0 only "
    "to satisfy the model schema. That value means unavailable/not recorded and "
    "must not be interpreted as clinically confirmed absence."
)
KAGGLE_SCHEMA_LIMITATION = (
    "The standalone Kaggle CSV was unavailable. Its 100,000 rows were recovered "
    "from the validated first segment of excluded/legacy_merged_dataset.csv. "
    "Kaggle feature availability is inferred from columns containing at least "
    "one nonzero value."
)


@dataclass
class ExperimentResult:
    """Serializable metrics and provenance for one controlled experiment."""

    experiment: str
    model_file: str
    record_count: int
    disease_count: int
    symptom_count: int
    accuracy: float
    balanced_accuracy: float
    macro_precision: float
    macro_recall: float
    macro_f1: float
    weighted_f1: float
    smallest_class_size: int
    largest_class_size: int
    training_duration_seconds: float
    excluded_singleton_records: int
    per_class_recall: dict[str, float]
    minimum_class_recall: float
    median_class_recall: float
    limitation: str


def _read_and_prepare(path: Path, nrows: int | None = None) -> pd.DataFrame:
    """Read one wide CSV and apply shared disease/symptom normalization."""
    disease_mapping = load_mapping(MAPPINGS_DIR / "disease_mapping.json")
    symptom_mapping = load_mapping(MAPPINGS_DIR / "symptom_mapping.json")
    frame = pd.read_csv(path, nrows=nrows, low_memory=False)
    if TARGET not in frame.columns:
        raise ValueError(f"Expected '{TARGET}' in {path}")
    prepared = prepare_wide_dataset(
        frame,
        TARGET,
        disease_mapping,
        symptom_mapping,
    )
    prepared = prepared.loc[
        ~prepared[TARGET].isin({"", "nan", "none", "null"})
    ].reset_index(drop=True)
    return prepared


def _validate_composite_boundary(original: pd.DataFrame) -> None:
    """Prove that the legacy composite tail is the original dataset."""
    merged_header = pd.read_csv(LEGACY_MERGED_PATH, nrows=0)
    with LEGACY_MERGED_PATH.open("r", encoding="utf-8") as handle:
        merged_rows = sum(1 for _ in handle) - 1
    expected = KAGGLE_ROWS + len(original)
    if merged_rows != expected:
        raise ValueError(
            f"Cannot recover Kaggle segment: expected {expected:,} composite rows, "
            f"found {merged_rows:,}"
        )
    # Validate representative boundary rows without loading the duplicate tail.
    original_raw = pd.read_csv(ORIGINAL_PATH, nrows=1)
    tail_first = pd.read_csv(
        LEGACY_MERGED_PATH,
        skiprows=range(1, KAGGLE_ROWS + 1),
        nrows=1,
    )
    common = [column for column in original_raw.columns if column in merged_header]
    if not original_raw[common].astype(str).iloc[0].equals(
        tail_first[common].astype(str).iloc[0]
    ):
        raise ValueError("Composite row 100,000 does not match the original dataset")
    LOGGER.info(
        "Validated composite layout: %s Kaggle rows followed by %s original rows",
        f"{KAGGLE_ROWS:,}",
        f"{len(original):,}",
    )


def load_experiment_datasets() -> dict[str, pd.DataFrame]:
    """Build original, Kaggle, union, and common-feature experiment frames."""
    LOGGER.info("Loading original clean dataset")
    original = _read_and_prepare(ORIGINAL_PATH)
    _validate_composite_boundary(original)
    LOGGER.info("Recovering the validated 100,000-row Kaggle segment")
    kaggle = _read_and_prepare(LEGACY_MERGED_PATH, nrows=KAGGLE_ROWS)

    original_features = set(original.columns) - {TARGET}
    # The old union CSV does not preserve source schema metadata. A nonzero value
    # is the only auditable evidence that a column existed in the Kaggle source.
    kaggle_features = {
        column
        for column in kaggle.columns
        if column != TARGET and bool(kaggle[column].ne(0).any())
    }
    original = original[[TARGET, *sorted(original_features)]]
    kaggle = kaggle[[TARGET, *sorted(kaggle_features)]]

    union_features = sorted(original_features | kaggle_features)
    common_features = sorted(original_features & kaggle_features)
    if not common_features:
        raise ValueError("The original and Kaggle datasets have no common symptoms")

    merged_union = pd.concat(
        [
            original.reindex(columns=[TARGET, *union_features], fill_value=0),
            kaggle.reindex(columns=[TARGET, *union_features], fill_value=0),
        ],
        ignore_index=True,
    )
    merged_common = pd.concat(
        [original[[TARGET, *common_features]], kaggle[[TARGET, *common_features]]],
        ignore_index=True,
    )
    LOGGER.info(
        "Feature schemas: original=%s, Kaggle=%s, union=%s, common=%s",
        f"{len(original_features):,}",
        f"{len(kaggle_features):,}",
        f"{len(union_features):,}",
        f"{len(common_features):,}",
    )
    return {
        "original_clean": original,
        "kaggle_100k": kaggle,
        "merged_union": merged_union,
        "merged_common_features": merged_common,
    }


def _eligible_for_stratification(
    frame: pd.DataFrame,
) -> tuple[pd.DataFrame, int]:
    """Exclude only singleton targets, which cannot be stratified into two sets."""
    counts = frame[TARGET].value_counts()
    singleton_labels = counts[counts.lt(2)].index
    excluded = int(frame[TARGET].isin(singleton_labels).sum())
    if excluded:
        LOGGER.warning(
            "Excluding %s singleton records across %s diseases before splitting",
            f"{excluded:,}",
            f"{len(singleton_labels):,}",
        )
    return (
        frame.loc[~frame[TARGET].isin(singleton_labels)].reset_index(drop=True),
        excluded,
    )


def _build_estimator() -> RandomForestClassifier:
    """Return the fixed estimator used unchanged in every experiment."""
    return RandomForestClassifier(
        n_estimators=300,
        random_state=RANDOM_STATE,
        n_jobs=-1,
        max_depth=24,
        max_leaf_nodes=4096,
        min_samples_leaf=2,
    )


def run_experiment(name: str, frame: pd.DataFrame) -> ExperimentResult:
    """Split, train, evaluate, and persist one experiment."""
    eligible, excluded = _eligible_for_stratification(frame)
    features = list(eligible.columns.drop(TARGET))
    x = eligible[features].astype("uint8")
    y = eligible[TARGET]
    counts = y.value_counts()
    x_train, x_test, y_train, y_test = train_test_split(
        x,
        y,
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
        stratify=y,
    )
    model = _build_estimator()
    LOGGER.info(
        "Training %s: %s records, %s diseases, %s symptoms",
        name,
        f"{len(eligible):,}",
        f"{y.nunique():,}",
        f"{len(features):,}",
    )
    started = time.perf_counter()
    model.fit(x_train, y_train)
    training_duration = time.perf_counter() - started
    predictions = model.predict(x_test)

    labels = list(model.classes_)
    recalls = recall_score(
        y_test,
        predictions,
        labels=labels,
        average=None,
        zero_division=0,
    )
    per_class_recall = {
        str(label): float(value) for label, value in zip(labels, recalls, strict=True)
    }
    recall_values = pd.Series(recalls)
    model_path = EXPERIMENT_MODELS_DIR / f"{name}.pkl"
    joblib.dump(model, model_path, compress=3)
    feature_path = EXPERIMENT_MODELS_DIR / f"{name}_features.json"
    feature_path.write_text(json.dumps(features, indent=2), encoding="utf-8")

    limitation = KAGGLE_SCHEMA_LIMITATION
    if name == "merged_union":
        limitation = f"{KAGGLE_SCHEMA_LIMITATION} {MISSING_FEATURE_LIMITATION}"
    elif name == "merged_common_features":
        limitation = (
            f"{KAGGLE_SCHEMA_LIMITATION} Restricting to common features avoids "
            "structural zero filling but discards source-specific symptoms."
        )
    result = ExperimentResult(
        experiment=name,
        model_file=str(model_path.relative_to(BACKEND_DIR)),
        record_count=len(eligible),
        disease_count=y.nunique(),
        symptom_count=len(features),
        accuracy=accuracy_score(y_test, predictions),
        balanced_accuracy=balanced_accuracy_score(y_test, predictions),
        macro_precision=precision_score(
            y_test, predictions, average="macro", zero_division=0
        ),
        macro_recall=recall_score(
            y_test, predictions, average="macro", zero_division=0
        ),
        macro_f1=f1_score(y_test, predictions, average="macro", zero_division=0),
        weighted_f1=f1_score(
            y_test, predictions, average="weighted", zero_division=0
        ),
        smallest_class_size=int(counts.min()),
        largest_class_size=int(counts.max()),
        training_duration_seconds=training_duration,
        excluded_singleton_records=excluded,
        per_class_recall=per_class_recall,
        minimum_class_recall=float(recall_values.min()),
        median_class_recall=float(recall_values.median()),
        limitation=limitation,
    )
    LOGGER.info(
        "%s complete in %.2fs: macro F1=%.4f, balanced accuracy=%.4f",
        name,
        training_duration,
        result.macro_f1,
        result.balanced_accuracy,
    )
    return result


def select_candidate(results: list[ExperimentResult]) -> ExperimentResult:
    """Rank by macro F1, balanced accuracy, then worst/median class recall."""
    return max(
        results,
        key=lambda result: (
            result.macro_f1,
            result.balanced_accuracy,
            result.minimum_class_recall,
            result.median_class_recall,
        ),
    )


def save_reports(results: list[ExperimentResult]) -> ExperimentResult:
    """Write concise CSV and detailed JSON reports, including recommendation."""
    candidate = select_candidate(results)
    detailed = [asdict(result) for result in results]
    csv_rows: list[dict[str, Any]] = []
    for result in detailed:
        row = {key: value for key, value in result.items() if key != "per_class_recall"}
        csv_rows.append(row)
    pd.DataFrame(csv_rows).to_csv(CSV_REPORT_PATH, index=False)
    payload = {
        "configuration": {
            "test_size": TEST_SIZE,
            "random_state": RANDOM_STATE,
            "stratified": True,
            "selection_order": [
                "macro_f1",
                "balanced_accuracy",
                "minimum_class_recall",
                "median_class_recall",
            ],
            "estimator": _build_estimator().get_params(),
        },
        "limitations": [KAGGLE_SCHEMA_LIMITATION, MISSING_FEATURE_LIMITATION],
        "experiments": detailed,
        "production_recommendation": {
            "experiment": candidate.experiment,
            "model_file": candidate.model_file,
            "fastapi": (
                f"Load {candidate.model_file} with its adjacent feature JSON."
            ),
            "flutter": (
                "Call the FastAPI prediction endpoint. A scikit-learn pickle is "
                "not directly executable in Flutter."
            ),
        },
    }
    JSON_REPORT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return candidate


def print_summary(results: list[ExperimentResult], candidate: ExperimentResult) -> None:
    """Print a compact comparison and explicit deployment recommendation."""
    columns = [
        "experiment",
        "record_count",
        "disease_count",
        "symptom_count",
        "accuracy",
        "balanced_accuracy",
        "macro_f1",
        "weighted_f1",
        "training_duration_seconds",
    ]
    print("\nDATASET COMPARISON")
    summary = pd.DataFrame([asdict(result) for result in results])[columns]
    print(summary.to_string(index=False))
    print("\nLIMITATION")
    print(MISSING_FEATURE_LIMITATION)
    print("\nPRODUCTION RECOMMENDATION")
    print(f"Dataset/model: {candidate.experiment} -> {candidate.model_file}")
    print("FastAPI: load the selected pickle and its adjacent feature JSON.")
    print("Flutter: call FastAPI; do not attempt to load the sklearn pickle directly.")


def main() -> None:
    """Execute all four experiments and save comparison artifacts."""
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    EXPERIMENT_MODELS_DIR.mkdir(parents=True, exist_ok=True)
    datasets = load_experiment_datasets()
    results = [run_experiment(name, frame) for name, frame in datasets.items()]
    candidate = save_reports(results)
    print_summary(results, candidate)
    LOGGER.info(
        "Saved comparison reports to %s and %s",
        CSV_REPORT_PATH,
        JSON_REPORT_PATH,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        LOGGER.exception("Dataset comparison failed")
        raise
