"""Statistical helpers for honest multi-class model evaluation.

These calculations deliberately separate top-1 accuracy from top-k coverage.
Top-k coverage answers a different question: whether the true label appears in
the model's first k suggestions. It must never be reported as ordinary
accuracy.
"""

from __future__ import annotations

from statistics import NormalDist
from typing import Iterable

import numpy as np
import pandas as pd


def apply_temperature_scaling(
    probabilities: np.ndarray,
    temperature: float,
    *,
    epsilon: float = 1e-15,
) -> np.ndarray:
    """Apply multiclass temperature scaling without changing class order."""
    matrix = np.asarray(probabilities, dtype=float)
    if matrix.ndim != 2 or matrix.shape[0] == 0 or matrix.shape[1] < 2:
        raise ValueError("probabilities must be a non-empty two-dimensional matrix")
    if not np.isfinite(matrix).all() or (matrix < 0).any():
        raise ValueError("probabilities must be finite and non-negative")
    if not np.allclose(matrix.sum(axis=1), 1.0, rtol=0, atol=1e-6):
        raise ValueError("each probability row must sum to one")
    if not np.isfinite(temperature) or temperature <= 0:
        raise ValueError("temperature must be a positive finite number")

    logits = np.log(np.clip(matrix, epsilon, 1.0)) / temperature
    logits -= logits.max(axis=1, keepdims=True)
    exponentiated = np.exp(logits)
    return exponentiated / exponentiated.sum(axis=1, keepdims=True)


def fit_temperature_from_oof(
    y_true: Iterable[object],
    probabilities: np.ndarray,
    classes: Iterable[object],
    *,
    minimum: float = 0.05,
    maximum: float = 5.0,
    grid_points: int = 401,
) -> dict[str, float | int | str]:
    """Fit one temperature using training/out-of-fold probabilities only.

    A deterministic logarithmic grid avoids an additional optimizer dependency.
    The caller is responsible for ensuring these are out-of-fold predictions
    from the training partition and must not pass held-out test predictions.
    """
    labels = list(y_true)
    class_list = list(classes)
    matrix = np.asarray(probabilities, dtype=float)
    if len(labels) != matrix.shape[0] or not labels:
        raise ValueError("OOF probabilities must align with non-empty y_true")
    if not 0 < minimum < maximum or grid_points < 3:
        raise ValueError("temperature search bounds are invalid")

    class_index = {label: index for index, label in enumerate(class_list)}
    try:
        true_indices = np.asarray([class_index[label] for label in labels])
    except KeyError as exc:
        raise ValueError(f"Unknown OOF label: {exc.args[0]}") from exc
    rows = np.arange(len(labels))

    def loss(temperature: float) -> float:
        calibrated = apply_temperature_scaling(matrix, temperature)
        return float(-np.log(np.clip(calibrated[rows, true_indices], 1e-15, 1)).mean())

    temperatures = np.geomspace(minimum, maximum, grid_points)
    losses = np.asarray([loss(float(value)) for value in temperatures])
    best_index = int(losses.argmin())
    return {
        "temperature": float(temperatures[best_index]),
        "oof_log_loss_before": loss(1.0),
        "oof_log_loss_after": float(losses[best_index]),
        "records": len(labels),
        "search_minimum": minimum,
        "search_maximum": maximum,
        "search_grid_points": grid_points,
        "fit_scope": "training_partition_out_of_fold_only",
    }


def wilson_interval(
    successes: int,
    total: int,
    *,
    confidence: float = 0.95,
) -> tuple[float, float]:
    """Return a Wilson score interval for a binomial proportion."""
    if total <= 0:
        raise ValueError("total must be positive")
    if successes < 0 or successes > total:
        raise ValueError("successes must be between zero and total")
    if not 0 < confidence < 1:
        raise ValueError("confidence must be between zero and one")

    p = successes / total
    z = NormalDist().inv_cdf((1 + confidence) / 2)
    denominator = 1 + z * z / total
    centre = (p + z * z / (2 * total)) / denominator
    radius = (
        z
        * (
            (p * (1 - p) / total)
            + (z * z / (4 * total * total))
        )
        ** 0.5
        / denominator
    )
    return max(0.0, centre - radius), min(1.0, centre + radius)


def top_k_successes(
    y_true: Iterable[object],
    probabilities: np.ndarray,
    classes: Iterable[object],
    k: int,
) -> int:
    """Count held-out rows whose true class is in the top-k probabilities."""
    class_list = list(classes)
    true_labels = list(y_true)
    if probabilities.ndim != 2 or probabilities.shape[1] != len(class_list):
        raise ValueError("probabilities must align with classes")
    if probabilities.shape[0] != len(true_labels):
        raise ValueError("probabilities must align with y_true")
    if k < 1:
        raise ValueError("k must be positive")

    class_index = {label: index for index, label in enumerate(class_list)}
    hits = 0
    for actual, row in zip(true_labels, probabilities):
        actual_index = class_index.get(actual)
        if actual_index is None:
            raise ValueError(f"Unknown held-out label: {actual}")
        width = min(k, len(row))
        top_indices = np.argpartition(row, -width)[-width:]
        hits += int(actual_index in top_indices)
    return hits


def multiclass_calibration_summary(
    y_true: Iterable[object],
    probabilities: np.ndarray,
    classes: Iterable[object],
    *,
    bin_count: int = 10,
    epsilon: float = 1e-15,
) -> dict[str, object]:
    """Summarize held-out probability calibration for a multiclass model.

    ECE uses equal-width bins over the probability assigned to the predicted
    class (top-label calibration). Multiclass Brier score and log loss also
    use the complete probability vector, so a strong top-1 result cannot hide
    poorly distributed probability mass among the remaining classes.
    """
    class_list = list(classes)
    true_labels = list(y_true)
    matrix = np.asarray(probabilities, dtype=float)
    if matrix.ndim != 2 or matrix.shape[1] != len(class_list):
        raise ValueError("probabilities must align with classes")
    if matrix.shape[0] != len(true_labels) or not true_labels:
        raise ValueError("probabilities must align with non-empty y_true")
    if bin_count < 2:
        raise ValueError("bin_count must be at least two")
    if not 0 < epsilon < 1:
        raise ValueError("epsilon must be between zero and one")
    if not np.isfinite(matrix).all() or (matrix < 0).any() or (matrix > 1).any():
        raise ValueError("probabilities must be finite values between zero and one")
    if not np.allclose(matrix.sum(axis=1), 1.0, rtol=0, atol=1e-6):
        raise ValueError("each probability row must sum to one")

    class_index = {label: index for index, label in enumerate(class_list)}
    try:
        true_indices = np.asarray(
            [class_index[label] for label in true_labels],
            dtype=int,
        )
    except KeyError as exc:
        raise ValueError(f"Unknown held-out label: {exc.args[0]}") from exc

    row_indices = np.arange(len(true_labels))
    predicted_indices = np.argmax(matrix, axis=1)
    confidences = matrix[row_indices, predicted_indices]
    correct = predicted_indices == true_indices
    bin_indices = np.minimum(
        (confidences * bin_count).astype(int),
        bin_count - 1,
    )
    bins: list[dict[str, float | int]] = []
    weighted_gap = 0.0
    maximum_gap = 0.0
    for index in range(bin_count):
        members = bin_indices == index
        count = int(members.sum())
        if count:
            mean_confidence = float(confidences[members].mean())
            empirical_accuracy = float(correct[members].mean())
            gap = abs(empirical_accuracy - mean_confidence)
            weighted_gap += (count / len(true_labels)) * gap
            maximum_gap = max(maximum_gap, gap)
        else:
            mean_confidence = 0.0
            empirical_accuracy = 0.0
            gap = 0.0
        bins.append(
            {
                "lower_bound_inclusive": index / bin_count,
                "upper_bound_inclusive": (index + 1) / bin_count,
                "records": count,
                "mean_confidence": mean_confidence,
                "empirical_accuracy": empirical_accuracy,
                "absolute_gap": gap,
            }
        )

    true_probabilities = np.clip(
        matrix[row_indices, true_indices],
        epsilon,
        1.0,
    )
    log_loss = float(-np.log(true_probabilities).mean())
    brier_per_row = (
        np.square(matrix).sum(axis=1)
        - 2 * matrix[row_indices, true_indices]
        + 1
    )
    top1_accuracy = float(correct.mean())
    mean_top1_confidence = float(confidences.mean())
    return {
        "definitions": {
            "multiclass_log_loss": "-mean(log(probability assigned to the true class))",
            "multiclass_brier_score": (
                "mean(sum((predicted probability - one-hot truth)^2 across classes))"
            ),
            "top_label_ece": (
                "sum(n_bin / n * abs(bin accuracy - bin mean confidence)); "
                "10 equal-width confidence bins by default"
            ),
        },
        "records": len(true_labels),
        "classes": len(class_list),
        "bin_count": bin_count,
        "multiclass_log_loss": log_loss,
        "multiclass_brier_score": float(brier_per_row.mean()),
        "top_label_expected_calibration_error": float(weighted_gap),
        "top_label_maximum_calibration_error": float(maximum_gap),
        "top1_accuracy": top1_accuracy,
        "mean_top1_confidence": mean_top1_confidence,
        "mean_confidence_minus_accuracy": mean_top1_confidence - top1_accuracy,
        "bins": bins,
        "interpretation": (
            "Lower log loss, Brier score, and calibration error are better. "
            "Calibration measures probability reliability on this held-out "
            "dataset; it does not establish diagnosis safety or clinical validity."
        ),
    }


def exact_vector_ambiguity_summary(
    features: pd.DataFrame,
    labels: pd.Series,
) -> dict[str, float | int]:
    """Measure the empirical ceiling imposed by identical inputs."""
    if len(features) != len(labels):
        raise ValueError("features and labels must have equal lengths")
    if len(labels) == 0:
        raise ValueError("labels must not be empty")

    packed = np.packbits(features.to_numpy(dtype="uint8"), axis=1)
    groups = np.array([row.tobytes() for row in packed], dtype=object)
    grouped = pd.DataFrame({"group": groups, "label": labels.to_numpy()})
    group_sizes = grouped.groupby("group", sort=False).size()
    label_counts = grouped.groupby(["group", "label"], sort=False).size()
    majority_by_group = label_counts.groupby(level=0, sort=False).max()
    labels_per_group = label_counts.groupby(level=0, sort=False).size()
    conflicting_groups = labels_per_group > 1

    ceiling_correct = int(majority_by_group.sum())
    total = int(len(labels))
    return {
        "unique_feature_vector_groups": int(group_sizes.size),
        "conflicting_feature_vector_groups": int(conflicting_groups.sum()),
        "rows_in_conflicting_feature_vector_groups": int(
            group_sizes[conflicting_groups].sum()
        ),
        "majority_vector_ceiling": ceiling_correct / total,
        "majority_vector_ceiling_correct_rows": ceiling_correct,
        "majority_class_baseline": float(labels.value_counts().max() / total),
    }


def statistical_metric_summary(
    *,
    total: int,
    top1_successes: int,
    top2_successes: int,
    top3_successes: int,
    class_count: int,
    ambiguity: dict[str, float | int],
) -> dict[str, object]:
    """Build a report that makes metric definitions and uncertainty explicit."""
    if class_count < 2:
        raise ValueError("class_count must be at least two")
    if total <= 0:
        raise ValueError("total must be positive")

    def metric(successes: int) -> dict[str, object]:
        if successes < 0 or successes > total:
            raise ValueError("metric successes must be between zero and total")
        estimate = successes / total
        lower, upper = wilson_interval(successes, total)
        return {
            "successes": successes,
            "total": total,
            "estimate": estimate,
            "wilson_95_ci": [lower, upper],
            "wilson_95_margin": (upper - lower) / 2,
        }

    return {
        "definitions": {
            "top1_accuracy": "P(predicted_label == true_label) = correct_top1 / n",
            "top_k_coverage": (
                "Top-k coverage = P(true_label is in k highest-ranked labels) "
                "= top_k_hits / n"
            ),
            "wilson_interval": "score interval for a binomial proportion at 95% confidence",
            "majority_vector_ceiling": "sum(max label count per identical input vector) / n",
        },
        "top1_accuracy": metric(top1_successes),
        "top2_coverage": metric(top2_successes),
        "top3_coverage": metric(top3_successes),
        "uniform_random_top1_baseline": 1 / class_count,
        "uniform_random_top3_coverage_baseline": min(3, class_count) / class_count,
        "ambiguity": ambiguity,
        "interpretation": (
            "Top-2 and top-3 are coverage metrics, not ordinary accuracy. "
            "The majority-vector value is an empirical upper bound for this "
            "feature representation and cannot establish clinical validity."
        ),
    }
