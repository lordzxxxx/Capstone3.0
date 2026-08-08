"""Disease-label normalization helpers and command-line preview."""

from __future__ import annotations

import pandas as pd

from pipeline_utils import (
    DISEASE_COLUMN,
    MAPPINGS_DIR,
    RAW_DIR,
    configure_logging,
    detect_disease_column,
    load_mapping,
    normalize_disease,
)

LOGGER = configure_logging(__name__)


def normalize_disease_column(frame: pd.DataFrame) -> pd.DataFrame | None:
    """Return a copy with its detected disease target renamed and normalized."""
    column = detect_disease_column(list(frame.columns))
    if column is None:
        return None
    mapping = load_mapping(MAPPINGS_DIR / "disease_mapping.json")
    result = frame.copy()
    result[DISEASE_COLUMN] = result[column].map(
        lambda value: normalize_disease(value, mapping)
    )
    if column != DISEASE_COLUMN:
        result = result.drop(columns=[column])
    return result


def main() -> None:
    """Report normalization coverage without changing any raw CSV."""
    for path in sorted(RAW_DIR.glob("*.csv")):
        try:
            frame = pd.read_csv(path, low_memory=False)
            normalized = normalize_disease_column(frame)
        except (OSError, UnicodeError, pd.errors.ParserError) as exc:
            LOGGER.warning("Skipping %s: %s", path.name, exc)
            continue
        if normalized is None:
            LOGGER.warning("Skipping %s: no disease/diseases column", path.name)
            continue
        LOGGER.info("Normalized %s disease labels in %s", f"{len(frame):,}", path.name)


if __name__ == "__main__":
    main()
