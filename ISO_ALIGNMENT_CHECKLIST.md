# AI-DSUHIS — ISO Alignment Checklist

**This document uses ISO/IEC 25010:2023, ISO/IEC 27001:2022, ISO
27799:2025, and ISO/IEC 42001:2023 only as quality-evaluation reference
frameworks. AI-DSUHIS is not certified, has not undergone a formal audit
against any of these standards, and this document makes no certification
claim.** Every row below is backed by a specific file/line in this
repository — check the "Evidence" column before relying on any row.

---

## Part 1 — ISO/IEC 25010:2023 product quality characteristics

| Quality Area | Current Implementation | Evidence | Test | Status |
|---|---|---|---|---|
| **Functional suitability** | `/guidance` recognizes symptoms/conditions, retrieves reviewed Firestore self-care content, and suggests a rule-based health category; on-device classifier assigns checkup/prenatal category+severity | `backend/app/api.py` (`guidance_endpoint`), `lib/app/core/services/health_ai_classifier.dart` | `backend/tests/test_api.py`, `backend/tests/test_symptom_guidance.py`, `backend/tests/test_health_category_service.py` — 63 backend tests pass | ✅ Implemented, tested |
| **Performance efficiency** | A single Random Forest fit (300 trees, 75,194 rows, 229 features) completes in ~4s; a full `predict_proba` call over a single request is sub-100ms in this environment | Measured directly during this review (`backend/scripts/optimize_random_forest.py` run) | Manual timing, this review | ✅ Measured, no formal SLA documented in-repo |
| **Compatibility** | Backend is a standard FastAPI service (JSON over HTTP); Flutter client targets Web, Android, iOS, desktop from one codebase | `backend/app/api.py`, `pubspec.yaml` targets | `flutter test` — 32 tests pass across widget/unit suites | ✅ |
| **Interaction capability / usability** | Landing/portal UI uses a single established design system (Mont font, fixed color tokens, existing component library); disclaimers shown on every AI response (`DISCLAIMER` constant) | `backend/app/api.py: DISCLAIMER`, `lib/web/features/auth/landing.dart` and shared widget files | Manual UI verification (prior sessions); no automated visual-regression suite in-repo | ⚠️ Manually verified only — no automated accessibility/usability test suite present |
| **Reliability** | `/guidance` returns typed error responses (422/503) rather than crashing on bad input or Firestore outage; `NoRecognizedSymptomsError`, `ArtifactLoadError` are handled explicitly; on-device classifier falls back to rule-based scoring if the neural net throws | `backend/app/api.py` (try/except blocks around Firestore calls), `health_ai_classifier.dart: classify()` (try/catch around `_mlModelClassify`) | `backend/tests/test_api.py` covers the 422/503 paths | ✅ |
| **Security** | Firebase ID token + App Check required on every AI request; sliding-window rate limiting; restrictive CORS; Firestore/Storage rules enforce role-based, barangay-scoped, doctor-note-specific access | `backend/app/security.py`, `firestore.rules`, `storage.rules` | `backend/tests/test_security.py` | ✅ — see Part 2 for detail |
| **Maintainability** | Clear module boundaries (`predict.py`/`train.py`/`api.py`/`security.py` each single-purpose); reproducible dataset pipeline (`merge_datasets.py`, verified MD5-identical regeneration during this review); typed Pydantic schemas define every API contract | `backend/app/*.py`, `backend/scripts/*.py`, `backend/app/schemas.py` | This review regenerated `merged_dataset.csv` from source and confirmed byte-identical output | ✅ |
| **Flexibility (portability/scalability)** | Confidence threshold, rate limits, Firebase auth/App-Check requirements are all environment-variable-configurable (`config.py`); model/feature paths are configurable, not hardcoded | `backend/app/config.py: get_settings()` | Config defaults verified by reading `config.py` directly | ✅ |
| **Safety** | Medication/dosage/prescription wording is actively stripped from every AI-sourced guidance string at the response boundary (both backend and on-device); `/predict` (disease diagnosis) is disabled; AI output is explicitly framed as decision support, not diagnosis | `backend/app/api.py: _safe_guidance_strings()`, `_MEDICATION_GUIDANCE_PATTERN`; `health_ai_classifier.dart: _safeGuidanceItems()`, `_isMedicationInstruction()`; `DISCLAIMER` string | Re-verified during this review (regex patterns read directly, unchanged) | ✅ |

---

## Part 2 — Information security alignment (ISO/IEC 27001:2022 / ISO 27799:2025 concepts)

ISO 27799 specifically concerns health-information security management;
reviewed here as a lens on how patient/clinical data is protected, not as
a certification claim.

| Control area | Current Implementation | Evidence | Status |
|---|---|---|---|
| **Authentication** | Every AI request requires a valid Firebase ID token (`Authorization: Bearer <token>`), verified server-side via `firebase_admin.auth.verify_id_token(...)` with revocation checking enabled by default | `backend/app/security.py: require_ai_access()` | ✅ |
| **Application attestation** | Firebase App Check required in addition to user auth — reCAPTCHA v3 (web), Play Integrity (Android release), App Attest + DeviceCheck fallback (iOS release); release web builds **fail to start** if the App Check key is missing (fail-closed, not fail-open) | `lib/firebase_app_check_bootstrap.dart` | ✅ |
| **Authorization / least privilege** | Firestore rules define per-collection, per-role functions (`isChoRole()`, `isBhwRole()`, `isDoctorRole()`, `isSuperAdmin()`); records are further scoped by barangay (`sameBarangay()`, `canReadBarangayScopedRecord()`) so a BHW cannot read another barangay's patient data | `firestore.rules` lines 167–271, 330+ | ✅ |
| **Clinical-record confidentiality** | Doctor notes: read restricted to CHO, the authoring doctor, or a BHW in the *same barangay*; create restricted to CHO/doctor and must match `authorUid` | `firestore.rules: canReadDoctorNote()`, `canCreateDoctorNote()` (lines 249–257) | ✅ |
| **Doctor-note protection specifically** | Same as above — doctor notes are a distinct, more restrictively-scoped collection type from general patient records, not merely covered by the general barangay rule | `firestore.rules` lines 249–257 | ✅ |
| **Referral confidentiality** | Referral read access limited to CHO, the specifically assigned doctor, or the BHW who created it; referral attachments in Cloud Storage require matching `ownerUid` or an allow-listed CHO/doctor role token, capped at 10MB, restricted to PDF/JPEG/PNG content types, and are immutable after upload (`update, delete: if false`) | `firestore.rules: canReadReferral()` (260–265); `storage.rules: /referral_attachments/...` | ✅ |
| **Data integrity** | Storage rules deny all writes/reads outside explicitly matched paths by default (`match /{allPaths=**} { allow read, write: if false; }`); protected user-profile fields cannot be altered by the profile owner on update (`preservesProtectedUserFields()`) | `storage.rules` (final block); `firestore.rules: preservesProtectedUserFields()` | ✅ |
| **Availability** | Rate limiting (`SlidingWindowRateLimiter`, default 30 req/60s per user) protects the AI endpoint from being overwhelmed by a single client; Firestore lookup failures degrade gracefully to a partial response rather than a hard failure | `backend/app/security.py`, `backend/app/api.py` (Firestore `try/except` blocks) | ✅ |
| **Auditability** | A dedicated `audit_logs` Firestore collection exists, readable only by CHO from the client and writable only by trusted backend Admin-SDK processes (never client writes) — comment in-rule confirms this is by design | `firestore.rules` lines 730–737 | ✅ — confirms an audit trail exists; this review did not verify which specific events are written to it (that logic lives in Cloud Functions/backend code outside this review's scope) |
| **Role management** | Roles are read from the Firebase Auth custom-claims token (`request.auth.token.role` / `.roles`), not from client-supplied data, in both Firestore and Storage rules | `firestore.rules: tokenRole()`, `storage.rules: tokenRole()` | ✅ |
| **Secure configuration defaults** | `require_firebase_auth`, `require_app_check`, and `check_revoked_tokens` all default to `True` in `config.py` — the system is secure-by-default and requires explicit opt-out via environment variable, not explicit opt-in | `backend/app/config.py: get_settings()` | ✅ |
| **Backup/recovery** | Not implemented or documented in this repository — Firestore/Firebase Hosting's platform-level backup and durability guarantees apply, but no project-specific backup/restore tooling or documented recovery procedure exists in-repo | — | ⚠️ Not found in repository — outside this review's ability to confirm or deny at the infrastructure level |

**No security control was weakened during this review.** All findings
above are read-only observations of existing rules and code; the only
new file added to the security-relevant surface is
`backend/scripts/optimize_random_forest.py`, a local research script with
no network exposure, no route registration, and no production wiring.

---

## Part 3 — Responsible-AI alignment (ISO/IEC 42001:2023 concepts)

| Item | Verified answer | Evidence |
|---|---|---|
| **Intended purpose** | Decision support for BHW/CHO staff — symptom recognition, reference guidance retrieval, coarse category/severity triage support. **Not** a diagnostic device; disclaimed as such on every response. | `backend/app/api.py: DISCLAIMER` |
| **Input variables** | Documented exhaustively in `AI_VARIABLE_DICTIONARY.md` | — |
| **Output variables** | Documented exhaustively in `AI_VARIABLE_DICTIONARY.md` | — |
| **Model version** | Production: `disease_model.pkl` (untouched by this review). Experimental candidate produced during this review: `disease_model_v2_candidate.pkl` (see `MODEL_EVALUATION_REPORT.md`), explicitly **not** wired into production. | `backend/models/`, `backend/models/experiments/` |
| **Dataset version** | `merged_dataset.csv`, 93,993 records — unchanged by this review (no legitimate expansion was found; see `DATASET_QUALITY_REPORT.md` §3) | `backend/dataset/processed/merged_dataset.csv` |
| **Evaluation evidence** | `backend/models/training_metrics.json` (production); `backend/reports/rf_optimization_final_report.json` and related CSVs (experimental candidate, this review) | See `MODEL_EVALUATION_REPORT.md` |
| **Known limitations** | Documented in `AI_ALGORITHM_QA.md` §17 and `DATASET_QUALITY_REPORT.md` §9 — unverified dataset provenance, inherent symptom-overlap ceiling (9.8% of rows share an ambiguous symptom vector with another disease), no Philippine-specific validation, no clinical validation, mild class imbalance | — |
| **Human oversight** | Doctors remain the decision-makers for medication/clinical action; AI output is explicitly labeled decision-support with a disclaimer; low-confidence predictions are flagged (`confidenceThresholdMet`, `LOW_CONFIDENCE_WARNING`) rather than presented as certain | `backend/app/api.py` | 
| **Medication restriction** | Enforced at the response boundary by regex filtering (`_safe_guidance_strings`, `_isMedicationInstruction`) in both the backend and the on-device classifier — re-verified unchanged during this review | `backend/app/api.py`, `health_ai_classifier.dart` |
| **Uncertainty handling** | `/guidance` returns `ignoredKeywords`/HTTP 422 when nothing is recognized rather than guessing; the disabled `/predict` path (if ever re-enabled) carried a `confidenceThresholdMet` flag; the on-device rule-based fallback activates automatically if the neural network throws | `backend/app/predict.py: NoRecognizedSymptomsError`; `backend/app/api.py`; `health_ai_classifier.dart: classify()` |
| **Traceability** | Every claim in this document and its companions (`AI_ALGORITHM_QA.md`, `AI_VARIABLE_DICTIONARY.md`, `DATASET_QUALITY_REPORT.md`, `MODEL_EVALUATION_REPORT.md`) is tied to a specific file/line/artifact, generated during this review from live code and live model objects — not from memory or assumption | This document set |
| **Change history** | This review's changes are isolated to: one new experimental script (`backend/scripts/optimize_random_forest.py`), new report artifacts under `backend/reports/` and `backend/models/experiments/`, and new root-level documentation files. No production file (`disease_model.pkl`, `api.py` routes, `predict.py` defaults) was modified. | Git diff at time of commit — see repository history |

**The AI in this system remains decision-support only. Doctors remain
the human decision-makers for medication and clinical action, both
before and after this review.**
