"""Tests for the model-reporting calculations."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from evaluation_metrics import (
    apply_temperature_scaling,
    exact_vector_ambiguity_summary,
    fit_temperature_from_oof,
    multiclass_calibration_summary,
    statistical_metric_summary,
    top_k_successes,
    wilson_interval,
)


def test_temperature_scaling_preserves_rows_and_class_order() -> None:
    probabilities = np.array([[0.55, 0.30, 0.15], [0.20, 0.50, 0.30]])

    calibrated = apply_temperature_scaling(probabilities, 0.5)

    assert calibrated.sum(axis=1) == pytest.approx([1.0, 1.0])
    assert calibrated.argmax(axis=1).tolist() == [0, 1]
    assert calibrated[0, 0] > probabilities[0, 0]


def test_temperature_is_fit_from_oof_probabilities() -> None:
    labels = ["a", "b", "a", "b"]
    underconfident = np.array(
        [[0.60, 0.40], [0.40, 0.60], [0.58, 0.42], [0.42, 0.58]]
    )

    fit = fit_temperature_from_oof(labels, underconfident, ["a", "b"])

    assert fit["fit_scope"] == "training_partition_out_of_fold_only"
    assert float(fit["temperature"]) < 1.0
    assert float(fit["oof_log_loss_after"]) < float(fit["oof_log_loss_before"])


def test_wilson_interval_is_bounded_and_contains_estimate() -> None:
    lower, upper = wilson_interval(90, 100)

    assert 0 <= lower < 0.9 < upper <= 1


def test_top_k_successes_counts_ranked_coverage() -> None:
    probabilities = np.array(
        [
            [0.7, 0.2, 0.1],
            [0.4, 0.5, 0.1],
            [0.45, 0.2, 0.35],
        ]
    )

    assert top_k_successes(["a", "b", "c"], probabilities, ["a", "b", "c"], 1) == 2
    assert top_k_successes(["a", "b", "c"], probabilities, ["a", "b", "c"], 2) == 3


def test_ambiguity_ceiling_counts_conflicting_identical_vectors() -> None:
    features = pd.DataFrame({"fever": [1, 1, 1, 0], "cough": [0, 0, 0, 1]})
    labels = pd.Series(["a", "a", "b", "c"], dtype="string")

    summary = exact_vector_ambiguity_summary(features, labels)

    assert summary["unique_feature_vector_groups"] == 2
    assert summary["conflicting_feature_vector_groups"] == 1
    assert summary["rows_in_conflicting_feature_vector_groups"] == 3
    assert summary["majority_vector_ceiling"] == pytest.approx(3 / 4)


def test_metric_summary_labels_top_k_as_coverage() -> None:
    summary = statistical_metric_summary(
        total=10,
        top1_successes=8,
        top2_successes=9,
        top3_successes=10,
        class_count=5,
        ambiguity={"majority_vector_ceiling": 0.95},
    )

    assert summary["top2_coverage"]["estimate"] == 0.9
    assert "coverage" in summary["definitions"]["top_k_coverage"]


def test_calibration_summary_is_zero_for_perfect_confident_predictions() -> None:
    summary = multiclass_calibration_summary(
        ["a", "b"],
        np.array([[1.0, 0.0], [0.0, 1.0]]),
        ["a", "b"],
    )

    assert summary["multiclass_log_loss"] == pytest.approx(0.0)
    assert summary["multiclass_brier_score"] == pytest.approx(0.0)
    assert summary["top_label_expected_calibration_error"] == pytest.approx(0.0)


def test_calibration_summary_exposes_overconfidence() -> None:
    summary = multiclass_calibration_summary(
        ["a", "b"],
        np.array([[0.9, 0.1], [0.9, 0.1]]),
        ["a", "b"],
    )

    assert summary["top1_accuracy"] == pytest.approx(0.5)
    assert summary["mean_top1_confidence"] == pytest.approx(0.9)
    assert summary["mean_confidence_minus_accuracy"] == pytest.approx(0.4)
    assert summary["top_label_expected_calibration_error"] == pytest.approx(0.4)


def test_calibration_summary_rejects_invalid_probability_rows() -> None:
    with pytest.raises(ValueError, match="sum to one"):
        multiclass_calibration_summary(
            ["a"],
            np.array([[0.2, 0.2]]),
            ["a", "b"],
        )
