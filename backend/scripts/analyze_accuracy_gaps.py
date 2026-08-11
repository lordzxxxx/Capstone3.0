"""Produce a reproducible, read-only analysis of the disease-model gaps.

This report connects the saved held-out diagnostics to the actual source
labels, processed feature vectors, and fields available in the application.
It deliberately does not merge data, alter labels, or add unsupported model
inputs.  A candidate application field is marked usable only when the current
training source contains the same field paired with the disease target.
"""

from __future__ import annotations

import itertools
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

BACKEND_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = BACKEND_DIR.parent
RAW_PATH = BACKEND_DIR / "dataset" / "raw" / "Diseases_and_Symptoms_dataset.csv"
PROCESSED_PATH = BACKEND_DIR / "dataset" / "processed" / "merged_dataset.csv"
DISEASE_MAPPING_PATH = BACKEND_DIR / "dataset" / "mappings" / "disease_mapping.json"
VERIFICATION_PATH = BACKEND_DIR / "reports" / "ai_requirements_verification.json"
OUTPUT_PATH = BACKEND_DIR / "reports" / "accuracy_gap_analysis.json"

sys.path.insert(0, str(BACKEND_DIR / "scripts"))
sys.path.insert(0, str(BACKEND_DIR / "app"))

from pipeline_utils import basic_normalize, load_mapping, normalize_disease  # noqa: E402
from train import vector_group_ids  # noqa: E402


def relative(path: Path) -> str:
    return str(path.relative_to(PROJECT_DIR))


def load_frame(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, low_memory=False)


def label_audit(raw: pd.DataFrame, processed: pd.DataFrame) -> dict[str, Any]:
    mapping = load_mapping(DISEASE_MAPPING_PATH)
    raw_labels = raw["diseases"].astype("string")
    normalized = raw_labels.map(lambda value: normalize_disease(value, mapping))
    changes: Counter[tuple[str, str]] = Counter()
    for source, target in zip(raw_labels, normalized, strict=False):
        source_value = basic_normalize(str(source))
        if source_value != target:
            changes[(source_value, target)] += 1

    mapping_entries = []
    for source, target in sorted(mapping.items()):
        source_count = int((raw_labels.map(basic_normalize) == source).sum())
        mapping_entries.append(
            {
                "source_label": source,
                "canonical_label": target,
                "present_in_current_raw_source": source_count > 0,
                "raw_record_count": source_count,
            }
        )

    collisions: dict[str, list[str]] = {}
    for source, target in mapping.items():
        collisions.setdefault(target, []).append(source)
    equivalent_groups = [
        {"canonical_label": target, "source_labels": sorted(sources)}
        for target, sources in sorted(collisions.items())
        if len(sources) > 1
    ]

    return {
        "mapping_file": relative(DISEASE_MAPPING_PATH),
        "raw_label_count": int(raw_labels.nunique()),
        "processed_label_count": int(processed["diseases"].nunique()),
        "raw_records": int(len(raw_labels)),
        "records_changed_by_configured_mapping": int(sum(changes.values())),
        "normalizations_applied_in_current_raw_source": [
            {
                "source_label": source,
                "canonical_label": target,
                "record_count": count,
            }
            for (source, target), count in sorted(changes.items())
        ],
        "reviewed_configured_mappings": mapping_entries,
        "equivalent_label_groups_in_mapping": equivalent_groups,
        "medical_distinction_policy": (
            "Only configured spelling, abbreviation, or synonym mappings are "
            "eligible. Overlapping symptoms do not justify merging medically "
            "different disease classes."
        ),
        "current_result": (
            "The current raw source already uses the canonical labels; no new "
            "label normalization was applied in this run."
            if not changes
            else "Configured label normalization was applied; each changed label is listed above."
        ),
    }


def conflict_analysis(features: pd.DataFrame, labels: pd.Series) -> dict[str, Any]:
    groups = vector_group_ids(features)
    grouped = pd.DataFrame({"group": groups, "label": labels.to_numpy()})
    group_labels = grouped.groupby("group")["label"].agg(lambda values: sorted(set(values)))
    conflict_groups = group_labels[group_labels.map(len) > 1]
    pair_groups: Counter[tuple[str, str]] = Counter()
    pair_rows: Counter[tuple[str, str]] = Counter()
    for group, values in conflict_groups.items():
        group_rows = int((groups == group).sum())
        for first, second in itertools.combinations(values, 2):
            pair = (str(first), str(second))
            pair_groups[pair] += 1
            pair_rows[pair] += group_rows

    group_sizes = pd.Series(groups).value_counts()
    majority_rows = int(
        grouped.groupby(["group", "label"], sort=False)
        .size()
        .groupby(level=0)
        .max()
        .sum()
    )

    return {
        "unique_feature_vector_groups": int(group_sizes.size),
        "rows_sharing_feature_vector": int(group_sizes[group_sizes > 1].sum()),
        "label_conflict_groups": int(len(conflict_groups)),
        "rows_in_label_conflict_groups": int(
            grouped["group"].isin(conflict_groups.index).sum()
        ),
        "largest_feature_vector_group_rows": int(group_sizes.max()),
        "majority_per_vector_upper_bound": int(majority_rows),
        "majority_per_vector_theoretical_ceiling": float(majority_rows / len(labels)),
        "most_common_conflicting_label_pairs": [
            {
                "labels": [first, second],
                "conflicting_vector_groups": int(pair_groups[(first, second)]),
                "rows_in_those_groups": int(pair_rows[(first, second)]),
            }
            for (first, second), _ in pair_groups.most_common(20)
        ],
    }


def variable_inventory() -> list[dict[str, Any]]:
    """Inventory fields found in application code without treating them as RF inputs."""
    return [
        {
            "variable": "symptoms",
            "available_in_system": True,
            "available_in_training_data": True,
            "source": "Application checkup/prenatal text fields; normalized wide symptom columns in the RF source",
            "can_be_used_for_training": True,
            "current_role": "228 binary symptom-presence inputs after normalization",
            "reason": "The current RF source contains the paired binary representation and disease label.",
        },
        {
            "variable": "age",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup/prenatal records and HealthAIClassifier; no age column in Diseases_and_Symptoms_dataset.csv",
            "can_be_used_for_training": False,
            "current_role": "On-device category/severity input only; not an RF disease input",
            "reason": "No real age value is paired with the 100-class RF target in the current training source.",
        },
        {
            "variable": "symptom_duration",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "DOH/RITM case-form templates and possible narrative details; no duration field in the local RF source",
            "can_be_used_for_training": False,
            "current_role": "Not used",
            "reason": "A duration feature requires real labeled records containing duration; no such paired field is present locally.",
        },
        {
            "variable": "symptom_severity",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Application severity workflow and free-text details; not a labeled RF training column",
            "can_be_used_for_training": False,
            "current_role": "On-device severity output/rule input, not RF disease input",
            "reason": "The current RF dataset has no severity measurement paired with disease labels.",
        },
        {
            "variable": "temperature",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup form/details and on-device classifier; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "On-device severity input only",
            "reason": "No paired temperature and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "blood_pressure",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup and prenatal forms/details; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "On-device severity input only",
            "reason": "No paired blood-pressure measurement and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "heart_rate",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup form/details and on-device classifier; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "On-device severity input only",
            "reason": "No paired heart-rate measurement and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "respiratory_rate",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup form/details; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "Captured for records; not an RF input",
            "reason": "No paired respiratory-rate measurement and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "oxygen_saturation",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Checkup form/details; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "Captured for records; not an RF input",
            "reason": "No paired oxygen-saturation measurement and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "medical_history",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Prenatal preExistingConditions/previousComplications fields; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "On-device/rule-based context only",
            "reason": "No paired history field and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "pregnancy_context",
            "available_in_system": True,
            "available_in_training_data": False,
            "source": "Prenatal fields including gestationalAge, gravida, para, and riskLevel; absent from RF source",
            "can_be_used_for_training": False,
            "current_role": "Prenatal workflow context only",
            "reason": "No paired pregnancy context and 100-class disease target exists in the current training data.",
        },
        {
            "variable": "diseases",
            "available_in_system": True,
            "available_in_training_data": True,
            "source": "Checkup diseaseType/AI category fields are not the same as the RF target; RF source diseases column is authoritative",
            "can_be_used_for_training": False,
            "current_role": "y target: 100-class categorical disease label",
            "reason": "The disease label is the dependent variable, not an independent input.",
        },
    ]


def main() -> int:
    raw = load_frame(RAW_PATH)
    processed = load_frame(PROCESSED_PATH)
    features = processed.drop(columns=["diseases"])
    labels = processed["diseases"].astype("string")
    verification = (
        json.loads(VERIFICATION_PATH.read_text(encoding="utf-8"))
        if VERIFICATION_PATH.exists()
        else {}
    )
    report = {
        "generated_at": pd.Timestamp.now(tz="UTC").isoformat(),
        "purpose": "Actual error-gap, label, variable, and ambiguity analysis; no records or labels changed.",
        "dataset": {
            "raw_path": relative(RAW_PATH),
            "processed_path": relative(PROCESSED_PATH),
            "raw_records": int(len(raw)),
            "usable_records": int(len(processed)),
            "feature_count": int(features.shape[1]),
            "class_count": int(labels.nunique()),
            "class_size_min": int(labels.value_counts().min()),
            "class_size_max": int(labels.value_counts().max()),
            "class_distribution": {
                str(label): int(count)
                for label, count in labels.value_counts().sort_index().items()
            },
        },
        "label_audit": label_audit(raw, processed),
        "ambiguity_analysis": conflict_analysis(features, labels),
        "held_out_error_diagnostics": verification.get("model_evaluation", {}).get("diagnostics", {}),
        "variable_inventory": variable_inventory(),
        "interpretation": {
            "largest_observed_causes": [
                "Identical 228-symptom vectors occur with different disease labels; the majority-per-vector ceiling is below 95%.",
                "Near-identical vectors are widespread, so one symptom difference often separates neighboring classes without enough clinical context.",
                "The weakest held-out recalls cluster in clinically overlapping classes, including COPD, skin polyp, skin pigmentation disorder, and noninfectious gastroenteritis.",
                "The current training source has no age, duration, severity, vital-sign, laboratory, history, or pregnancy-context columns paired with the 100-class target.",
                "No additional label aliases were observed in the current raw source beyond the configured mapping file; medically distinct overlapping classes were retained.",
            ],
            "accuracy_ceiling_definition": "Sum of the majority label count within every exact feature-vector group divided by usable records; this is an upper bound for any classifier using only the current 228 binary inputs on these records.",
        },
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({
        "report": relative(OUTPUT_PATH),
        "raw_records": report["dataset"]["raw_records"],
        "usable_records": report["dataset"]["usable_records"],
        "label_changes": report["label_audit"]["records_changed_by_configured_mapping"],
        "conflict_groups": report["ambiguity_analysis"]["label_conflict_groups"],
        "theoretical_ceiling": report["ambiguity_analysis"]["majority_per_vector_theoretical_ceiling"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
