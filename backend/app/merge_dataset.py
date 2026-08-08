"""Backward-compatible entry point for the relocated merge pipeline."""

from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from merge_datasets import build_master_dataset  # noqa: E402


if __name__ == "__main__":
    build_master_dataset()
