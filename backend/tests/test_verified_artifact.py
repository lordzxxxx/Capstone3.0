"""Integrity tests for externally provisioned model artifacts."""

from __future__ import annotations

from pathlib import Path

import joblib
import pytest

import verified_artifact
from verified_artifact import (
    ArtifactVerificationError,
    load_verified_joblib,
    sha256_file,
)


def test_matching_digest_allows_deserialization(tmp_path: Path) -> None:
    artifact = tmp_path / "model.pkl"
    joblib.dump({"model": "verified"}, artifact)

    assert load_verified_joblib(artifact, sha256_file(artifact)) == {
        "model": "verified"
    }


def test_mismatch_rejects_before_joblib_load(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    artifact = tmp_path / "model.pkl"
    artifact.write_bytes(b"not approved")
    called = False

    def unsafe_load(_: Path) -> object:
        nonlocal called
        called = True
        return object()

    monkeypatch.setattr(verified_artifact.joblib, "load", unsafe_load)

    with pytest.raises(ArtifactVerificationError, match="checksum mismatch"):
        load_verified_joblib(artifact, "0" * 64)
    assert called is False


def test_expected_digest_must_be_explicitly_valid(tmp_path: Path) -> None:
    artifact = tmp_path / "model.pkl"
    artifact.write_bytes(b"payload")

    with pytest.raises(ArtifactVerificationError, match="64 hexadecimal"):
        load_verified_joblib(artifact, "unknown")
