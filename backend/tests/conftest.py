"""Test path configuration for backend modules."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
for path in (BACKEND_DIR, BACKEND_DIR / "app", BACKEND_DIR / "firebase"):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))


@pytest.fixture(autouse=True)
def authenticated_ai_access() -> None:
    """Keep contract tests focused while security has dedicated tests."""
    import api
    from security import AuthenticatedUser

    api.app.dependency_overrides[api.require_ai_access] = lambda: (
        AuthenticatedUser(uid="test-user")
    )
    yield
    api.app.dependency_overrides.pop(api.require_ai_access, None)
