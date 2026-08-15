# Deployment and final handoff checklist

## Build and configuration

- [ ] Confirm the intended Firebase project and production Firestore database.
- [ ] Provision a deployed HTTPS FastAPI host for `/guidance`.
- [ ] Configure release `AI_API_BASE_URL`; never ship a localhost URL.
- [ ] Configure production Firebase Authentication providers.
- [ ] Configure production App Check provider, web site key, and allowed
  domains.
- [ ] Store service-account credentials outside the repository.
- [ ] Apply only clinically reviewed `symptom_guidance` documents.
- [ ] Confirm Firebase rules and indexes are deployed from the reviewed files.
- [ ] Build web and Android release artifacts with the intended defines.

## Safety and validation

- [ ] Obtain qualified health-professional review of the manual validation set.
- [ ] Run real authenticated/App Check guidance requests in staging.
- [ ] Verify 401, 403, 422, 429, unavailable-backend, and emergency cases.
- [ ] Complete the real-form OCR accuracy table.
- [ ] Complete Android handset offline/reconnect testing.
- [ ] Complete iOS testing if iOS is in scope.
- [ ] Attach synthetic-data screenshots and test logs.
- [ ] Confirm all defense slides use the canonical metrics and limitations.

## Handoff and rollback

- [ ] Record the exact Git commit, build defines, Firebase project, and API
  host used for the defense build.
- [ ] Export the final test evidence bundle.
- [ ] Tag the reviewed release candidate only after the open release gates are
  closed or explicitly accepted by the project supervisor.
- [ ] Keep the previous working commit available for rollback.
- [ ] Do not commit Firebase secrets, patient data, or emulator exports.

Current status: repository implementation and local evidence are committed on
`main`; production deployment, clinical review, real-form OCR measurement, and
field testing remain open as recorded in `docs/E2E_TEST_LOG.md`.
