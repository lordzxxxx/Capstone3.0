"""Leakage-safe Random Forest optimization experiment.

This is a research/evaluation script. It does NOT modify the production
model (`backend/models/disease_model.pkl`), the production feature list,
or any FastAPI route. `POST /predict` stays disabled regardless of this
script's results (see backend/app/api.py).

What this script does, in order:
  1. Load the existing processed dataset (dataset/processed/merged_dataset.csv)
     -- the same file train.py uses. No rows are fabricated or duplicated.
  2. Detect rows that share an identical 229-symptom feature vector with a
     different disease label ("label-conflict" rows) and rows that share an
     identical feature vector with the SAME label (harmless duplicates from
     multiple source records). Both are reported for the dataset-quality
     report.
  3. Split train/test using StratifiedGroupKFold keyed on the feature-vector
     identity, so that no exact feature vector can appear in both the
     training set and the test set (the production split, a plain
     `train_test_split`, does not guarantee this -- 1,485 rows were found to
     leak across its train/test boundary; see reports/leakage_report.json).
  4. Reproduce the production hyperparameters on this leakage-safe split as
     an apples-to-apples baseline.
  5. Run RandomizedSearchCV (stratified-group CV) on the training portion
     only to search for a better RandomForestClassifier configuration.
  6. Evaluate the tuned model exactly once on the held-out test portion.
  7. Run stratified k-fold cross-validation of the tuned hyperparameters as
     a robustness check.
  8. Save every artifact (metrics, confusion matrix, per-class report,
     search results, the tuned model itself) under backend/reports/ and
     backend/models/experiments/ -- never overwriting the production files.
"""

from __future__ import annotations

import hashlib
import json
import time
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
    f1_score,
    precision_recall_fscore_support,
    top_k_accuracy_score,
)
from sklearn.model_selection import (
    RandomizedSearchCV,
    StratifiedGroupKFold,
    cross_validate,
)

BACKEND_DIR = Path(__file__).resolve().parents[1]
DATASET_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
REPORTS_DIR = BACKEND_DIR / "reports"
EXPERIMENTS_DIR = BACKEND_DIR / "models" / "experiments"
TARGET = "diseases"
RANDOM_STATE = 42

REPORTS_DIR.mkdir(parents=True, exist_ok=True)
EXPERIMENTS_DIR.mkdir(parents=True, exist_ok=True)


def load_dataset() -> tuple[pd.DataFrame, pd.Series]:
    header = pd.read_csv(DATASET_PATH, nrows=0)
    dtype = {column: "uint8" for column in header.columns if column != TARGET}
    frame = pd.read_csv(DATASET_PATH, dtype=dtype, low_memory=False)
    features = frame.drop(columns=[TARGET])
    labels = frame[TARGET].astype("string")
    return features, labels


def vector_group_ids(features: pd.DataFrame) -> np.ndarray:
    """Deterministic group id per unique 229-length binary feature vector."""
    packed = np.packbits(features.to_numpy(dtype="uint8"), axis=1)
    return np.array(
        [hashlib.blake2b(row.tobytes(), digest_size=16).hexdigest() for row in packed]
    )


def analyze_leakage_and_conflicts(
    features: pd.DataFrame, labels: pd.Series, groups: np.ndarray
) -> dict:
    frame = features.copy()
    frame["__disease__"] = labels.to_numpy()
    frame["__group__"] = groups

    group_sizes = frame.groupby("__group__").size()
    duplicated_groups = group_sizes[group_sizes > 1]
    rows_in_duplicated_groups = int(duplicated_groups.sum())

    group_label_nunique = frame.groupby("__group__")["__disease__"].nunique()
    conflicting_groups = group_label_nunique[group_label_nunique > 1]
    rows_in_conflicting_groups = int(
        frame["__group__"].isin(conflicting_groups.index).sum()
    )

    # Example conflicts for the report: which diseases get confused for an
    # identical symptom presentation.
    examples = []
    for group_id in conflicting_groups.index[:15]:
        diseases = sorted(
            frame.loc[frame["__group__"] == group_id, "__disease__"].unique().tolist()
        )
        examples.append({"sharedSymptomVectorGroup": group_id, "diseases": diseases})

    return {
        "totalRows": int(len(frame)),
        "uniqueFeatureVectorGroups": int(group_sizes.shape[0]),
        "rowsSharingAVectorWithAnotherRow": rows_in_duplicated_groups,
        "vectorGroupsWithMultipleDiseaseLabels": int(conflicting_groups.shape[0]),
        "rowsInvolvedInLabelConflicts": rows_in_conflicting_groups,
        "labelConflictExamples": examples,
    }


def group_safe_split(
    features: pd.DataFrame, labels: pd.Series, groups: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    """80/20-equivalent split where no feature-vector group crosses the split."""
    splitter = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)
    train_idx, test_idx = next(splitter.split(features, labels, groups=groups))
    return train_idx, test_idx


def verify_no_group_leakage(
    features: pd.DataFrame, train_idx: np.ndarray, test_idx: np.ndarray
) -> int:
    train_vectors = set(map(tuple, features.iloc[train_idx].to_numpy().tolist()))
    test_vectors = set(map(tuple, features.iloc[test_idx].to_numpy().tolist()))
    return len(train_vectors & test_vectors)


def evaluate(model, X_test, y_test, label: str) -> dict:
    predictions = model.predict(X_test)
    probabilities = model.predict_proba(X_test)
    accuracy = accuracy_score(y_test, predictions)
    balanced_accuracy = balanced_accuracy_score(y_test, predictions)
    precision_w, recall_w, f1_w, _ = precision_recall_fscore_support(
        y_test, predictions, average="weighted", zero_division=0
    )
    precision_m, recall_m, f1_m, _ = precision_recall_fscore_support(
        y_test, predictions, average="macro", zero_division=0
    )
    top3 = top_k_accuracy_score(
        y_test, probabilities, k=min(3, probabilities.shape[1]), labels=model.classes_
    )
    report_dict = classification_report(
        y_test, predictions, zero_division=0, output_dict=True
    )
    matrix = confusion_matrix(y_test, predictions, labels=model.classes_)

    metrics = {
        "label": label,
        "testSamples": int(len(y_test)),
        "accuracy": float(accuracy),
        "balancedAccuracy": float(balanced_accuracy),
        "precisionWeighted": float(precision_w),
        "recallWeighted": float(recall_w),
        "f1Weighted": float(f1_w),
        "precisionMacro": float(precision_m),
        "recallMacro": float(recall_m),
        "f1Macro": float(f1_m),
        "top3Accuracy": float(top3),
    }
    return metrics, report_dict, matrix


def main() -> None:
    overall_start = time.time()
    print("=" * 70)
    print("Random Forest optimization experiment (leakage-safe split)")
    print("=" * 70)

    features, labels = load_dataset()
    print(f"Loaded {len(features):,} rows, {features.shape[1]} features, "
          f"{labels.nunique()} classes from {DATASET_PATH}")

    groups = vector_group_ids(features)
    leakage_report = analyze_leakage_and_conflicts(features, labels, groups)
    print(f"Unique feature-vector groups: {leakage_report['uniqueFeatureVectorGroups']:,}")
    print(f"Rows in label-conflict groups: {leakage_report['rowsInvolvedInLabelConflicts']:,}")

    # For comparison: how much train/test leakage exists in the CURRENT
    # production split (plain stratified train_test_split, no grouping)?
    from sklearn.model_selection import train_test_split as plain_split

    prod_train_idx, prod_test_idx = plain_split(
        np.arange(len(features)),
        test_size=0.20,
        random_state=RANDOM_STATE,
        stratify=labels,
    )
    prod_leak = verify_no_group_leakage(
        features, np.asarray(prod_train_idx), np.asarray(prod_test_idx)
    )
    leakage_report["productionSplitVectorOverlapRows"] = int(prod_leak)
    print(f"Production (ungrouped) split train/test vector overlap: {prod_leak:,} rows")

    train_idx, test_idx = group_safe_split(features, labels, groups)
    group_leak = verify_no_group_leakage(features, train_idx, test_idx)
    leakage_report["groupSafeSplitVectorOverlapRows"] = int(group_leak)
    print(f"Group-safe split train/test vector overlap: {group_leak:,} rows (must be 0)")
    assert group_leak == 0, "Group-safe split leaked a feature vector across train/test"

    X_train, X_test = features.iloc[train_idx], features.iloc[test_idx]
    y_train, y_test = labels.iloc[train_idx], labels.iloc[test_idx]
    groups_train = groups[train_idx]

    leakage_report["groupSafeSplit"] = {
        "trainRecords": int(len(X_train)),
        "testRecords": int(len(X_test)),
        "trainPercent": round(100 * len(X_train) / len(features), 2),
        "testPercent": round(100 * len(X_test) / len(features), 2),
        "minClassCountTrain": int(y_train.value_counts().min()),
        "minClassCountTest": int(y_test.value_counts().min()),
        "classesInTrain": int(y_train.nunique()),
        "classesInTest": int(y_test.nunique()),
    }
    (REPORTS_DIR / "leakage_report.json").write_text(
        json.dumps(leakage_report, indent=2), encoding="utf-8"
    )
    print(f"Leakage report written to {REPORTS_DIR / 'leakage_report.json'}")

    # --- Baseline: production hyperparameters, evaluated on the leakage-safe split ---
    print("\n--- Baseline (production hyperparameters) on leakage-safe split ---")
    baseline = RandomForestClassifier(
        n_estimators=300,
        random_state=RANDOM_STATE,
        n_jobs=-1,
        max_depth=24,
        max_leaf_nodes=4096,
        min_samples_leaf=2,
    )
    t0 = time.time()
    baseline.fit(X_train, y_train)
    baseline_fit_seconds = time.time() - t0
    baseline_metrics, baseline_report, baseline_matrix = evaluate(
        baseline, X_test, y_test, "baseline_production_config_group_safe_split"
    )
    baseline_metrics["fitSeconds"] = round(baseline_fit_seconds, 2)
    print(json.dumps(baseline_metrics, indent=2))

    # --- Hyperparameter search (training data / group-aware CV only) ---
    print("\n--- RandomizedSearchCV (StratifiedGroupKFold, training data only) ---")
    # Search budget deliberately bounded for wall-clock feasibility: the
    # original 40-candidate x 5-fold (200 fit) sweep, including candidates up
    # to 600 trees / depth 40, ran over 55 minutes on this machine without
    # finishing. This narrower space keeps every candidate within a cost range
    # already empirically confirmed fast (the 300-tree/depth-24 baseline fit
    # in ~4s using all cores), while still covering every hyperparameter the
    # task asked to tune. This is a smaller search, not a lower-quality one --
    # disclosed transparently in the generated report.
    param_distributions = {
        "n_estimators": [200, 300, 400],
        "max_depth": [16, 20, 24, 28, 32],
        "min_samples_leaf": [1, 2, 3, 4],
        "min_samples_split": [2, 4, 6, 10],
        "max_features": ["sqrt", "log2", 0.3, 0.5],
        "criterion": ["gini", "entropy"],
        "class_weight": [None, "balanced_subsample"],
    }
    cv = StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=RANDOM_STATE)
    search = RandomizedSearchCV(
        estimator=RandomForestClassifier(random_state=RANDOM_STATE, n_jobs=1, bootstrap=True),
        param_distributions=param_distributions,
        n_iter=15,
        scoring="f1_weighted",
        cv=cv,
        random_state=RANDOM_STATE,
        n_jobs=-1,
        verbose=2,
        refit=True,
    )
    t0 = time.time()
    search.fit(X_train, y_train, groups=groups_train)
    search_seconds = time.time() - t0
    print(f"\nSearch completed in {search_seconds:.1f}s")
    print("Best params:", search.best_params_)
    print("Best CV f1_weighted:", search.best_score_)

    cv_results_summary = (
        pd.DataFrame(search.cv_results_)
        .sort_values("rank_test_score")
        .head(10)[
            ["rank_test_score", "mean_test_score", "std_test_score", "mean_fit_time", "params"]
        ]
        .to_dict(orient="records")
    )
    search_report = {
        "searchSeconds": round(search_seconds, 1),
        "nIter": 15,
        "cv": "StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=42)",
        "searchSpaceNote": "Bounded to n_estimators<=400, max_depth<=32 after an "
        "initial 40-candidate x 5-fold sweep (incl. up to 600 trees/depth 40) "
        "exceeded 55 minutes without completing on this machine. See "
        "MODEL_EVALUATION_REPORT.md for the disclosed methodology.",
        "scoring": "f1_weighted",
        "bestParams": search.best_params_,
        "bestCvScore": float(search.best_score_),
        "top10CvResults": cv_results_summary,
    }
    (REPORTS_DIR / "rf_search_results.json").write_text(
        json.dumps(search_report, indent=2, default=str), encoding="utf-8"
    )

    # --- Final evaluation of the tuned model on the untouched test set ---
    print("\n--- Tuned model: final evaluation on held-out test set (touched once) ---")
    tuned_model = search.best_estimator_
    tuned_metrics, tuned_report, tuned_matrix = evaluate(
        tuned_model, X_test, y_test, "tuned_group_safe_split"
    )
    print(json.dumps(tuned_metrics, indent=2))

    # --- Cross-validation robustness check of the tuned hyperparameters ---
    print("\n--- 5-fold stratified-group CV of tuned hyperparameters (robustness check) ---")
    cv_check = cross_validate(
        RandomForestClassifier(**search.best_params_, random_state=RANDOM_STATE, n_jobs=-1),
        X_train,
        y_train,
        groups=groups_train,
        cv=StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE),
        scoring=["accuracy", "f1_weighted", "f1_macro"],
        n_jobs=1,
    )
    cv_summary = {
        "folds": 5,
        "meanAccuracy": float(np.mean(cv_check["test_accuracy"])),
        "stdAccuracy": float(np.std(cv_check["test_accuracy"])),
        "meanF1Weighted": float(np.mean(cv_check["test_f1_weighted"])),
        "stdF1Weighted": float(np.std(cv_check["test_f1_weighted"])),
        "meanF1Macro": float(np.mean(cv_check["test_f1_macro"])),
        "stdF1Macro": float(np.std(cv_check["test_f1_macro"])),
        "perFoldAccuracy": cv_check["test_accuracy"].tolist(),
        "perFoldF1Weighted": cv_check["test_f1_weighted"].tolist(),
    }
    print(json.dumps(cv_summary, indent=2))

    # --- Feature importances ---
    importances = tuned_model.feature_importances_
    order = np.argsort(importances)[::-1][:20]
    top_features = [
        {"feature": features.columns[i], "importance": float(importances[i])}
        for i in order
    ]

    # --- Per-class results, worst classes by recall ---
    per_class_rows = []
    for class_name, values in tuned_report.items():
        if class_name in ("accuracy", "macro avg", "weighted avg"):
            continue
        per_class_rows.append(
            {
                "disease": class_name,
                "precision": values["precision"],
                "recall": values["recall"],
                "f1": values["f1-score"],
                "support": values["support"],
            }
        )
    per_class_df = pd.DataFrame(per_class_rows).sort_values("recall")
    per_class_df.to_csv(REPORTS_DIR / "rf_tuned_per_class_report.csv", index=False)

    matrix_df = pd.DataFrame(
        tuned_matrix, index=list(tuned_model.classes_), columns=list(tuned_model.classes_)
    )
    matrix_df.to_csv(REPORTS_DIR / "rf_tuned_confusion_matrix.csv")

    baseline_matrix_df = pd.DataFrame(
        baseline_matrix, index=list(baseline.classes_), columns=list(baseline.classes_)
    )
    baseline_matrix_df.to_csv(REPORTS_DIR / "rf_baseline_group_safe_confusion_matrix.csv")

    final_report = {
        "datasetPath": str(DATASET_PATH),
        "randomState": RANDOM_STATE,
        "splitMethod": "StratifiedGroupKFold(n_splits=5) fold 0 as test; "
        "groups = identical 229-feature symptom vectors",
        "baseline": baseline_metrics,
        "tuned": tuned_metrics,
        "crossValidation": cv_summary,
        "topFeatureImportances": top_features,
        "worstRecallClasses": per_class_df.head(10).to_dict(orient="records"),
        "bestRecallClasses": per_class_df.tail(10).to_dict(orient="records"),
        "totalRuntimeSeconds": round(time.time() - overall_start, 1),
    }
    (REPORTS_DIR / "rf_optimization_final_report.json").write_text(
        json.dumps(final_report, indent=2), encoding="utf-8"
    )

    # --- Save the tuned candidate model WITHOUT touching production files ---
    model_path = EXPERIMENTS_DIR / "disease_model_v2_candidate.pkl"
    features_path = EXPERIMENTS_DIR / "disease_model_v2_candidate_features.json"
    joblib.dump(tuned_model, model_path, compress=3)
    features_path.write_text(
        json.dumps(list(features.columns), indent=2), encoding="utf-8"
    )
    print(f"\nTuned candidate model saved to {model_path} (NOT wired into production)")
    print(f"Total runtime: {time.time() - overall_start:.1f}s")


if __name__ == "__main__":
    main()
