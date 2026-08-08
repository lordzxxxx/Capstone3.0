"""Reusable duplicate-removal operation for canonical datasets."""

from __future__ import annotations

import pandas as pd


def remove_duplicates(frame: pd.DataFrame) -> pd.DataFrame:
    """Drop exact duplicate records and print the requested summary."""
    before = len(frame)
    result = frame.drop_duplicates(ignore_index=True)
    after = len(result)
    print(f"Rows before: {before:,}")
    print(f"Rows after: {after:,}")
    print(f"Duplicates removed: {before - after:,}")
    return result
