# AI symptom-guidance workflow

The product feature is symptom guidance and decision support. It is not an
automated diagnosis or prescription system.

## Active request path

1. A worker enters symptom text in the mobile or web check-up workflow.
2. The Flutter client normalizes the input and requests a Firebase Auth ID
   token plus Firebase App Check token.
3. The client calls `POST /guidance` at the configured `AI_API_BASE_URL`.
4. FastAPI verifies authentication, App Check, request shape, known symptom
   vocabulary, and the per-user sliding-window rate limit.
5. The service reads Firestore-authored `symptom_guidance` documents.
6. Medication and prescription wording is filtered before the response is
   returned; emergency warnings are preserved.
7. The UI presents supportive care, precautions, referral prompts, emergency
   warnings, confidence/review messaging, and a human-review disclaimer.
8. The check-up record is saved independently of remote guidance availability.

## Unavailable-service path

- Mobile record saving occurs before the remote request can fail.
- The mobile client retains local rule-based decision support for the offline
  path, with explicit confidence and review messaging.
- Release builds without `AI_API_BASE_URL` fail closed with a safe unavailable
  message rather than silently calling localhost.
- Web BHW check-ups catch the remote error and show a local fallback/status.

## Model decision

- Local rule-based classifier: active offline decision-support fallback.
- Portable model artifact: experimental/documented only unless retrained and
  revalidated with legitimate data.
- Random Forest `/predict`: disabled and intentionally returns 404.
- None of these paths may be described as clinically validated diagnosis.

Evidence: `docs/PHASE_3_AI_VERIFICATION.md`,
`docs/AI_VALIDATION_REPORT.md`, `backend/app/api.py`, and
`lib/app/core/services/disease_prediction_api_service.dart`.
