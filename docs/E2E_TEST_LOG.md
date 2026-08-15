# Phase 5 — End-to-end validation log

Run date: 2026-08-15 (Asia/Manila)

This log separates checks that executed in this repository from release gates
that require the team's Firebase project, real accounts, or physical devices.
No production account tokens, App Check secrets, or service-account keys are
stored in this repository.

## Automated and local checks

| Task | Evidence | Result |
|---|---|---|
| E2E-01 backend locally | Uvicorn local smoke run from Phase 3: `/` 200, `/health` 200, protected `/guidance` 401 without credentials, `/predict` 404 | Passed |
| E2E-02 Flutter to backend contract | `disease_prediction_api_service.dart`, authenticated/App Check headers, debug Android default `10.0.2.2:8000`, release fail-closed behavior, service tests | Passed in code/tests; live authenticated request remains open |
| E2E-05 OCR-to-record path | Shared Google ML Kit capture/review/parser flow plus `ocr_extraction_test.dart`, `ocr_record_action_test.dart`, and form validation tests | Passed in code/tests; real printed forms remain open |
| E2E-07 BHW/CHO/doctor permissions | `npm run test:firestore-rules`: 17 passing; `npm run test:workflow-persistence`: 1 passing against the Firestore emulator | Passed |
| E2E-08 Android target smoke | Android 14 emulator detected; `flutter build apk --debug --no-pub` succeeded; APK installed and launched on `emulator-5554` | Emulator smoke passed; physical target-device run remains open |
| E2E-10 bug classification | No critical or major failure was found in the automated checks below; remaining items are external release gates | Recorded below |
| E2E-11 critical/major fixes | Backend tests, Flutter tests, Firestore rules, workflow persistence, and Android build/install completed without a blocking failure | No repository critical/major fix currently required |
| E2E-12 regression | Backend `pytest`: 69 passed; Flutter full suite: 91 passed; release web build and Android debug build succeeded | Passed for available local targets |

## Current bug and release-gate classification

| ID | Severity | Status | Owner/action |
|---|---|---|---|
| E2E-GATE-01 | Major release gate | Open | Provision and verify the production HTTPS AI API host, then pass it as `AI_API_BASE_URL` in release builds. |
| E2E-GATE-02 | Major release gate | Open | Test `/guidance` with real Firebase Authentication and App Check credentials in the intended Firebase project. |
| E2E-GATE-03 | Major release gate | Open | Seed and read live `symptom_guidance` documents only after qualified clinical review and deployment approval. |
| E2E-GATE-04 | Major field-test gate | Open | Run OCR capture, offline save, reconnect/synchronization, and record retrieval on the target Android handset(s). |
| E2E-GATE-05 | Minor/optional field gate | Open | Run the same mobile workflow on iOS if iOS is part of the final scope; no iOS target was available in this environment. |

These are not silently treated as passed. The application remains usable when
the AI service is unavailable, but a release is not considered production
validated until the open gates are executed and attached to the defense
evidence.

## Commands and results

```text
backend/.venv/bin/pytest -q                         69 passed
npm run test:firestore-rules                       17 passing
npm run test:workflow-persistence                   1 passing
flutter test                                        91 passed
flutter build web --release --no-tree-shake-icons   succeeded
flutter build apk --debug --no-pub                  succeeded
adb install + launch on emulator-5554              succeeded
```

The Firebase emulator emits verbose rule-evaluation traces for expected
permission denials; the test process still exits successfully. Those traces
are diagnostic output, not failed assertions.
