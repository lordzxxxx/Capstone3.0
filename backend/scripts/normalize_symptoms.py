"""Symptom-name normalization helpers and command-line preview."""

from __future__ import annotations

from pipeline_utils import MAPPINGS_DIR, load_mapping, normalize_symptom


def normalize_symptom_name(value: object) -> str:
    """Normalize one symptom using the project mapping file."""
    mapping = load_mapping(MAPPINGS_DIR / "symptom_mapping.json")
    return normalize_symptom(value, mapping)


def main() -> None:
    """Print example conversions for a quick mapping smoke test."""
    examples = ("symptom_fever", "high fever", "difficulty breathing")
    for example in examples:
        print(f"{example} -> {normalize_symptom_name(example)}")


if __name__ == "__main__":
    main()
