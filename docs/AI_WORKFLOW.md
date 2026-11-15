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
5. The service retrieves active Firestore-authored guidance through a bounded
   local TF-IDF vector plus keyword/metadata ranker and attaches
   source/version/review metadata and stable citation IDs.
6. An optional server-side JSON LLM provider receives only recognized terms and
   retrieved guidance excerpts. It is disabled by default; structured output
   must cite returned IDs and pass medication/unsupported-diagnostic safety
   checks. Invalid or unavailable provider output falls back to a deterministic
   local explanation.
7. Medication and prescription wording is filtered before the response is
   returned; emergency warnings are preserved and cannot be overridden by the
   explanation provider.
8. The UI presents supportive care, precautions, referral prompts, emergency
   warnings, grounded explanation/review messaging, and a human-review
   disclaimer.
9. The check-up record is saved independently of remote guidance availability.

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
- RAG: active as bounded local TF-IDF vector plus keyword/metadata retrieval
  with traceable evidence; a persistent embedding/vector database is not yet
  implemented.
- LLM explanation: provider abstraction and mocked safety validation are
  implemented, but the provider remains disabled until an authorized HTTPS
  endpoint and clinical review are available.
- None of these paths may be described as clinically validated diagnosis.

Evidence: `docs/PHASE_3_AI_VERIFICATION.md`,
`docs/AI_VALIDATION_REPORT.md`, `backend/app/api.py`, and
`lib/app/core/services/disease_prediction_api_service.dart`.
