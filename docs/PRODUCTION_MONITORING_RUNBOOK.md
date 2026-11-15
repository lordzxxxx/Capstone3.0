# Production monitoring runbook

Monitoring must support the two-month evaluation without recording passwords,
Firebase tokens, OCR images, symptom lists, patient names, or other health
information unnecessarily.

## Signals

- Vercel: deployment status, website availability, failed asset/API requests,
  browser console errors, and route-level web errors.
- Cloud Run: `/health` uptime, `/ready` readiness, request count, 4xx/5xx rate,
  p50/p95 latency, instance count, CPU, memory, timeouts, and container restarts.
- FastAPI JSON logs: `requestId`, method, path, status, latency, and safe event
  names. The new middleware intentionally excludes bodies and auth headers.
- Firebase Functions: execution errors, duration, retries, and failed callable
  operations.
- Firebase Auth/Firestore/Storage: sign-in failures, permission denials,
  database errors, slow reads, upload failures, and quota/billing warnings.
- AI/OCR: `/ready` failures, protected endpoint 401/403/429/503 rates, model
  load failures, OCR unavailable events, and timeout rate.

## Configure checks

1. Add an uptime check for the final HTTPS API `/health` endpoint. Add a second
   readiness check for `/ready` with an alert that distinguishes dependency
   failure from process liveness.
2. Add alerts for sustained 5xx, repeated readiness failures, authentication
   failure spikes, Storage permission/upload errors, Function failures, and
   p95 latency above the staging-established threshold.
3. Route alerts to the project owner and technical operator; document who
   acknowledges and who can roll back.
4. Set log retention and access according to the organization's health-data
   policy. Restrict log access to operators who need it.
5. Perform one controlled alert test using a synthetic failure or temporarily
   disabled staging dependency. Confirm the alert reaches the operator and the
   test is removed.

## Incident response

For a critical error: stop further release changes, preserve the request ID and
revision metadata (not payloads), compare with the last known good revision,
and use the platform rollback procedure. Do not diagnose a patient from logs.
For suspected data inconsistency, stop writes to the affected workflow and
follow the backup/restore and clinical escalation runbooks.
