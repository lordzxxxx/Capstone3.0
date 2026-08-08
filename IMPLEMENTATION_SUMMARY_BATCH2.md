# Smart Health Integration — Implementation Summary (Batch 2, August 2026)

This document describes the **actual, verified** state of the system after the
August 2026 panel-revision pass. Every component listed here was confirmed
directly against the source code — nothing below is aspirational or assumed.
Where provenance could not be independently verified (the ML dataset's exact
external source), that is stated explicitly rather than guessed.

---

## 1. System Purpose

Smart Health Integration is a unified health information system for
barangay-level primary care in the Philippines. It supports:

- Patient-record management with offline-first data entry and Firestore
  synchronization.
- Continuity of care across consultations, via a shared patient health
  timeline and append-only doctor notes.
- Health-worker (BHW) and doctor collaboration through a referral workflow
  with availability-aware doctor assignment.
- Health reporting: bulk period reports and single-record PDFs, filterable by
  date range, doctor, and status.
- AI-assisted, **non-prescriptive** home-care guidance generated from
  patient-reported symptoms — supportive information only; all medication
  and clinical decisions remain with the attending physician.

It is **not** an automated diagnosis or prescription system. The trained
disease-prediction model described in Section 5 exists and is evaluated, but
its inference endpoint is intentionally disabled in production.

---

## 2. Verified Technology Stack

**Frontend:** Flutter 3.44.9 / Dart 3.12.2. Two separate frontend
implementations share one codebase: `lib/web/*` (browser, selected when
`kIsWeb` is true) and `lib/app/*` (mobile/desktop). State/navigation uses
`GetX`, with manual role-based routing layered on top — no other
state-management framework was introduced.

**Firebase services** (all confirmed in use, not just declared as
dependencies):
- **Cloud Firestore** — primary cloud database for patients, checkups,
  referrals, doctor notes, disease/guidance content, and account records.
- **Realtime Database** — secondary mirror of `users/{uid}` role/profile
  data, used as a fallback role source.
- **Authentication** — email/password and Google Sign-In.
- **App Check** — enforced on both the Flutter web client and the Python
  backend's protected endpoint.
- **Cloud Storage** — referral file attachments only (`storage.rules`).
- **Cloud Functions** (Node.js) — account/role management, invitations,
  password reset, doctor registration, referral-assignment automation.

**Local/offline:** SQLite via `sqflite` (and `sqflite_common_ffi_web` for
web), used by each module's `DatabaseHelper` class for offline-first record
storage with explicit sync-to/from-Firestore methods.

**Backends:**
1. **Firebase Cloud Functions** (`functions/`) — privileged account/role
   operations.
2. **Python FastAPI** (`backend/`) — `fastapi`, `pydantic`, `scikit-learn`,
   `pandas`, `numpy`, `joblib`, `firebase-admin`. Serves the AI
   symptom-guidance endpoint (Section 5).

**Reporting:** Dart `pdf` package. Single-record PDFs via
`record_pdf_builder.dart`; bulk/period reports via
`bhw_report_generation.dart` and `dashboard_report_launcher.dart`.

**Icons:** Flutter Material `Icons` throughout — no second icon package was
introduced. Emoji-as-UI-icon usage identified in the AI recovery-plan
section headers and several SnackBar messages has been replaced with
`Icon` + `Text`.

**Charts:** `fl_chart` (web dashboards), `community_charts_flutter` (mobile
dashboard) — this inconsistency between platforms was **not** changed in
this pass (out of scope; migrating chart libraries this close to the
deadline was judged too risky for the marginal benefit).

**Design system:** New in this pass — `lib/web/shared/theme/app_theme.dart`
defines `AppColors`, `AppSpacing`, and `AppTheme.light()`, consolidating the
canonical brand color (`0xFF00A8B5`, confirmed as the value already used in
40+ files) as the single source of truth. `lib/main.dart` and the web
landing page now read from this file instead of redeclaring local color
constants. The other ~150 screens were **not** migrated — this was an
explicit scope decision (see Section 12).

---

## 3. Dataset — Verified vs. Unverified

The panel specifically asked for the dataset to be identified and its
reliability documented. Two entirely separate AI systems exist in this
codebase, and only one of them has a real dataset behind it.

### 3a. System A — Python RandomForest (`backend/`)

**VERIFIED INTERNAL DATASET INFORMATION** (confirmed directly from the
repository):

| Property | Value |
|---|---|
| File | `backend/dataset/raw/Diseases_and_Symptoms_dataset.csv` |
| Row count | 96,089 (96,088 records + header) |
| Columns | 233 binary symptom columns + 1 disease label column |
| Disease classes | 100 |
| Processed/cleaned file used for training | `backend/dataset/processed/merged_dataset.csv` (93,994 rows) |
| Train/test split | 80/20 — 75,194 training records, 18,799 test records |
| Model | `RandomForestClassifier` (scikit-learn), `n_estimators=300`, `max_depth=24` |
| Accuracy | 84.96% (from `backend/models/training_metrics.json`) |
| Precision (weighted) | 88.39% |
| Recall (weighted) | 84.96% |
| F1 (weighted) | 85.60% |
| Per-class variance | Documented in `backend/reports/dataset_comparison.json` — recall varies by disease class, as low as ~0.32 for some classes in a comparison experiment. Not uniformly reliable across all 100 diseases. |
| ICD-10 coding | Intentionally left empty for all 100 seeded disease records — the repository's own validation report (`disease_seed_validation.json`) flags every record with "ICD-10 codes unavailable; clinical mapping required" rather than inventing codes. |

**EXTERNAL SOURCE PROVENANCE — REQUIRES VERIFICATION.** The repository's own
code and documentation (`backend/README.md`, `backend/scripts/compare_datasets.py`)
describe this dataset as originating from **Kaggle**, but no exact dataset
title, author, listing URL, license, or DOI exists anywhere in this
repository. The pipeline code itself states that the original standalone
Kaggle file was *"unavailable"* and had to be reconstructed from a legacy
merged artifact — and that reconstructed segment scored far worse (39.8%
accuracy) than the version actually in production (86.9% in the internal
comparison experiment), which is itself evidence that the "Kaggle" claim
should be independently re-verified before it is cited as a definitive
source in any paper. **Do not cite a specific Kaggle listing unless someone
with access to the original download can confirm it.** State the source as
"internally compiled tabular disease/symptom data, structurally consistent
with datasets commonly distributed as 'Disease and Symptoms' collections;
exact original listing not confirmed."

**How this dataset is actually used:** training only. It is not used for
retrieval-augmented generation, and there is no vector database or
embeddings anywhere in the repository.

**Is the trained model live?** No. `POST /predict` exists in
`backend/app/api.py` but has no route decorator — it returns HTTP 404 by
design (confirmed by an explicit unit test,
`test_legacy_prediction_endpoint_is_not_registered`). This was an
intentional prior decision and **was deliberately left disabled in this
revision pass** — the panel's requirements do not call for disease
prediction to be activated, and enabling it this close to the deadline
would expand medical-risk scope without a corresponding requirement.

### 3b. System B — Dart rule-based classifier (live in the app)

`lib/app/core/services/health_ai_classifier.dart` is what actually runs when
a user saves a check-up record today. **It is not trained on, and does not
use, the dataset described above.** It is a hand-written keyword-matching
and vital-sign-threshold scoring engine with no training data and no loaded
model file (the optional TFLite path is present in code but disabled — the
`tflite_flutter` package is commented out in `pubspec.yaml`). Its output
schema, as of this revision, is exactly:

```json
{
  "home_care": ["..."],
  "precautions": ["..."],
  "estimated_recovery": "...",
  "general_advice": ["..."]
}
```

Prior to this revision, the same internal data structures also carried a
`medications` field (see Section 5). That field has been removed at the
source level — see below.

**Do not describe Systems A and B as one AI system.** They are unrelated:
different languages, different techniques, different data sources, and
different live/disabled status.

---

## 4. AI Medication Removal (Panel/Client Requirement)

**Requirement:** doctors, not AI, remain responsible for medication.

**What was found:** `health_ai_classifier.dart`'s `treatmentDatabase` and
`categoryFallbackTreatment` maps contained a `medications` field per
condition (e.g., `fever` → `['Paracetamol/Acetaminophen', 'Ibuprofen']`;
`diabetes` → `['Metformin', 'Insulin (as prescribed)', ...]`; `chest pain`
→ included `'Chew aspirin if not allergic'` as a self-treatment
precaution). Critically, `_generateRecoveryPlan()` — the function that
actually builds the output shown in the UI — **never read this field**, so
it was already invisible to end users before this revision. That did not
make it acceptable to leave in the source: a data field the system can
technically produce is still a real capability, regardless of whether any
current UI happens to render it.

**What was done:**
- Removed the `medications` key and all associated drug names, from every
  entry in `treatmentDatabase` (11 conditions) and `categoryFallbackTreatment`
  (6 categories) in `health_ai_classifier.dart`.
- Removed the aspirin self-treatment suggestion from the chest-pain
  precautions list.
- Reworded two generic compliance reminders that referenced "antibiotics"/
  "medications" by name to non-prescriptive phrasing (e.g., "Take all
  medications exactly as prescribed by your doctor" instead of "Complete
  full course of antibiotics").
- Removed the now-vestigial `'medications': []` key from the JSON-decode
  fallback default schemas in `checkup_database_helper.dart` (both
  occurrences) and `prenatal_database_helper.dart`, keeping the fallback
  shape consistent with what the classifier can actually produce.
- Confirmed via repository-wide search that no other AI-generated
  medication-recommendation logic exists. Two remaining hits for
  "medication" + "dosage" in `patient.dart` (both web and app) are patient
  *intake form* field hints ("Medications currently taking with dosage") —
  legitimate clinical history fields filled in by a health worker, not AI
  output, and were correctly left untouched.
- Confirmed the Python backend (`backend/app/schemas.py`) has never had a
  medication field in its API contract — `DiseaseInformation` and
  `SymptomGuidanceResponse` only expose `selfCareGuidance`/`homeCare`,
  `precautions`, `whenToSeeCare`, `emergencyWarningSigns`. No changes were
  needed there.
- Corrected three root-level documentation files
  (`AI_IMPLEMENTATION_SUMMARY.md`, `AI_RECOVERY_RECOMMENDATIONS.md`,
  `RECOVERY_RECOMMENDATIONS_SUMMARY.md`, `AI_DEFENSE_EXPLANATION.md`) that
  previously described medication suggestions as a current feature — each
  now carries a correction notice pointing here, rather than being silently
  rewritten (they remain a historical record of the development process).

**Result:** the AI does not generate medication names, dosages, schedules,
or antibiotic suggestions anywhere in the codebase — verified true at the
source level, not just in the currently-rendered UI.

---

## 5. AI Home-Care Guidance (Retained)

Both AI systems retain their non-prescriptive supportive content:

- **Dart classifier:** home care instructions, precautions, estimated
  recovery time, and general advice — rendered under the heading
  **"AI-Assisted Home-Care Recommendation"** (previously "Recovery
  Recommendations"/"📋 Recovery Recommendations") in four separate
  recovery-plan display widgets across `lib/web/roles/bhw/checkups/checkup.dart`
  and `lib/app/features/checkups/checkup.dart`. Every one of these now
  displays the disclaimer: *"AI-generated information provides supportive
  home-care guidance only. Medication and clinical decisions remain under
  the attending physician,"* next to a Material `Icons.info_outline` icon
  (no emoji).
- **Python backend `/guidance` endpoint:** home care, precautions, when to
  seek care, emergency warning signs, and references — protected by
  Firebase ID-token authentication, App Check, and rate limiting (30
  requests/60s per user), all fail-closed by default. This endpoint never
  calls the RandomForest and never returns a disease prediction.

---

## 6. Patient History & Doctor Notes (Priority Functional Fix)

**Previous state:** `doctorNotes` existed only as a single overwritable
string field on a *referral* document. A doctor assigned to a later
referral for the same patient could not see notes an earlier doctor wrote,
because doctor-facing queries filter to `assignedDoctorUid == currentUser`.
Referrals also were not shown in the patient's health-history timeline at
all.

**What was built:** a real, append-only doctor-notes feature, tied to a
specific check-up rather than a referral:

- **Model** (`lib/web/shared/models/doctor_note.dart`): `DoctorNote` with
  `id`, `patientId`, `patientName`, `checkupId`, `barangayCode`,
  `authorUid`, `authorName`, `authorRole`, `note`, `createdAt` (Firestore
  server timestamp).
- **Service** (`lib/web/shared/services/doctor_notes_service.dart`):
  `watchNotesForCheckup()` (live stream, oldest-first), `fetchNotesForPatient()`
  (one-off fetch across all of a patient's check-ups, for the history
  timeline), and `addNote()` (create-only — no update/delete method
  exists in the service, matching the Firestore rule below).
- **Firestore collection `doctor_notes`** with dedicated rules
  (`firestore.rules`): any CHO or DOCTOR account may read every note
  (continuity of care requires a later doctor to see an earlier doctor's
  notes regardless of which referral or barangay originated them); BHW
  accounts may read notes for patients in their own barangay (the note's
  `barangayCode` is taken from the **patient** record, not the author's own
  scope, so a CHO- or DOCTOR-authored note about a patient in Barangay X
  remains visible to BHWs serving Barangay X). **Notes cannot be updated or
  deleted once created** — `allow update, delete: if false`.
- **Reusable widget** (`lib/web/shared/widgets/doctor_notes_section.dart`):
  shows the note history for a selected check-up (author name, role badge,
  timestamp, note text) and, for CHO/DOCTOR accounts only, a text field to
  add a new note. BHW and other roles see a read-only notice instead of the
  input.
- **Wired into two live surfaces:**
  1. `CanonicalPatientDetailsModal` (opened from the BHW patient list) —
     the patient-centered profile view.
  2. `PatientHistoryDialogs.showPatientTimelineDialog` (opened from the
     Referrals page's "Continuity of Care" flow) — **this is the page the
     `DOCTOR` role actually lands on after login**, making this the more
     important of the two integration points for real doctor workflows.
- **`PatientCenteredHistoryService` was extended, not replaced**, per the
  explicit instruction to reuse the existing service:
  - `PatientModuleHistorySnapshot` gained `referralHistory` and
    `doctorNotes` fields, both folded into the existing `timeline` getter
    so they appear chronologically alongside checkups/prenatal/immunization
    /morbidity/mortality records.
  - `loadPatientHistory()` now also fetches referral history, using a
    query filter that mirrors the `canReadReferral` Firestore rule exactly
    (CHO sees every referral for the patient; a DOCTOR sees referrals
    assigned to them; a BHW sees referrals they created) — chosen
    specifically so the query never asks Firestore for documents the
    current user isn't authorized to read.

**Known gap:** the CHO-side referral views
(`cho_referral_management.dart`, `referral.dart`) and the mobile app's
referral flow do not yet call into this same history/notes surface — only
the BHW-side web referral page and the BHW patient list do. This is
documented as a follow-up, not silently left unfixed (see Section 11).

---

## 7. Referrals & Doctor Availability

Referrals were **not rebuilt** — the existing state machine and features
(referring doctor, assigned doctor, reason, priority, statuses,
attachments, timestamps, PDF export) were preserved.

**Duplicate `CHOPreferralPage` investigation:** two different classes with
the identical name existed — one in `cho_referral_management.dart` (reached
from the sidebar "Referrals" destination) and one in `referral.dart`
(reached from CHO dashboard quick actions). Investigation found this is
**not just a naming collision but a real, deeper divergence**: the two
pages use *entirely different, incompatible status vocabularies* against
what is presumably the same `referrals` Firestore collection
(`cho_referral_management.dart`: `pending_review` / `hospital_assigned` /
`doctor_assigned` / `waiting_consultation` / `consulted` / `completed`;
`referral.dart`: `submitted` / `under_review` / `assigned` /
`in_treatment` / `completed`). Cross-referencing `firestore.rules`'
`canUpdateReferral` function confirmed it checks for `pending_review` and
`returned_for_correction` — i.e., `cho_referral_management.dart`'s
vocabulary is the one the deployed security rules were designed around.

`referral.dart`, however, has real functionality
`cho_referral_management.dart` lacks entirely: doctor-registry management
(register/edit/archive/restore), referral filters, summary cards, and PDF
printing.

**Decision:** given the risk of breaking either the state machine or the
doctor-registry UI, a full merge was judged too risky to attempt safely
this close to the deadline. Instead:
- The naming collision was resolved by renaming `referral.dart`'s class to
  `CHOReferralWorkspacePage` (mechanical rename, zero logic changes) so the
  two are no longer confusingly identical.
- Both files now carry a prominent doc comment cross-referencing each
  other and explaining the vocabulary divergence, its cause, and the
  recommended remediation (treat `cho_referral_management.dart` as
  authoritative, port `referral.dart`'s extra features into it, then retire
  `referral.dart`).
- This is reported as **PARTIAL**, not DONE — see Section 11.

**Doctor availability:** the existing real scheduling logic
(`_doctorWorkingDays`, `_doctorHoursForDate`, `_assessDoctorAvailability` in
`cho_dashboard.dart`) was preserved and **not** replaced with a hard-coded
"Available Daily" field. A new presentation layer was added
(`_doctorScheduleSummary()`) that reads a doctor's actual configured
working days/hours and produces one of: "Available Daily" (only shown when
every day is genuinely configured, or no day restriction exists at all —
which is how the underlying availability check itself already treats an
unconfigured schedule), "Available Weekdays (Mon–Fri)", "Available: Mon,
Wed, Fri" (or whatever specific days are configured), or "Working days not
published" / "Marked unavailable in the doctor directory." This is
rendered on every doctor-availability search result card in the CHO
dashboard, alongside the existing point-in-time slot check.

---

## 8. Dashboard Data Integrity

**Found:** the BHW web dashboard (`lib/web/roles/bhw/dashboard/homepage.dart`)
displayed three "Performance Indicators" presented as real operational
metrics — Appointment Completion Rate, Patient Satisfaction Score, Average
Response Time — that were actually computed as
`85.0 + (checkups.length % 15)`, `4.2 + (checkups.length % 8) * 0.1`, and
`15 - (checkups.length % 10)` respectively: formulas with no relationship
to any real appointment, satisfaction, or response-time data, since none of
that data is tracked anywhere in the schema.

**Fixed:** replaced with three metrics genuinely derivable from stored
Firestore data, computed in the same `_loadKPIData()` function from data
already being fetched:
- **Check-ups This Month** — `_checkupsThisMonth` (already a real,
  previously-computed field) shown against total patients.
- **Documentation Completion** — the share of check-up records that have
  clinical notes recorded (mirrors the "pending review" business rule
  already used elsewhere in the same file for checkups missing notes).
- **Prenatal Coverage** — the share of registered patients with a prenatal
  record on file (same real-data shape as the pre-existing, already-genuine
  Immunization Coverage metric, which was left unchanged).

**Also fixed in the same file:** three `'icon': '??'` literal placeholder
strings on "health insights" cards (a genuine bug, not emoji) were replaced
with real `IconData` values (`Icons.trending_up`, `Icons.vaccines_outlined`,
`Icons.warning_amber_rounded`).

**Also removed:** ~430 lines of dead, unreachable code —
`_createCHOAccount()` and `_createBHOAccount()` — confirmed via
repository-wide search to have zero call sites anywhere in the app. These
functions created privileged accounts directly from the BHW dashboard
module, generated a predictable timestamp-based temporary password
(`'Temp${DateTime.now().millisecondsSinceEpoch}@Ab1'`), and stored that
password in plaintext in the Firestore user document — a real security
hazard even though unreachable. Their only helper functions
(`_buildCredentialRow`, `_copyToClipboard`) were dead code exclusively used
by these two functions and were removed with them.

**Not changed:** `_upcomingAppointments` "mock data (last 5 patients)" in
the same file, and the CHO dashboard's real-time metrics, which were
already confirmed genuine in the prior audit. See Section 11 for why the
mock-appointments generator was left as a known, documented issue rather
than fixed in this pass.

---

## 9. Filters

Existing working filters (referral status/barangay/search, CHO dashboard
barangay explorer, doctor-availability search, bulk-report period
selection) were preserved and not duplicated. No new filters were added in
this pass — the existing filter set was judged adequate against the
explicit panel requirement, and effort was directed to the higher-priority
doctor-notes and data-integrity fixes instead.

---

## 10. PDF / Report Generation

The confirmed small-font issue (7.2–8pt body text in bulk/tabular reports)
was fixed without causing column overflow:

- `bhw_report_generation.dart`'s `_buildRecordsTable` (used by every
  module's bulk export): header font 7.4pt → 10.5pt bold, body font
  7.2pt → 9.5pt, with proportionally increased cell padding. Verified
  against the `pdf` package's own text-layout source that cells wrap
  (never truncate) and long words force-split rather than overflow, so no
  column-width changes were required.
- `dashboard_report_launcher.dart`'s indicator tables (Prenatal, Immunization,
  Check-up, Patient, NCD, Morbidity, Mortality, Communicable): header
  8pt → 11pt bold, body 7.8pt → 9.5pt. The narrow "Sex" column's flex ratio
  was increased (0.55–0.6 → 0.7) to avoid ugly mid-word breaks at the
  larger font size. A previously-missing "Generated: `<date>`" timestamp
  and a "Period: … — …" filter-summary line were added to this report's
  header/footer, matching the pattern already used elsewhere.
- `record_pdf_builder.dart` (single-record PDFs) was already well-built —
  reasonable fonts, real headers/footers with page numbers, `pw.MultiPage`
  — and was left unchanged.

Report generation, in plain terms: every PDF is generated **client-side**
in the Flutter app (not on a server) using the `pdf` Dart package, pulling
data from whatever Firestore-synced records are already loaded, applying
the user's selected filters (period, month/year, or module scope) before
rendering, and producing a downloadable/printable file directly in the
browser or device.

---

## 11. Known Limitations / Deliberately Deferred Work

Reported honestly rather than glossed over:

1. **CHO referral duplication is documented, not merged.** See Section 7.
   A full state-machine reconciliation is a multi-file, multi-day task that
   was judged too risky to rush before the deadline.
2. **Doctor notes are not yet wired into the CHO-side referral views or the
   mobile app** — only the BHW-side web referral page and BHW patient list
   currently surface them. The underlying service/model support any
   caller; only the UI wiring is missing in those two places.
3. **BHW dashboard's "upcoming appointments" widget still synthesizes
   sample appointment dates from the last 5 patient records** — a
   pre-existing mock-data pattern distinct from the KPI-formula issue that
   *was* fixed. A real fix requires an actual appointment/scheduling data
   model that doesn't exist yet in this system; that is new-feature work,
   not a data-integrity bug fix, and was out of scope for this pass.
4. **Chart library inconsistency** (`fl_chart` on web vs.
   `community_charts_flutter` on mobile) was identified but not unified —
   explicitly out of scope per the instruction not to migrate chart
   libraries this close to the deadline.
5. **Design system migration is partial.** `AppColors`/`AppTheme` now
   exist as the single source of truth and are used by `main.dart` and the
   web landing page; the other ~150 screens still declare local color
   constants. This was an explicit, bounded scope decision, not an
   oversight — rewriting every screen risked destabilizing working UI this
   close to the deadline.
6. **`_createInvitation()`** in the BHW dashboard (a *different*, actively
   used function from the two removed dead functions) still generates a
   timestamp-based temporary password
   (`'TempPass${DateTime.now().millisecondsSinceEpoch}@Ab1'`) when directly
   creating a Firebase Auth user from client code. Unlike the two removed
   functions, this one is live and wired to a real UI flow, so it was left
   alone to avoid destabilizing a working invitation flow — but it shares
   the same predictable-password weakness and should be revisited in a
   dedicated follow-up (ideally by moving user creation server-side into a
   Cloud Function, matching the pattern already used by
   `process_invitations.js`).
