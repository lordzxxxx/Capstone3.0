# Deployment and final handoff checklist

## Build and configuration

- [ ] Confirm the intended Firebase project and production Firestore database.
- [ ] Provision a deployed HTTPS FastAPI host for `/guidance`.
- [ ] Set `APP_ENV=production`; the API refuses to start if Auth, App Check,
      revoked-token checks, HTTPS origins, or allowed hosts are missing.
- [ ] Set `API_ALLOWED_HOSTS` to the exact API hostname; never use `*`.
- [ ] Review `API_RATE_LIMIT_REQUESTS` and `API_RATE_LIMIT_WINDOW_SECONDS`;
      these limit traffic per client address before request parsing.
- [ ] Configure release `AI_API_BASE_URL`; never ship a localhost URL.
- [ ] Set `WEB_ALLOWED_ORIGINS` to the exact production Vercel origin in the
      FastAPI and password-reset environments; do not use a wildcard.
- [ ] Configure production Firebase Authentication providers.
- [ ] Configure production App Check provider, web site key, and allowed
  domains.
- [ ] Store service-account credentials outside the repository.
- [ ] Apply only clinically reviewed `symptom_guidance` documents.
- [ ] Confirm Firebase rules and indexes are deployed from the reviewed files.
- [ ] Confirm Cloud Functions use `FIRESTORE_DATABASE_ID=capstone-c98f9` and
      that reset/audit/rate-limit collections are not client-writable.
- [ ] Verify password reset revokes refresh tokens and returns generic account
      recovery messages for unknown addresses.
- [ ] Build the web artifact with `AI_API_BASE_URL` and
      `FIREBASE_APP_CHECK_WEB_KEY` set, using `npm run build:web:release`.
- [ ] Run `vercel build --prod` locally or in CI, then deploy the generated
      output with `vercel deploy --prebuilt --prod`; Flutter's generated
      `build/` directory is intentionally not committed to Git.

## Safety and validation

- [ ] Obtain qualified health-professional review of the manual validation set.
- [ ] Run real authenticated/App Check guidance requests in staging.
- [ ] Verify OCR requests require Firebase Auth and App Check, accept only
      valid JPEG/PNG/WebP images, and enforce the file, batch, and rate limits.
- [ ] Verify 401, 403, 422, 429, unavailable-backend, and emergency cases.
- [ ] Confirm Firebase Authentication's server-side `too-many-requests`
      response is retained for repeated password failures; the app cooldown is
      only an additional client-side backoff and must not be treated as the
      security boundary.
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
