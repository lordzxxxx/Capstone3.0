from pathlib import Path
import pandas as pd


BASE_DIR = Path(__file__).resolve().parent
RAW_DIR = BASE_DIR.parent / "dataset" / "raw"


def find_target_column(columns: list[str]) -> str | None:
    candidates = ["diseases", "disease", "prognosis", "label"]

    normalized = {
        str(column).strip().lower(): column
        for column in columns
    }

    for candidate in candidates:
        if candidate in normalized:
            return normalized[candidate]

    return None


def inspect_datasets() -> None:
    csv_files = sorted(RAW_DIR.glob("*.csv"))

    if not csv_files:
        print(f"No CSV files found in: {RAW_DIR}")
        return

    for file_path in csv_files:
        print("\n" + "=" * 72)
        print(f"Dataset: {file_path.name}")
        print("=" * 72)

        try:
            frame = pd.read_csv(
                file_path,
                low_memory=False,
            )
        except Exception as error:
            print(f"Failed to read dataset: {error}")
            continue

        print(f"Rows: {len(frame):,}")
        print(f"Columns: {len(frame.columns):,}")

        target_column = find_target_column(frame.columns.tolist())

        print(
            "Target column:",
            target_column if target_column else "Not found",
        )

        if target_column:
            print(
                "Unique diseases:",
                frame[target_column].nunique(dropna=True),
            )

            print(
                "Blank disease labels:",
                frame[target_column]
                .astype("string")
                .str.strip()
                .eq("")
                .sum(),
            )

        # Faster summary instead of printing every column calculation.
        missing_per_column = frame.isnull().sum(numeric_only=False)
        total_missing = int(missing_per_column.sum())

        print(f"Total missing values: {total_missing:,}")

        columns_with_missing = missing_per_column[
            missing_per_column > 0
        ].sort_values(ascending=False)

        if columns_with_missing.empty:
            print("Columns with missing values: None")
        else:
            print("Top columns with missing values:")
            print(columns_with_missing.head(20).to_string())

        # Full duplicate detection can be slow on large datasets.
        if len(frame) <= 50_000:
            duplicate_count = int(frame.duplicated().sum())
            print(f"Duplicate rows: {duplicate_count:,}")
        else:
            sample_size = min(20_000, len(frame))
            sample = frame.sample(n=sample_size, random_state=42)

            sample_duplicates = int(sample.duplicated().sum())

            print(
                f"Duplicate check skipped for full dataset "
                f"because it contains {len(frame):,} rows."
            )
            print(
                f"Sample duplicate rows: {sample_duplicates:,} "
                f"out of {sample_size:,} sampled rows"
            )

        feature_frame = (
            frame.drop(columns=[target_column])
            if target_column
            else frame
        )

        numeric_features = feature_frame.select_dtypes(
            include="number"
        )

        print(f"Numeric feature columns: {len(numeric_features.columns):,}")
        print(
            "Non-numeric feature columns:",
            len(feature_frame.columns) - len(numeric_features.columns),
        )

        if not numeric_features.empty:
            sample_values = set()

            for column in numeric_features.columns:
                values = numeric_features[column].dropna().unique()

                if len(values) <= 10:
                    sample_values.update(values.tolist())

                if len(sample_values) > 20:
                    break

            print(
                "Sample numeric values:",
                sorted(sample_values, key=str)[:20],
            )


if __name__ == "__main__":
    inspect_datasets()
