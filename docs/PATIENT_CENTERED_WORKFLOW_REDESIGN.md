# Patient-Centered Workflow Redesign for the BHW Health Information System

Date: April 8, 2026
Status: Proposed redesign grounded in the current prototype structure

## Overview
The current prototype already has working health modules and a separate patient master record, but the transaction flow is still mostly module-first. To make the system practical for Barangay Health Workers, every visit should start by identifying the patient first, then loading that patient's history, then adding a new module-specific record as another entry in the same longitudinal record.

This redesign keeps your existing module coverage:
- Immunization
- Prenatal
- Check Up
- Communicable Disease
- Non-Communicable Disease
- Mortality
- Morbidity

The goal is not to remove modules. The goal is to make each module behave as a patient-linked history instead of a disconnected stand-alone form.

## Current Codebase Findings
The redesign below is based on the current implementation, not on a generic health app pattern.

- A patient master record already exists in `patient_records` through:
  - `lib/app/features/patients/patient_database_helper.dart`
  - `lib/web/roles/bhw/patients/patient_database_helper.dart`
- Immunization, Prenatal, and Morbidity already store `patientName` and `patientId` fields in their module tables:
  - `lib/app/immunization_database_helper.dart`
  - `lib/app/features/prenatal/prenatal_database_helper.dart`
  - `lib/app/morbidity_database_helper.dart`
  - Web equivalents under `lib/web/...`
- Check Up still stores the patient as free text in the `patient` field, which makes reliable patient reuse difficult:
  - `lib/app/features/checkups/checkup_database_helper.dart`
  - `lib/web/database_helper.dart`
- Communicable and Non-Communicable currently reuse the check-up data source and filter it by `diseaseType`, so they are not yet true patient-history modules with a strong patient foreign key.
- Mortality currently stores `name` but not a strong patient link:
  - `lib/app/mortality_database_helper.dart`
  - `lib/web/mortality_database_helper.dart`
- Dashboard navigation currently opens module pages directly, which encourages module-first encoding instead of patient-first retrieval.

## System Workflow Explanation

### Target Principle
One patient profile should be the entry point for all transactions.

### Target Operational Rule
Before a BHW adds any new health record, the system should first ask:

1. Does this patient already exist?
2. If yes, load the patient profile and module history.
3. If no, register the patient once, then continue to the selected module.

### New Overall Flow
1. Open dashboard.
2. Choose `Find Patient` or enter a module from a `Search Patient First` prompt.
3. Search the patient by name, birth date, phone number, barangay, or patient code.
4. If patient exists, open the patient profile workspace.
5. Show patient summary plus module history counts.
6. Select a module from inside the patient profile.
7. Show module history before showing the new entry form.
8. Click `Add New Record`.
9. Save the new record as a new child entry linked to the same patient.
10. Refresh the patient history and timeline immediately after saving.

## Step-by-Step Process Flow

### 1. Patient Registration
Use patient registration only when no existing patient is found.

Required behavior:
- Search must happen before saving a new patient.
- The system should warn about possible duplicates using:
  - Full name
  - Date of birth
  - Phone number
  - Barangay or address
- After save, assign one unique patient identifier.
- Recommended pattern:
  - Internal key: `patient_records.id`
  - Human-readable code: `patientCode` such as `BHW-2026-000123`

### 2. Patient Search
The search screen should be global and reusable by all modules.

Searchable fields:
- Patient code
- First name
- Surname
- Full name
- Date of birth
- Phone number
- Barangay

Search result card should show:
- Patient code
- Full name
- Age and sex
- Barangay
- Status
- Latest visit date
- Module badges such as Prenatal Active, Immunization Due, NCD Follow-up

### 3. Patient Profile Viewing
After selection, open one patient workspace, not a raw module form.

The patient profile should display:
- Demographics
- Contact details
- Risk flags
- Current status
- Last recorded visit
- Module summary cards
- Unified timeline of visits and reports

### 4. Module Selection
Modules should be opened from the patient profile or from a module button that first forces patient lookup.

Recommended module buttons:
- Check Up
- Prenatal
- Immunization
- Communicable
- Non-Communicable
- Morbidity
- Mortality

### 5. Viewing Patient History
History must appear before the new form.

Required behavior:
- Show the latest record first.
- Keep previous records read-only.
- Highlight active care plans, due follow-ups, and latest assessment.
- Allow the BHW to review the previous entry before adding the next one.

Recommended module history layout:
- Latest record summary card on top
- Chronological history list below
- `Add New Record` button beside or below the history header

### 6. Adding a New Record
When the BHW clicks `Add New Record`:
- Patient identity should already be locked in.
- Patient header should remain visible while encoding.
- The BHW should not retype core patient demographics.
- Only visit-specific or module-specific details should be encoded.

### 7. Saving and Updating History
When saved:
- Create a new transaction row, not a replacement of the old one.
- Link the new row to the same patient.
- Refresh the module history immediately.
- Update the patient timeline and latest-visit summary.
- Keep older records unchanged unless the BHW explicitly edits that exact old record.

## Patient-Centered Record Sequence

### When the Patient Is New
1. Search returns no reliable match.
2. System offers `Register New Patient`.
3. BHW completes one patient profile.
4. System creates:
   - Master patient record
   - Unique patient identifier
5. System returns the user to the patient workspace.
6. BHW selects the needed module.
7. System shows empty module history with a message such as `No previous immunization records`.
8. BHW adds the first module record.

### When the Patient Already Exists
1. Search returns a patient match.
2. BHW selects the patient.
3. System opens the patient profile.
4. BHW selects a module.
5. System shows previous records for that module first.
6. BHW reviews the latest and previous entries.
7. BHW clicks `Add New Record`.
8. System saves a new record linked to the same patient.
9. History updates immediately and keeps the old entries visible.

## Module Logic

### Immunization
Use one patient profile with multiple immunization events over time.

Behavior:
- One child record per administered vaccine or dose.
- Show immunization history in dose order and date order.
- Display:
  - Vaccine
  - Dose number
  - Administration date
  - Brand and batch
  - Adverse events
  - Next dose due date
- Before adding a new dose, show:
  - Last dose received
  - Series completion status
  - Next due schedule

### Prenatal
Prenatal should be episode-based, not just visit-based.

Recommended structure:
- One patient can have multiple pregnancy episodes over time.
- One pregnancy episode can have multiple prenatal visit records.

Behavior:
- Patient profile -> Prenatal -> Pregnancy Episodes
- Open current pregnancy episode first if active.
- Show previous prenatal visits for the active pregnancy before encoding a new visit.
- For completed pregnancies, keep the episode read-only except for corrections.

Important prenatal logic:
- Do not overwrite the first prenatal registration when the mother returns.
- Add a new prenatal visit under the same pregnancy episode.
- If a new pregnancy happens in the future, create a new episode for the same patient.

### Check Up
Check Up should behave as a general visit history.

Behavior:
- One record per consultation or assessment.
- Use patient profile as the anchor.
- Show latest vitals, latest complaint, and latest follow-up plan before creating a new entry.
- Save every new consultation as a separate visit.

### Communicable Disease
Communicable disease should be case-based.

Recommended structure:
- One patient can have multiple communicable disease cases over time.
- One case can have multiple monitoring or follow-up transactions.

Behavior:
- If the patient has an active case for the same disease, add a follow-up transaction instead of creating a disconnected duplicate patient record.
- Show:
  - Disease
  - Date started
  - Case status
  - Isolation or treatment plan
  - Follow-up history
- Keep past closed cases visible for reference.

### Non-Communicable Disease
Non-Communicable disease should be registry plus follow-up based.

Recommended structure:
- One patient can have multiple chronic-condition registries.
- Each condition can have multiple monitoring visits.

Behavior:
- Example:
  - Patient has Hypertension registry
  - BHW adds BP monitoring visits over time under the same patient and condition
- Show:
  - Condition
  - Date enrolled
  - Current status
  - Last visit
  - Medication and lifestyle notes
  - Follow-up history

### Morbidity
Morbidity should record illness occurrences without breaking patient continuity.

Behavior:
- Each morbidity entry must link to the patient.
- If the same illness is still active, allow follow-up updates.
- If the illness is new or unrelated, create a new morbidity episode under the same patient.
- Keep all episodes visible in the patient history.

### Mortality
Mortality is a final event linked to the patient record.

Behavior:
- If the deceased person already exists, search and select the patient first.
- Save mortality as a linked record under that same patient.
- Preserve all previous medical history.
- After a confirmed mortality entry:
  - Set patient status to `Deceased`
  - Prevent new active care transactions
  - Keep all old records available for reporting and audit

If the person does not yet exist in the system:
- Allow minimal patient registration first
- Then create the mortality record
- This prevents orphan death records with no patient profile

## Suggested Database Relationship

### Core Concept
Keep one patient profile, then keep separate module histories linked by patient.

### Recommended Master Table
`patient_records`
- `id`
- `patientCode`
- demographic fields
- address fields
- status
- registration metadata

### Recommended Shared Columns for All Module Tables
Every module record should contain:
- `id`
- `linkedPatientId`
- `patientCodeSnapshot`
- `patientNameSnapshot`
- `encounterDate`
- `createdAt`
- `updatedAt`
- `createdBy`
- `recordStatus`

Snapshot fields are important so old reports still show the name used at the time, even if the patient profile is edited later.

### Recommended Module Tables
- `checkup_records`
- `immunization_records`
- `prenatal_episodes`
- `prenatal_visit_records`
- `communicable_cases`
- `communicable_followups`
- `ncd_cases`
- `ncd_followups`
- `morbidity_records` or `morbidity_episodes`
- `mortality_records`

### Practical Migration Path from the Current Prototype
You do not need to rewrite everything at once.

Recommended transition path:
1. Keep existing tables.
2. Add `linkedPatientId` to every module table.
3. Standardize module records so `linkedPatientId = patient_records.id`.
4. Keep current patient name fields as snapshot fields.
5. Convert free-text only modules:
   - `checkup_records.patient` -> keep as `patientNameSnapshot`
   - add `linkedPatientId`
   - use `diseaseType` to continue separating General, Communicable, and Non-Communicable
6. Convert `mortality_records.name` into a snapshot name and add `linkedPatientId`.
7. Later, split episode-based modules such as Prenatal, Communicable, and NCD into parent-child tables if needed.

### Timeline and Multi-Visit Tracking
To track multiple visits over time, each module record should represent a new event, visit, or follow-up.

Recommended fields:
- `encounterDate`
- `followUpDate`
- `episodeId` or `caseId` when applicable
- `isLatest`
- `closedAt` for completed cases or episodes

Timeline can be:
- generated dynamically from module tables, or
- stored in an audit table such as `patient_timeline_events`

For the current prototype, dynamic generation is the easier first step.

## Recommended UI Behavior

### Main Navigation
Recommended top-level actions:
- Find Patient
- Register Patient
- Quick Follow-up
- Reports

### Best BHW Screen Flow
1. Dashboard
2. Patient Search
3. Patient Profile
4. Module Workspace
5. History First
6. Add New Record
7. Save
8. Return to Updated Patient History

### Patient Profile Layout
Recommended sections:
- Patient header
- Alerts and active programs
- Module cards with counts
- Unified timeline
- Quick actions

### Module Workspace Layout
Recommended sections:
- Patient header
- Latest module summary
- Previous history list
- `Add New Record` button
- New record form

### Buttons and Actions That Should Appear
- `Search Patient`
- `Register New Patient`
- `Open Patient Profile`
- `View Full History`
- `Add New Record`
- `Edit Patient Profile`
- `Back to Search`
- `Mark as Follow-up`
- `Print Patient Summary`

### Duplicate Prevention Behavior
Before saving a new patient:
- Show `Possible existing patient found`
- Show side-by-side candidate matches
- Offer:
  - `Use Existing Patient`
  - `Continue New Registration`

Before saving a module record:
- Do not allow saving without a linked patient.
- Auto-populate patient fields from the selected patient profile.
- Remove manual retyping of patient identity inside module forms.

### Latest vs Previous Records
Display rules:
- Latest record pinned at the top
- Previous records below in reverse chronological order
- Old records remain visible and unchanged
- New form should optionally preload selected values from the latest record for faster encoding

## Functional Recommendations
- Prevent duplicate patient creation through a search-before-save step.
- Use one internal patient identifier across all modules.
- Add a human-readable patient code for BHW reference and paper follow-up.
- Keep module records append-only unless the exact transaction is being corrected.
- Show module history before every new transaction.
- Provide a cross-module timeline in the patient profile.
- Mark deceased patients clearly and restrict new care transactions after mortality confirmation.

## Immediate Design Decision for This Codebase
For the current prototype, the best next implementation step is:

1. Make patient search the required first step for every module.
2. Standardize module records to link back to `patient_records.id`.
3. Show patient history before opening the module form.
4. Save each new visit as a new child record linked to the same patient.

That keeps your existing working modules, but changes the system behavior from module-centered encoding to patient-centered continuity of care.
