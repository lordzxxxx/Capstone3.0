"""Build the canonical binary symptom dataset for disease prediction."""

from __future__ import annotations

import pandas as pd

from pipeline_utils import (
    DISEASE_COLUMN,
    MAPPINGS_DIR,
    PROCESSED_DIR,
    RAW_DIR,
    configure_logging,
    detect_disease_column,
    detect_text_symptom_column,
    ensure_directories,
    load_mapping,
    prepare_wide_dataset,
    remove_empty_labels,
)
from remove_duplicates import remove_duplicates


LOGGER = configure_logging(__name__)

MIN_DISEASE_SAMPLES = 20
OUTPUT_PATH = PROCESSED_DIR / "merged_dataset.csv"
PROVENANCE_OUTPUT_PATH = PROCESSED_DIR / "row_provenance.csv"

EXCLUDED_FILENAMES = {
    "merged_dataset.csv",
    "class_distribution.csv",
}


def is_binary_feature_dataset(
    frame: pd.DataFrame,
    disease_column: str,
    filename: str,
) -> bool:
    """Return True when all non-target columns are numeric binary features."""
    feature_columns = [
        column
        for column in frame.columns
        if column != disease_column
    ]

    if not feature_columns:
        LOGGER.warning(
            "Skipping %s: no symptom feature columns found",
            filename,
        )
        return False

    numeric_features = frame[feature_columns].select_dtypes(
        include="number"
    )

    if len(numeric_features.columns) != len(feature_columns):
        non_numeric_columns = [
            column
            for column in feature_columns
            if column not in numeric_features.columns
        ]

        LOGGER.warning(
            "Skipping %s: contains non-numeric symptom columns: %s",
            filename,
            non_numeric_columns[:10],
        )
        return False

    valid_values = set(
        numeric_features
        .stack()
        .dropna()
        .unique()
        .tolist()
    )

    if not valid_values.issubset({0, 1}):
        LOGGER.warning(
            "Skipping %s: symptom values are not strictly binary. "
            "Found sample values: %s",
            filename,
            sorted(valid_values, key=str)[:20],
        )
        return False

    return True


def has_enough_class_samples(
    frame: pd.DataFrame,
    disease_column: str,
    filename: str,
) -> bool:
    """Reject datasets that do not contain enough examples per disease."""
    class_counts = (
        frame[disease_column]
        .astype("string")
        .str.strip()
        .value_counts()
    )

    if class_counts.empty:
        LOGGER.warning(
            "Skipping %s: no valid disease labels found",
            filename,
        )
        return False

    maximum_count = int(class_counts.max())
    median_count = float(class_counts.median())

    if maximum_count <= 1:
        LOGGER.warning(
            "Skipping %s: every disease has only one record",
            filename,
        )
        return False

    if median_count < MIN_DISEASE_SAMPLES:
        LOGGER.warning(
            "Skipping %s: median samples per disease is %.1f, "
            "which is below the required minimum of %s",
            filename,
            median_count,
            MIN_DISEASE_SAMPLES,
        )
        return False

    return True


def load_compatible_datasets() -> list[pd.DataFrame]:
    """Load only compatible wide binary symptom datasets from RAW_DIR."""
    disease_mapping = load_mapping(
        MAPPINGS_DIR / "disease_mapping.json"
    )
    symptom_mapping = load_mapping(
        MAPPINGS_DIR / "symptom_mapping.json"
    )

    datasets: list[pd.DataFrame] = []

    raw_files = sorted(RAW_DIR.glob("*.csv"))

    if not raw_files:
        LOGGER.warning(
            "No CSV files found in raw dataset directory: %s",
            RAW_DIR,
        )
        return datasets

    for path in raw_files:
        if path.name.lower() in EXCLUDED_FILENAMES:
            LOGGER.info(
                "Skipping generated output file: %s",
                path.name,
            )
            continue

        LOGGER.info("Reading %s", path.name)

        try:
            frame = pd.read_csv(
                path,
                low_memory=False,
            )
        except (
            OSError,
            UnicodeError,
            pd.errors.ParserError,
        ) as exc:
            LOGGER.warning(
                "Skipping unreadable CSV %s: %s",
                path.name,
                exc,
            )
            continue

        disease_column = detect_disease_column(
            list(frame.columns)
        )

        if disease_column is None:
            LOGGER.warning(
                "Skipping %s: no supported disease target column",
                path.name,
            )
            continue

        text_column = detect_text_symptom_column(
            list(frame.columns)
        )

        if text_column is not None:
            LOGGER.warning(
                "Skipping %s: text-based symptoms are not compatible "
                "with the production binary Random Forest model",
                path.name,
            )
            continue

        if not is_binary_feature_dataset(
            frame,
            disease_column,
            path.name,
        ):
            continue

        if not has_enough_class_samples(
            frame,
            disease_column,
            path.name,
        ):
            continue

        prepared = prepare_wide_dataset(
            frame,
            disease_column,
            disease_mapping,
            symptom_mapping,
        )

        prepared = remove_empty_labels(prepared)

        if prepared.empty:
            LOGGER.warning(
                "Skipping %s: no valid rows remained after preparation",
                path.name,
            )
            continue

        prepared_feature_columns = [
            column
            for column in prepared.columns
            if column != DISEASE_COLUMN
        ]

        if not prepared_feature_columns:
            LOGGER.warning(
                "Skipping %s: no symptoms remained after normalization",
                path.name,
            )
            continue

        # Keep source-row identity alongside the prepared frame.  This is
        # deliberately metadata only; it never enters the model feature
        # matrix.  The CSV row number includes the header row (row 1).
        prepared.attrs["source_file"] = path.name
        prepared.attrs["source_relative_path"] = str(path)
        prepared.attrs["source_row_numbers"] = [
            int(index) + 2 for index in prepared.index
        ]

        datasets.append(prepared)

        LOGGER.info(
            "Loaded %s: %s rows, %s diseases, %s symptoms",
            path.name,
            f"{prepared.shape[0]:,}",
            f"{prepared[DISEASE_COLUMN].nunique():,}",
            f"{prepared.shape[1] - 1:,}",
        )

    return datasets


def build_master_dataset(
    min_samples: int = MIN_DISEASE_SAMPLES,
) -> pd.DataFrame:
    """Merge compatible datasets and export the processed master CSV."""
    ensure_directories()

    datasets = load_compatible_datasets()

    if not datasets:
        raise RuntimeError(
            f"No compatible binary symptom datasets found in {RAW_DIR}"
        )

    symptom_columns = sorted(
        {
            column
            for frame in datasets
            for column in frame.columns
            if column != DISEASE_COLUMN
        }
    )

    LOGGER.info(
        "Master symptom list contains %s features",
        f"{len(symptom_columns):,}",
    )

    aligned_frames: list[pd.DataFrame] = []

    for frame in datasets:
        aligned = (
            frame
            .set_index(DISEASE_COLUMN)
            .reindex(
                columns=symptom_columns,
                fill_value=0,
            )
            .reset_index()
        )

        aligned["__source_file"] = str(
            frame.attrs.get("source_file", "SOURCE REQUIRES VERIFICATION")
        )
        aligned["__source_csv_row_number"] = frame.attrs.get(
            "source_row_numbers",
            [None] * len(aligned),
        )

        aligned_frames.append(aligned)

    merged = pd.concat(
        aligned_frames,
        ignore_index=True,
    )

    merged[symptom_columns] = (
        merged[symptom_columns]
        .fillna(0)
        .astype("uint8")
    )

    model_columns = [DISEASE_COLUMN, *symptom_columns]
    provenance = merged[
        ["__source_file", "__source_csv_row_number"]
    ].copy()
    merged = merged[model_columns]

    rows_before_duplicates = len(merged)

    duplicate_mask = ~merged.duplicated(keep="first")
    merged = remove_duplicates(merged)
    provenance = provenance.loc[duplicate_mask].reset_index(drop=True)

    rows_after_duplicates = len(merged)
    duplicates_removed = (
        rows_before_duplicates - rows_after_duplicates
    )

    LOGGER.info(
        "Rows before duplicate removal: %s",
        f"{rows_before_duplicates:,}",
    )
    LOGGER.info(
        "Rows after duplicate removal: %s",
        f"{rows_after_duplicates:,}",
    )
    LOGGER.info(
        "Duplicate rows removed: %s",
        f"{duplicates_removed:,}",
    )

    disease_counts = merged[DISEASE_COLUMN].value_counts()

    removed_diseases = disease_counts[
        disease_counts < min_samples
    ].sort_index()

    valid_diseases = disease_counts[
        disease_counts >= min_samples
    ].index

    valid_mask = merged[DISEASE_COLUMN].isin(valid_diseases)
    merged = merged.loc[valid_mask].reset_index(drop=True)
    provenance = provenance.loc[valid_mask].reset_index(drop=True)

    print("\nRemoved diseases with too few records:")

    if removed_diseases.empty:
        print("  None")
    else:
        for disease, count in removed_diseases.items():
            print(f"  {disease}: {count}")

    print(
        f"\nRemaining diseases: "
        f"{merged[DISEASE_COLUMN].nunique():,}"
    )
    print(
        f"Remaining records: {len(merged):,}"
    )
    print(
        f"Remaining symptoms: {len(symptom_columns):,}"
    )

    OUTPUT_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    merged.to_csv(
        OUTPUT_PATH,
        index=False,
    )

    provenance_output = provenance.rename(
        columns={
            "__source_file": "source_file",
            "__source_csv_row_number": "source_csv_row_number",
        }
    )
    provenance_output.insert(
        0,
        "processed_row_index",
        range(len(provenance_output)),
    )
    provenance_output.insert(
        1,
        "normalized_disease",
        merged[DISEASE_COLUMN].to_numpy(),
    )
    provenance_output.to_csv(PROVENANCE_OUTPUT_PATH, index=False)

    LOGGER.info(
        "Saved master dataset to %s",
        OUTPUT_PATH,
    )
    LOGGER.info(
        "Saved row provenance sidecar to %s",
        PROVENANCE_OUTPUT_PATH,
    )

    return merged


if __name__ == "__main__":
    try:
        build_master_dataset()
    except Exception:
        LOGGER.exception("Dataset merge failed")
        raise
