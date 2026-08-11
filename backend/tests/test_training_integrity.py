"""Tests for the dataset/model integrity gates used by the trainer."""

from __future__ import annotations

import json
from pathlib import Path

from train import group_safe_split, load_training_data, vector_group_ids


BACKEND_DIR = Path(__file__).resolve().parents[1]


def test_group_safe_split_has_no_identical_vector_overlap() -> None:
    features, labels = load_training_data()
    groups = vector_group_ids(features)
    train_idx, test_idx = group_safe_split(features, labels, groups)

    assert set(groups[train_idx]).isdisjoint(set(groups[test_idx]))
    assert len(train_idx) + len(test_idx) == len(features)
    assert set(labels.iloc[train_idx].unique()) == set(labels.unique())
    assert set(labels.iloc[test_idx].unique()) == set(labels.unique())


def test_saved_metrics_record_actual_quality_gate_and_artifacts() -> None:
    metrics = json.loads(
        (BACKEND_DIR / "models" / "training_metrics.json").read_text(
            encoding="utf-8"
        )
    )

    assert metrics["dataset_records"] == 93993
    assert metrics["features"] == 228
    assert metrics["diseases"] == 100
    assert metrics["train_test_feature_vector_overlap_groups"] == 0
    assert metrics["model_version"] == "disease_model_v4"
    assert metrics["accuracy"] == 0.8933985850311187
    assert metrics["top2_accuracy"] == 0.9654236927496144
    assert metrics["top3_accuracy"] == 0.9850523964040641
    assert metrics["model_parameters"]["min_samples_leaf"] == 2
    assert metrics["cross_validation"]["folds"] == 5
    assert (
        BACKEND_DIR / "reports" / "disease_model_confusion_matrix.csv"
    ).exists()
    assert (
        BACKEND_DIR / "reports" / "disease_model_per_class_report.csv"
    ).exists()


def test_row_provenance_covers_every_processed_record() -> None:
    import pandas as pd

    processed = pd.read_csv(
        BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv",
        usecols=["diseases"],
    )
    provenance = pd.read_csv(
        BACKEND_DIR / "dataset" / "processed" / "row_provenance.csv"
    )
    assert len(provenance) == len(processed)
    assert provenance["processed_row_index"].is_unique
    assert provenance["source_file"].notna().all()
    assert provenance["source_csv_row_number"].notna().all()
    assert provenance["normalized_disease"].tolist() == processed[
        "diseases"
    ].tolist()
