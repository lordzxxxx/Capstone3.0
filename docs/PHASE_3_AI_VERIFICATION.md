# Phase 3 — AI integration verification

Verification date: 2026-08-15.

This phase treats the active feature as symptom guidance and decision support.
The Random Forest `/predict` path remains disabled and is not presented as a
clinical prediction feature.

## Backend evidence

| Task | Status | Evidence |
| --- | --- | --- |
| AI-01 local `/guidance` | Verified | Live local API: `/` and `/health` returned HTTP 200; `/guidance` was exercised as a protected route. |
| AI-02 Firebase Authentication | Control verified | Missing credentials return HTTP 401; valid-token verification is covered by `backend/tests/test_security.py`. A real account test remains part of E2E-04. |
| AI-03 Firebase App Check | Control verified | Missing App Check after valid-token verification returns HTTP 403; live production attestation remains part of E2E-03/E2E-04. |
| AI-04 rate limits/errors | Verified | Sliding-window retry behavior, 401/403/422/429 contracts, and safe error handling are covered by backend tests. |
| AI-05 Firestore guidance content | Seed verified | `seed_symptom_guidance.py` dry-run validated 7 active documents. Live Firestore reads require deployment credentials. |
| AI-06 medication filtering | Verified | API regression test confirms medication/antibiotic wording is removed while emergency warnings remain. |
| AI-07 emergency warnings | Verified | Seed and API regression tests preserve urgent warning signs for fever and breathing-risk content. |
| AI-08 production `AI_API_BASE_URL` | Pending deployment | The production host has not been provisioned in this repository. Release builds now fail closed instead of silently targeting localhost; the deployment command is documented in `backend/README.md`. |

## Flutter evidence

| Task | Status | Evidence |
| --- | --- | --- |
| AI-09 symptom parsing | Verified | `test/disease_prediction_api_service_test.dart` covers comma, semicolon, newline, trimming, and de-duplication. |
| AI-10 mobile check-up display | Verified in code/tests | Mobile check-up calls `/guidance`, renders reviewed sections, and shows the disclaimer. |
| AI-11 web BHW check-up display | Verified in code/tests | Web BHW check-up uses the same `SymptomGuidanceApiService` contract and guidance modal. |
| AI-12 record persistence | Verified in code | Guidance fields are written through `SymptomGuidanceResult.toRecordFields()` and persisted with the check-up record/update path. |
| AI-13 unavailable backend | Verified | Records are saved before remote guidance on mobile; web uses a local category fallback. An unset release API URL now returns a safe unavailable message without making a network call. |
| AI-14 confidence/disclaimer | Verified | Guidance responses carry a human-review disclaimer and decision-support metadata; local classifier tests cover uncertainty and review messaging. |
| AI-15 legacy UI | Verified by route audit | No active caller uses disease prediction; `/predict` is unregistered and the client method is disabled without a network call. The dormant compatibility display code is retained only for old stored records. |

## Model decisions

- AI-16: the local rule-based classifier remains the active mobile fallback and
  offline path.
- AI-17: the portable model remains experimental and is not treated as
  clinical evidence.
- AI-18: `/predict` remains disabled and returns HTTP 404.

## Acceptance result

The application can accept symptoms, return safe reviewed guidance when the
protected backend is available, clearly label the result as decision support,
and continue saving records when the backend is unavailable. Real Firebase
account/App Check tests, live Firestore verification, and a production API
host remain external deployment/field-testing work.

## Commands and results

```text
backend/.venv/bin/pytest -q                 68 passed
backend/firebase/seed_symptom_guidance.py  Validated 7 documents
flutter test <AI/safety/responsive tests>   All tests passed
local API /                                 200
local API /health                           200
local API POST /guidance without auth       401
local API POST /predict                      404
```
