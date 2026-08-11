"""Repack the trained Random Forest without changing its predictions.

The training run writes a valid joblib artifact.  This maintenance step loads
that artifact and serializes the same estimator from a clean process into a
high-compression temporary file, which keeps the tracked binary below the
regular GitHub file limit.  It does not retrain, alter data, or change model
parameters.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import joblib


BACKEND_DIR = Path(__file__).resolve().parents[1]
MODEL_PATH = BACKEND_DIR / "models" / "disease_model.pkl"
METRICS_PATH = BACKEND_DIR / "models" / "training_metrics.json"
METADATA_PATH = BACKEND_DIR / "models" / "disease_model_v2.metadata.json"
TEMP_PATH = Path("/private/tmp") / f"disease_model_v2_repack_{os.getpid()}.pkl"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    model = joblib.load(MODEL_PATH)
    joblib.dump(model, TEMP_PATH, compress=("bz2", 9))
    TEMP_PATH.replace(MODEL_PATH)
    checksum = sha256_file(MODEL_PATH)

    metrics = json.loads(METRICS_PATH.read_text(encoding="utf-8"))
    metrics["model_sha256"] = checksum
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    metadata["artifact_sha256"] = checksum
    METADATA_PATH.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps({"model": str(MODEL_PATH), "bytes": MODEL_PATH.stat().st_size, "sha256": checksum}, indent=2))


if __name__ == "__main__":
    main()
