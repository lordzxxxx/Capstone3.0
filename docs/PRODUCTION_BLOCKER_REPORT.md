# AI-DSUHIS production blocker report

Date: 2026-10-15

Scope: web platform, FastAPI/backend infrastructure, Firebase services,
Cloud Functions, APIs, database/storage boundaries, synchronization, and
production operations. Follow-up local validation also covered the Flutter
application test suite and release web build; no physical-device, staging, or
production mobile verification was performed.

Mobile outbound synchronization was also hardened locally: Patient, Prenatal,
Immunization, Morbidity, and Mortality writes now restore the authenticated
barangay/role scope immediately before Firestore create, update, and retry
operations. This reduces scope drift for offline rows but does not replace a
real device offline/reconnect test.

This pass made local, uncommitted changes only. It did not push, deploy, or
modify the live system.

## Blocker 1 — `AI_API_BASE_URL`

**Description:** The Vercel production variable is empty. The web client passes
the value at compile time and uses it for `POST /guidance`; the backend also
exposes protected OCR endpoints at `/api/v1/ocr/handwriting` and
`/api/v1/ocr/handwriting/batch`.

**Root Cause:** The repository contains a FastAPI application and model files,
but no live HTTPS host or deployment credentials. The release build previously
allowed an empty value and produced a deliberately fail-closed client.

**Classification:** **C — BLOCKED BY USER/INFRASTRUCTURE ACTION.** A Cloud Run
project, billing, service-account permissions, and Vercel environment access
are required to create and publish the real endpoint.

**Action Taken:**

- Added `backend/Dockerfile` and `.dockerignore` for a non-root Cloud Run
  deployment containing only the API and model artifacts.
- Added ADC support to `backend/app/firebase_service.py`, so Cloud Run uses its
  attached service account instead of requiring a committed or uploaded JSON
  key.
- Included the runtime `backend/firebase/disease_schema.py` dependency in the
  container image after the first Cloud Run startup log exposed an incomplete
  deployment context; the Docker ignore rules now preserve that dependency.
- Narrowed the package import fallback so a future missing dependency reports
  its real cause instead of being masked by `No module named 'config'`.
- Added `GET /ready`, which checks the model and a Firestore read and returns a
  safe `503` when either dependency is unavailable.
- Added a production Vercel build guard that rejects an empty or non-HTTPS
  `AI_API_BASE_URL` before publishing a web artifact.
- Added a Firestore transaction-backed rate-limit option for staging and
  production. It stores only a namespace-scoped key digest, fails closed when
  the backend is unavailable, and requires a TTL policy on `expiresAt`.
- Documented the Cloud Run deployment and Vercel configuration in
  [AI_API_DEPLOYMENT.md](AI_API_DEPLOYMENT.md).

**Verification:** Backend tests pass locally (109/109), including readiness
failure handling, and the corrected archive contains
`backend/firebase/disease_schema.py`; shell syntax and the release build script
checks pass. The first Cloud Run revision failed before listening because that
file was omitted from the archive. No successful production HTTPS endpoint
exists yet, so the complete Web → FastAPI → Firestore/AI/OCR → Web flow is not
verified.

**Status:** **BLOCKED — USER ACTION REQUIRED**

**User Action Required:** Deploy the service, verify `/health` and `/ready`,
configure the exact HTTPS URL in Vercel Production, and trigger a new web
deployment. Follow [AI_API_DEPLOYMENT.md](AI_API_DEPLOYMENT.md).

## Blocker 2 — Firebase Storage

**Description:** Firebase Storage is not provisioned in project `capstone-c98f9`.
Branding uploads and referral attachments therefore cannot be tested against a
real bucket.

**Root Cause:** The Flutter SDK already points at
`capstone-c98f9.firebasestorage.app`, and rules exist, but the Firebase project
has no Storage bucket available for the CLI to deploy to.

**Classification:** **C — BLOCKED BY USER/PROJECT-OWNER ACTION.** Storage
provisioning and billing/location choices belong to the Firebase project owner.

**Action Taken:**

- Added `StorageUploadPolicy` for client feedback and consistent 5 MB branding
  and 10 MB referral limits, with allowed MIME types and matching extensions.
- Kept server-authoritative Storage Rules for authentication, role, ownership,
  path safety, size, and MIME type.
- Prevented direct doctor reads of another owner's referral attachment. The
  current named Firestore database cannot be safely consulted by a direct
  Storage rule for assignment-aware access, so added the App Check-enforced
  `getReferralAttachmentDownloadUrl` callable. It verifies the referral,
  assignment/CHO permission, declared storage path, and object existence before
  returning a ten-minute signed URL; the Doctor Portal now uses that callable.
- Added owner/CHO deletion for referral files and made the web attachment
  removal action delete the object instead of leaving an orphan.
- Added emulator coverage for unauthorized doctor read/delete behavior.

**Verification:** The Storage Rules emulator suite passes 6/6, covering
authenticated role/ownership behavior and unauthorized doctor read/delete
attempts. The new server authorization helpers pass 5/5 unit checks, the
Functions lint/index load passes, and the Doctor Portal compiles with the
callable integration. A real upload, signed download, replace/delete cycle,
and bucket-level permission test remain unverified because the production
bucket does not exist.

**Status:** **BLOCKED — USER ACTION REQUIRED**

**User Action Required:** Provision Storage and run the validation checklist in
[FIREBASE_STORAGE_RUNBOOK.md](FIREBASE_STORAGE_RUNBOOK.md). Do not loosen the
rules to public read/write.

## Blocker 3 — authenticated role test accounts

**Description:** Emulator QA identities exist, but production-like login,
logout, CRUD, role enforcement, session expiry, App Check, and account
revocation still require approved staging or controlled production test
accounts.

**Root Cause:** Those checks require real Firebase Authentication, approved
Firestore profiles, App Check attestation, and evaluator-owned credentials.

**Classification:** **C — BLOCKED BY USER/ACCOUNT-OWNER ACTION.** The test
identities and supported-browser App Check credentials must be approved and
controlled outside the repository.

**Action Taken:** The existing emulator matrix was retained and documented
with four least-privilege roles: BHW, CHO, Doctor, and CHO Super Admin. The
matrix explicitly tests allowed and denied actions, direct URLs, refresh,
logout, disabled accounts, password reset, role changes, and App Check.

**Verification:** The web-only Playwright suite passes 42/42 across desktop,
tablet, and mobile-sized Chromium viewports against local Auth/Firestore
emulators. Callable integration and backend rules also pass with seeded
emulator identities. The Flutter suite separately passes 220/220 tests and the
release web build succeeds. Real production/staging identities and App Check
have not been used in this pass.

**Status:** **IMPLEMENTED — VERIFICATION REQUIRED**

**User Action Required:** Create the dedicated accounts and complete the
matrix in [PRODUCTION_TEST_ACCOUNT_MATRIX.md](PRODUCTION_TEST_ACCOUNT_MATRIX.md).
Use synthetic records only; do not use real patient accounts.

## Blocker 4 — Cloud Functions runtime

**Description:** The Functions runtime needed to move off the older Node.js
20 configuration before the 2026-10-30 decommission date.

**Root Cause:** The runtime and Functions SDK had not been upgraded, and the
legacy Admin SDK namespace APIs were not compatible with the target major.

**Classification:** **A — IMPLEMENTED IN THE CODEBASE.** The version change can
be reviewed and tested locally; the controlled staging deployment remains a
release verification step.

**Action Taken:** Updated `functions/package.json` and the lockfile to Node.js
22, `firebase.json` to `runtime: nodejs22`, `firebase-admin` to 14.5.0,
`firebase-functions` to 7.4.0, and `nodemailer` to 10.1.1. Migrated the
active Functions and bootstrap utilities to the modular Admin SDK APIs while
preserving v1 callable handler contracts and v2 Firestore triggers. The
one-time CHO bootstrap utility now uses Application Default Credentials instead
of requiring a local `serviceAccount.json` file, and rejects invalid bootstrap
input with a non-zero exit code.

**Verification:** Both root and Functions production audits report zero
vulnerabilities. JavaScript syntax/lint and Functions index loading pass. The
local Auth, Firestore, Realtime Database, and Functions emulator suites pass
for BHW management, doctor workflows, RBAC, doctor access links, automatic
referral routing, and doctor account management. The upgraded runtime has not
been deployed, so staging deployment remains required.

**Status:** **IMPLEMENTED — VERIFICATION REQUIRED**

**User Action Required:** Deploy the Functions change in a controlled release
after running the runtime checklist; do not mix it with unrelated production
changes.

## Blocker 5 — load/performance testing

**Description:** No authenticated staging load evidence exists for the web,
API, database, uploads, synchronization, or OCR paths.

**Root Cause:** There is no approved non-production target or test account/token
available in this checkout.

**Classification:** **B — REQUIRES CONTROLLED INFRASTRUCTURE CONFIGURATION.**
The harness is local and safe, but authenticated workload evidence requires an
approved staging target and synthetic credentials.

**Action Taken:** Added `tools/load_test_api.py`, a dependency-free probe with
latency percentiles, throughput, status counts, timeout handling, secret-safe
headers, and a hard remote-target confirmation/cap. It defaults to local
`/health` and never runs against a remote target accidentally.

**Verification:** Help output and safety checks pass. Only local unauthenticated
health probing is safe to run without an approved target; AI/OCR and CRUD load
tests remain pending.

**Status:** **IMPLEMENTED — VERIFICATION REQUIRED**

**User Action Required:** Run the documented staging plan in
[LOAD_AND_OPERATIONS_TEST_PLAN.md](LOAD_AND_OPERATIONS_TEST_PLAN.md), then tune
Cloud Run memory, concurrency, and limits using the measured results.

## Blocker 6 — backup and restore

**Description:** A successful isolated Firestore and Storage restore has not
been evidenced.

**Root Cause:** Backup schedules, retention, IAM access, Storage protection,
and a non-production restore environment require project-owner permissions and
cannot be safely inferred from source code.

**Classification:** **C — BLOCKED BY USER/PROJECT-OWNER ACTION.** Provider
 backup features and IAM permissions must be enabled outside the repository.

**Action Taken:** Prepared a non-destructive backup/restore procedure covering
Firestore scheduled backups, Storage soft delete/versioning, rules/config
inventory, integrity checks, and restore to a new database.

**Verification:** No live backup or restore mutation was attempted.

**Status:** **BLOCKED — USER ACTION REQUIRED**

**User Action Required:** Complete [BACKUP_RESTORE_RUNBOOK.md](BACKUP_RESTORE_RUNBOOK.md)
with a project owner and attach the restore evidence before approval.

## Blocker 7 — clinical approval

**Description:** The system recognizes symptoms and displays supportive
guidance and health-category decision support. It must not be treated as a
diagnostic or autonomous treatment system.

**Root Cause:** Clinical content approval is a human governance requirement,
not a software test. Active seed documents are not proof of clinician review.

**Classification:** **D — EXTERNAL HUMAN APPROVAL REQUIRED.** A licensed
 clinical owner must review and sign off the outputs and safety boundaries.

**Action Taken:** Identified the backend `/guidance` output, the local health
classifier, emergency warnings, medication-wording filter, OCR review boundary,
and the disabled legacy prediction route. Prepared a reviewer checklist that
requires a licensed health professional to review content, safety boundaries,
and referral behavior.

**Verification:** Automated safety and contract tests pass; no clinical
approval has been claimed.

**Status:** **EXTERNAL APPROVAL REQUIRED**

**User Action Required:** Obtain sign-off from the designated physician/CHO
clinical owner using [CLINICAL_REVIEW_CHECKLIST.md](CLINICAL_REVIEW_CHECKLIST.md).

## Blocker 8 — production monitoring

**Description:** The web platform, FastAPI service, Functions, Firebase, and
Storage need observable errors, latency, availability, and operational alerts
for the two-month evaluation window.

**Root Cause:** Source logging existed, but there was no complete cross-service
monitoring runbook or readiness check.

**Classification:** **B — REQUIRES INFRASTRUCTURE CONFIGURATION.** The code now
 emits safe signals, while uptime checks, alert policies, retention, and
 notification routing must be configured in the providers.

**Action Taken:** Added payload-free JSON request logs with correlation IDs,
status, path, and latency; added `/health` liveness and `/ready` dependency
readiness; documented Cloud Run, Functions, Vercel, Firebase, uptime, alert,
retention, and privacy configuration.

**Verification:** Backend request-ID/readiness tests pass. Cloud alert policies,
uptime checks, and real AI/Storage failure alerts are not configured or
verified from this checkout.

**Status:** **IMPLEMENTED — VERIFICATION REQUIRED**

**User Action Required:** Apply [PRODUCTION_MONITORING_RUNBOOK.md](PRODUCTION_MONITORING_RUNBOOK.md)
and perform an alert test without logging health data or credentials.

## Updated assessment

**NOT READY FOR PRODUCTION.** The local code is prepared for controlled staging,
but the live AI host, Storage bucket, authenticated account/App Check evidence,
backup restore evidence, load results, monitoring alerts, and clinical sign-off
are still release gates.

### Remaining blockers in priority order

1. Deploy and verify the HTTPS FastAPI service, then set Vercel Production
   `AI_API_BASE_URL` and rebuild the web artifact.
2. Provision Firebase Storage and verify upload/download/delete behavior with
   the restricted rules.
3. Create approved synthetic staging identities and complete the authenticated
   RBAC/App Check matrix.
4. Deploy and verify the Node.js 22 Functions runtime in staging.
5. Run bounded staging load and failure tests for API, database, uploads, OCR,
   and synchronization.
6. Enable backups and complete an isolated restore test.
7. Obtain clinical approval for all guidance and classification outputs.
8. Configure and exercise production monitoring and alerting.

## Verification snapshot

- FastAPI: 109 tests passed; two non-blocking Starlette/httpx deprecation
  warnings remain. The scikit-learn model/runtime mismatch is resolved by the
  pinned 1.9.0 backend dependency.
- Firestore Rules: 33 tests passed.
- Storage Rules: 6 tests passed.
- Web regression: 42 tests passed across desktop, tablet, and mobile-sized
  Chromium viewports.
- Flutter: 220 tests passed and the release web build completed successfully;
  physical-device behavior and production mobile services remain unverified.
- Flutter analyzer: 311 non-error warnings/info findings remain, but the
  async-context lifecycle findings are now cleared across the audited clinical
  workflows. Remaining findings are primarily legacy debug prints and unused
  compatibility UI helpers.
- Web release build: passed with a staging placeholder AI URL and App Check
  value; the production build guard rejects missing, non-HTTPS, local-host,
  and trailing-slash AI URLs for Vercel production/preview builds.
- Functions: Node 22 lockfile install, lint, syntax checks, zero high/critical
  audit findings, and six callable emulator suites passed locally. The
  bootstrap utility syntax/lint and invalid-input smoke check also pass. The
  upgraded runtime is not deployed.
- FastAPI liveness probe: 50/50 local `/health` requests succeeded at
  concurrency 5, with approximately 28 ms p95 latency after separating
  liveness from model/Firestore readiness.
- Docker image: not built because Docker was unavailable on this machine;
  `backend/Dockerfile` was reviewed and Python syntax checks passed.
