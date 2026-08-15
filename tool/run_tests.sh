#!/usr/bin/env bash
# Repeatable test command for this repo (ENV-06). Run from anywhere:
#   ./tool/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== flutter pub get =="
flutter pub get

echo "== flutter analyze =="
# flutter analyze's exit code is 1 whenever ANY issue exists, including the
# 820+ pre-existing warning/info-level lints (unused code, print(),
# deprecated dart:html) that are debt, not blockers -- --no-fatal-warnings
# does not change this. So check for real `error`-level issues ourselves
# and only fail the step on those.
set +e
ANALYZE_OUTPUT="$(flutter analyze 2>&1)"
set -e
echo "$ANALYZE_OUTPUT"
if echo "$ANALYZE_OUTPUT" | grep -q "^  error •"; then
  echo "flutter analyze found blocking errors" >&2
  exit 1
fi

echo "== flutter test =="
flutter test

echo "== backend pytest =="
(cd backend && ./.venv/bin/pytest -q)

echo "== all checks passed =="
