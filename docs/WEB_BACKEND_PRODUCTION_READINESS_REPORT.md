# AI-DSUHIS Web and Backend Production-Readiness Report

Date: 2026-09-15

Scope: Flutter web, FastAPI, Firebase Authentication, Firestore, Storage,
Cloud Functions, APIs, server-side synchronization, and production
configuration. The mobile application was not built, launched, or tested.

## Executive assessment

Status: **Not yet ready for production deployment**.

The local web/backend code is materially safer and more reliable than the
starting point, and the main automated security and backend checks pass. A
production release is still blocked by deployment and operational gates that
cannot be proven from this local checkout: a provisioned HTTPS AI API host,
production Firebase/App Check configuration, live rule/index/function
verification, clinical approval of guidance content, load testing, and backup
restore evidence.

## Live release status

- Commit `122372c` was pushed to `origin/main`.
- Vercel production deployment `dpl_CqBXY5wQyvXqn1E7SraJqWak58YF` completed
  with status **Ready** and is aliased to `ai-dsuhis.com` and
  `www.ai-dsuhis.com`.
- The live site serves `app-version.json` as `122372c`, returns HTTP 200 for
  public/deep-link routes, and redirects anonymous protected routes to login.
- Firestore rules, `processInvitation`, and `validateRegistrationPolicy` were
  deployed to Firebase project `capstone-c98f9`.
- Storage rules were not deployed because Firebase Storage is not provisioned
  on the production project. No Storage bucket or data was created.
- The Vercel production `AI_API_BASE_URL` is empty. Remote AI guidance is
  therefore unavailable in the live web build by design; the client fails
  closed instead of calling localhost. A real HTTPS API host is still required.

## 1. Problems identified

- BHW nested Firestore reads were checked against the user profile and path,
  but the web query did not include the matching `barangayCode` filter. Secure
  rules therefore rejected valid list queries.
- Firestore authorization could use stale custom claims or a privileged email
  path instead of the active Firestore profile. This created role and scope
  drift risk.
- BHW scope checks could fall back from a contradictory `barangayCode` to a
  matching name, weakening the canonical scope boundary.
- CHO user-list access was not consistently tied to the explicit
  `cho.users.view` permission.
- Storage uploads allowed a write path that did not explicitly prevent an
  overwrite after the first upload.
- OCR returned a successful empty result when its model was unavailable, and
  model failures were not translated into a stable client response.
- Some server and client logs could include email addresses, raw exception
  text, or broader record payloads than needed for troubleshooting.
- The release environment example did not document the Flutter web API and
  App Check build inputs and used a Windows-only credential path.

## 2. Bugs fixed

- Added the exact BHW `barangayCode` filter to scoped web record queries.
- Changed Firestore role checks to use the active, approved Firestore user
  profile as the authorization source of truth.
- Removed the hardcoded privileged-email bypass from Firestore rules.
- Required CHO user-list reads to have `cho.users.view`.
- Added path-and-record scope agreement for BHW nested records.
- Made branding and referral files immutable after creation.
- Made OCR fail closed with HTTP 503 when the model is not ready, when model
  execution fails, or when a batch returns the wrong result count.
- Converted the symptom catalog artifact failure into a safe HTTP 503.
- Made invitation account creation retry only for `auth/user-not-found`; other
  Auth failures now stop instead of risking duplicate-account behavior.

## 3. Security improvements

- Firestore now validates active profile role, approval, account status,
  permissions, and barangay scope server-side.
- BHW nested reads and writes require both the requested barangay path and the
  stored record scope to agree.
- Branding writes require a CHO-admin claim, an allowed image MIME type, a
  path-safe filename, and a 5 MB limit. Referral attachments require the
  owner, allowed file type, path-safe identifiers, and a 10 MB limit.
- Existing API protections were retained and verified: Firebase Auth,
  App Check, revoked-token checks, exact CORS origins, trusted hosts, request
  size limits, OCR content validation, security headers, and rate limiting.
- Production client errors no longer expose raw App Check, token, Firestore,
  or model exception details.
- Invitation and account-policy logs no longer record unnecessary email or
  raw error details.

## 4. Performance improvements

- Symptom guidance now batch-reads Firestore documents instead of performing
  one sequential read per symptom, while retaining a compatibility fallback
  for older test doubles.
- OCR inference remains off the FastAPI event loop through the thread pool.
- Existing web queries use scope-specific paths and bounded queries in several
  high-volume areas; the BHW query fix also prevents rejected/retried reads.

Remaining performance work is listed below because several CHO dashboard
streams still aggregate large collections in memory.

## 5. Database improvements

- Firestore rules now enforce the database as the authority for profile role,
  permissions, approval, and barangay scope.
- Existing Firestore indexes were reviewed and retained for doctor notes,
  checkups, and patient history.
- Nested record reads now use the same canonical path and code constraint as
  writes, reducing inconsistent cross-path records.
- No destructive data migration was performed.

## 6. API/backend improvements

- OCR endpoints now provide predictable `503 Service Unavailable` behavior for
  missing or failing model infrastructure.
- The symptom catalog endpoint no longer leaks an artifact-loading failure.
- Server logs retain event names and safe operational counts without storing
  patient payloads or credentials in the changed paths.
- Invitation processing now distinguishes a missing account from network,
  permission, and other Firebase failures.
- Production configuration remains fail-closed for Auth, App Check, revoked
  tokens, explicit hosts, and explicit browser origins.

## 7. Synchronization improvements

- Web BHW reads now use the same normalized barangay code in the Firestore path,
  query, and rules.
- The existing web record synchronization layer was verified in code for stable
  IDs, client operation IDs, version checks, server timestamps, idempotent
  create handling, and conflict reporting.
- Backend-facing mobile synchronization was reviewed only from the API,
  Firestore, and Storage side. The mobile app and emulator were not run.
- Storage overwrite protection prevents a repeated upload from silently
  replacing the original attachment.

## 8. Codebase cleanup performed

- Removed raw exception and full-record logging from the changed web checkup
  path.
- Removed sensitive detail from changed Cloud Function logs and invitation
  error documents.
- Added a centralized OCR readiness/error response path rather than repeating
  inconsistent endpoint behavior.
- Updated `.env.example` with cross-platform server credential guidance and
  documented web release inputs.
- Preserved unrelated existing worktree changes and did not delete source code,
  user data, mobile code, or production records.

## 9. Remaining risks and limitations

- The production HTTPS FastAPI host is not provisioned or live-verified in this
  checkout. `AI_API_BASE_URL` must not be empty or localhost in release.
- Production Firebase App Check/Auth and hosting origin were reachable, but
  headless smoke testing received the expected third-party reCAPTCHA/App Check
  403 and cannot prove a real browser attestation. Firestore rules and the two
  changed Functions are deployed; Storage is not provisioned, and indexes,
  API CORS/TrustedHost, and authenticated production workflows still need
  direct verification.
- In-process API rate limiting is suitable for one process but is not a
  distributed limit when the API is scaled across multiple workers or hosts.
- Several CHO dashboard listeners and some archive queries remain unbounded or
  aggregate many records in memory. They need pagination, time windows, or
  server-side summaries before record volume grows substantially.
- The Firestore REST reader currently performs one bounded query and does not
  paginate beyond its requested page size; large support-center lists need a
  cursor/pagination design.
- The legacy Realtime Database mirror still uses claim-based compatibility
  rules and must not be treated as the authoritative database.
- The TrOCR model artifact/download, model checksum, memory use, timeout, and
  concurrent-request capacity need production load validation.
- Clinical review and approval of guidance content and health-category rules
  remain external release gates.
- Real browser tests use Firebase emulators and seeded QA identities. They do
  not prove production credentials, inbox delivery, real storage, or live
  deployment behavior.

## 10. Tests and validations performed

- Backend: `93 passed` with the project virtual environment; six dependency
  warnings remain (Starlette/httpx deprecation and scikit-learn model/runtime
  version mismatch).
- Firestore rules: `32 passing` with the local emulator.
- Storage rules: `4 passing` with the local emulator.
- Cloud Functions syntax/lint: passed with `npm --prefix functions run lint`.
- Focused web browser regression for BHW canonical routes: `1 passed` after
  the scope-query fix.
- Full web browser matrix: `42 passed` across desktop, tablet, and
  mobile-width browser projects; this tested the web layout/runtime only, not
  the mobile application.
- Workflow persistence: `1 passing` through a live Firestore emulator, covering
  the BHW referral -> CHO assignment -> doctor consultation/note -> BHW
  history synchronization path.
- Callable integration: doctor-account creation passed with local Auth,
  Firestore, and Functions emulators.
- Web release build: succeeded with non-production placeholder values; the
  real production API host and App Check site key still must be supplied at
  release time.
- Dart formatting: passed for the changed Dart files using the installed Dart
  SDK directly.
- No mobile build, emulator, or mobile runtime was started.
- Live web smoke: public routes and deep links returned HTTP 200, anonymous
  `/bhw/patients` redirected to `/login`, invalid login returned a safe error,
  and no page exceptions were observed. Headless reCAPTCHA/App Check produced
  a third-party 403/aborted request, so authenticated App Check flows remain
  unverified.

## 11. Production-readiness assessment

The local code is **ready for controlled staging/UAT review**, but the overall
system is **not yet ready for production deployment**. The remaining blockers
are mostly live-environment, operational, scale, and clinical-validation
requirements rather than a known unauthenticated Firestore/Storage path in the
tested rules.

## 12. Recommended actions before deployment

1. Provision and health-check the HTTPS AI API host; set exact
   `API_ALLOWED_HOSTS`, `WEB_ALLOWED_ORIGINS`, and web `AI_API_BASE_URL`.
2. Configure and verify production Firebase App Check, Auth, Firestore,
   Storage, Functions, indexes, and hosting rules.
3. Pin the Python dependency/model build together; resolve the scikit-learn
   model/runtime version mismatch and record the artifact checksum.
4. Add distributed rate limiting at the edge or API gateway before using more
   than one backend process.
5. Add pagination or server-side summaries for unbounded CHO/archive queries.
6. Run a staging load test covering login, list/search/filter, CRUD, OCR,
   uploads, Cloud Functions, and simultaneous synchronization.
7. Test backup/restore and define monitoring, alerting, log retention, and
   rollback procedures for the two-month evaluation period.
8. Provision Firebase Storage before enabling attachment/branding workflows;
   deploy and verify `storage.rules` only after the bucket exists.
9. Obtain clinical/content approval and document the decision-support
   limitations before exposing guidance to evaluators.
10. Upgrade Cloud Functions from Node.js 20 before its 2026-10-30
    decommissioning date and update the Firebase Functions SDK in a separate
    tested release.
11. Run a final authenticated staging smoke test with real production-like
   configuration. Keep mobile verification limited to backend/API/database
   synchronization as required by this task.

The reviewed code was committed as `122372c` and pushed. Vercel web
deployment and the reviewed Firebase rules/Functions deployment completed.
The Storage deployment was intentionally skipped because the production
bucket is not provisioned.
