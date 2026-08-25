"""Checksum verification for externally provisioned model artifacts.

Joblib/pickle files can execute code while loading. The checksum therefore has
to be verified before deserialization, and the expected digest must come from
versioned metadata or an explicit deployment setting.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any

import joblib

_SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class ArtifactVerificationError(RuntimeError):
    """Raised before deserialization when artifact integrity is not proven."""


def sha256_file(path: Path) -> str:
    """Return the SHA-256 digest without loading or deserializing the file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_verified_joblib(path: Path, expected_sha256: str) -> Any:
    """Verify *path* against an approved digest, then deserialize it once."""
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise ArtifactVerificationError(f"Model file not found: {resolved}")
    expected = expected_sha256.strip().lower()
    if not _SHA256_PATTERN.fullmatch(expected):
        raise ArtifactVerificationError(
            "MODEL_EXPECTED_SHA256 must contain exactly 64 hexadecimal characters"
        )
    actual = sha256_file(resolved)
    if actual != expected:
        raise ArtifactVerificationError(
            "Model checksum mismatch; the artifact was not deserialized "
            f"(expected {expected}, found {actual})"
        )
    try:
        return joblib.load(resolved)
    except Exception as exc:
        raise ArtifactVerificationError(
            f"Verified model artifact could not be deserialized: {exc}"
        ) from exc
