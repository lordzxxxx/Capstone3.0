# BHW Referral Entry Point + Summary Export — Design

Date: 2026-08-21
Status: Approved, ready for implementation planning

## Background

The capstone adviser asked for two BHW-facing usability improvements, plus a broader
usability review of the BHW module:

1. A way for a BHW to refer a patient to CHO directly from the Check-Up Records page
   (`/bhw/checkups?view=records`) when findings, symptoms, or vitals warrant further
   evaluation — without requiring the BHW to state a definitive diagnosis.
2. A properly formatted, exportable barangay health summary from the Summary page
   (`/bhw/summary`) — previewable, copyable, downloadable as DOCX, and printable —
   automatically carrying barangay, reporting period, and BHW information.
3. A written list of further practical, low-risk usability improvements for the BHW
   module (delivered separately as recommendations, not implemented in this pass).

Investigation found the BHW referral workflow already exists in full at
`/bhw/referrals` (`lib/web/roles/bhw/referrals/bhw_referral_management.dart`,
`BhwReferralPage`): patient-first gate, auto-loaded read-only clinical context,
Reason / Priority / Observations / Supporting Notes / Destination Facility (optional) /
Attachments, submission to CHO, status tracking, and home-visit follow-ups. It
deliberately has no diagnosis field. The gap is purely that nothing links to it from
the Check-Up Records page, and it isn't pre-filled with the check-up that triggered
the referral.

The Summary page (`lib/web/roles/bhw/analytics/health_metrics.dart`, `HealthMetricsPage`)
already generates, previews, copies, and saves a history of summaries via
`lib/web/roles/bhw/analytics/ai_summary.dart`. That generator is shared with the mobile
app (`lib/app/features/analytics/health_metrics.dart` calls the same functions), so its
output format must not change. What's missing on the web page is DOCX download, print,
and a structured header (barangay / period / BHW name) wrapped around the existing body
for export purposes only.

## Goals / Non-goals

**Goals**
- BHW can jump from a specific check-up record straight into a referral for that
  patient, without re-searching for the patient or retyping vitals/symptoms already on
  file.
- BHW gets a lightweight, non-blocking visual cue when a check-up's vitals cross known
  abnormal thresholds, consistent with "refer based on findings, not diagnosis."
- BHW can download a properly formatted, professional `.docx` summary and print/export
  a PDF version, both carrying barangay/period/BHW header info.
- No changes to diagnosis-adjacent scope: BHWs still never enter a diagnosis anywhere
  in this pass.

**Non-goals**
- Not rebuilding the referral form or its CHO-side review/assignment flow — both already
  work and are out of scope.
- Not changing `ai_summary.dart`'s generated text (shared with mobile).
- Not implementing the broader BHW module recommendations in this pass — those are
  delivered as a separate written list.
- Not adding new pubspec dependencies (DOCX is hand-written using the already-available
  `archive` package; PDF reuses the already-present `pdf` package).

## Design

### 1. Referral entry point on Check-Up Records

**Button placement**: `_CheckUpCard` in `lib/web/roles/bhw/checkups/checkup.dart`
(around line 4887-4915) currently renders 3 action icons — History, Edit, PDF — in a
112px-wide `SizedBox`. Add a 4th icon button, `Icons.local_hospital_outlined` /
tooltip "Refer to CHO", and widen the column (and matching header cell at
`_buildCheckUpCardHeader`, line ~1906) to fit 4 icons (112 → ~150px).

**Navigation**: On tap, build a patient-seed map from the check-up record:

```dart
{
  'patientId': record['patientId'] ?? record['linkedPatientId'] ?? record['id'],
  'patientName': record['patient'],
  'age': record['age'],
  'address': record['address'],
  'barangay': record['barangay'],
}
```

Navigate to `WebRoutes.bhwReferrals` passing this as `initialPatient`, plus a new
`initialObservations` string built from the record's `vitalsigns` and `symptoms`
fields (e.g. `"Vitals: BP 120/80, Temp 37.5°C, HR 78 bpm, O2 98%. Symptoms: cough, mild fever."`).

**`BhwReferralPage` changes** (`bhw_referral_management.dart`):
- Add an optional `initialObservations` constructor parameter.
- In `initState`, when `widget.initialObservations` is non-empty, seed
  `_observationsController.text` with it after `_openPatient` completes (still fully
  editable — this is a starting point, not a lock).
- In `_openPatient`, if the resolved patient has no usable `patientId` (unlinked/legacy
  check-up record), don't silently fail: fall back to the existing `_patientGate()` /
  "Search and Select Patient" flow and show a snackbar — *"This check-up isn't linked to
  a registered patient. Search for the patient to continue."*
- Reason for referral is deliberately left blank — the BHW states why they're
  referring; that's their judgment call, not something auto-filled from vitals.

**Routing**: `main.dart`'s `bhwReferrals` `GetPage` currently builds a `const
BhwReferralPage()` with no arguments. This app's existing convention for passing
per-navigation data through `Get.toNamed` (used e.g. at `main.dart:751` for
`verificationCode`) is to read `Get.arguments` inside the route's `page:` callback and
pass it into the widget's constructor — not a const widget. Follow that pattern: change
the `bhwReferrals` `GetPage` builder to read `Get.arguments as Map?`, extract
`initialPatient` (`Map<String, dynamic>?`) and `initialObservations` (`String?`), and
pass both into `BhwReferralPage(...)`. The check-up row's tap handler calls
`Get.toNamed(WebRoutes.bhwReferrals, arguments: {'initialPatient': seed, 'initialObservations': observations})`.

### 2. Abnormal-vitals suggestion badge

New file `lib/web/shared/utils/vital_risk_flags.dart`:

```dart
List<String> detectAbnormalVitalFlags(String vitalSignsText);
```

Parses labeled tokens from the check-up's `vitalsigns` string (format confirmed at
`checkup.dart:6902-6923`: `"BP: 120/80, Temp: 37.5°C, HR: 78 bpm, RR: 18 brpm, O2: 98%, ..."`)
against fixed thresholds mirrored from the alert logic already in `ai_summary.dart`
(fever ≥38.0°C, SpO2 <92%, systolic BP ≥140, heart rate <50 or >100 bpm). Returns a list
of short human-readable flag strings (e.g. `"Fever range"`, `"Low oxygen saturation"`) or
an empty list.

In `_CheckUpCard`, if `detectAbnormalVitalFlags(vitalsigns)` is non-empty, render a small
amber pill badge near the patient name: "Suggested Referral" with the flags as a tooltip.
Purely informational — never blocks, auto-fills, or auto-submits anything. No changes to
`ai_summary.dart` itself; thresholds are duplicated intentionally to avoid coupling a
web-only UI concern to the shared mobile+web summary generator.

### 3. Summary page — DOCX, print, structured header

**Header composition** (web-only, in `HealthMetricsPage`): a small helper builds a
header block — barangay name (from `UserAccessScope.barangay`), reporting period
(`_currentPeriodLabel`, already computed), BHW name (from `FirebaseAuth` current user),
and generated-at timestamp — and combines it with the existing `_summary` body text
*only* at export time. The on-screen preview (`_SummaryViewer`) and the shared
`ai_summary.dart` generator are unchanged.

**DOCX download** — new `lib/web/shared/utils/summary_docx.dart`:
- `Future<List<int>> buildSummaryDocxBytes({required String title, required String headerBlock, required String body})`.
- Hand-writes a minimal valid OOXML `.docx`: `[Content_Types].xml`, `_rels/.rels`,
  `word/_rels/document.xml.rels` (if needed), `word/document.xml` with heading and
  bullet paragraphs, zipped via the `archive` package (already a transitive dependency
  via `pdf`; will be promoted to a direct `pubspec.yaml` entry since we depend on it
  directly now).
- Downloaded via the existing `report_print.dart` → `report_print_web.dart`
  `printReportFile(bytes, filename, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', target: null)`,
  which triggers a browser blob download when there's no print-preview target.

**Print / PDF export** — new `lib/web/shared/utils/summary_pdf.dart`, mirroring the
existing `referral_pdf.dart` pattern (same `pdf` package usage), producing a formatted
PDF with the same header block + body. Opened via the existing
`report_print.dart`/`report_print_web.dart` (new-tab, browser-handled print/save) — same
UX referrals already use.

**UI**: Two new buttons next to the existing Copy/Clear in `_buildSummaryActions()` —
"Download DOCX" and "Print / Export PDF" — both disabled until a summary exists, same
enablement rule as Copy/Clear.

## Error handling

- Check-up record with no linkable patient → referral page falls back to patient search
  gate with an explanatory snackbar (not a crash or silent no-op).
- DOCX/PDF generation failure → snackbar error, consistent with existing
  `_printReferralReport` error handling in `referrals.dart`.
- Vital-flag parsing on malformed/missing `vitalsigns` text → returns empty list (no
  flags shown), never throws.

## Testing

- `flutter analyze` clean after changes.
- Manual verification:
  - Refer button from a check-up record opens `/bhw/referrals` with patient and
    observations pre-filled; Reason is blank.
  - A check-up record with a known-abnormal vital (e.g. Temp: 39.0°C) shows the
    suggested-referral badge; a normal-vitals record does not.
  - Generate a summary, download DOCX, open it in Word/Google Docs/LibreOffice and
    confirm it renders correctly with header + body.
  - Generate a summary, use Print/Export PDF, confirm the PDF opens in a new tab with
    header + body and is printable.
  - Unlinked/legacy check-up record (no `patientId`) routes to the patient-search gate
    instead of erroring.
