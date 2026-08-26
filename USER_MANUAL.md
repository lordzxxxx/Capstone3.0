# Smart Health Integration — User Manual

This manual covers the web application (`lib/web/*`), which is what
CHO/BHW/Doctor staff use in a browser. Screens and menu wording match the
running application as of the August 2026 revision.

---

## Landing Page

The landing page is the public entry point before login. It presents the
system's purpose and a call-to-action leading to the CHO and BHW login
pages. No patient data is accessible from this page.

## Login

1. Choose "Login as CHO" or the equivalent BHW/health-worker entry point
   from the landing page.
2. Enter your registered email and password.
3. New BHW accounts require CHO approval before first login — if you see
   an "awaiting approval" message, contact your City Health Office.
4. Forgot your password? Use the "Forgot Password" link. A reset
   email/code is sent to your registered address.

Doctor accounts are provisioned by a CHO administrator and log in the same
way; a doctor account lands directly on the **Referrals** page after login
(doctors do not have a separate dashboard — referral review is their
primary workspace).

## CHO Dashboard

Available to CHO and administrator accounts. Shows:
- Real-time patient risk-level counts and follow-up counts (live Firestore
  data, updates automatically).
- A monthly check-up trend chart.
- A barangay demographic explorer — select a barangay from the dropdown to
  see its specific statistics.
- A doctor-availability search tool — pick a date, time, duration, and
  optionally a specialty, to see which doctors are genuinely free (see
  **Doctor Availability** below).
- Quick actions, including a shortcut into the referral workspace.

## BHW Dashboard

Available to BHW accounts. Shows:
- Patient and check-up counts for your barangay.
- A "Performance Indicators" panel: Check-ups This Month, Documentation
  Completion (share of check-ups with clinical notes on file), Prenatal
  Coverage, and Immunization Coverage — all computed from your barangay's
  actual stored records.
- Health insight cards that flag notable patterns (e.g., rising prenatal
  caseload, strong immunization coverage, low check-up activity).

## Patient Records

From the Patients section you can create, edit, search, and list patients.
The system checks for likely duplicate patients (matching name plus date
of birth or phone number) when you add a new one — review any match before
proceeding.

## Patient Profile

Opening a patient shows their baseline information (medical history,
allergies, blood type) plus two additional panels described below.

## Health Timeline

Below the patient's baseline information, the **Health Timeline** panel
lists every linked record for that patient — check-ups, prenatal visits,
immunizations, morbidity/mortality reports, **referrals**, and **doctor
notes** — merged into one chronological list, most recent first. Chip
counters at the top show how many records exist in each category. This is
the same underlying history that appears in the Referrals page's
"Continuity of Care" view when reviewing a referral.

## Check-ups

Recording a check-up captures symptoms, vital signs, and clinical
findings. On save, the AI classifier (see below) automatically analyzes
the entry and attaches a category, severity, and home-care recommendation
to the record — this happens locally/offline and does not require the
Python backend to be reachable.

## Doctor Notes

A **Doctor Notes** panel appears in the patient's Health Timeline and in
the Referrals page's patient-history view. It shows every note left for
this patient's check-ups, each with the author's name, role, and
timestamp — notes are never edited or overwritten, so you always see the
full history left by every doctor who has treated this patient, not just
your own.

**To add a note** (CHO and Doctor accounts only): select the relevant
check-up from the dropdown (if the patient has more than one), type your
note, and select "Add Note." BHW and other accounts can read all notes but
will see a message explaining that only doctors and CHO staff can add
them.

## AI Home-Care Guidance

After a check-up is classified, an **"AI-Assisted Home-Care
Recommendation"** panel appears with: estimated recovery time, home-care
instructions, precautions, and general advice. A disclaimer is always
shown: *"AI-generated information provides supportive home-care guidance
only. Medication and clinical decisions remain under the attending
physician."* The AI does not suggest medications, dosages, or
prescriptions — that responsibility remains entirely with the attending
doctor.

## Referrals

Create a referral from a patient's record when they need to see a doctor.
Fill in the reason, priority, and preferred doctor (or let the system
suggest one). A CHO reviews and assigns the referral to a hospital and
doctor; the assigned doctor can then review the patient's full history
(including prior doctor notes) before the consultation, record the
outcome, and — for BHWs — a returned/corrected referral can be revised and
resubmitted.

## Doctor Availability

When assigning a referral or searching the CHO dashboard's availability
tool, each doctor's card shows both a point-in-time check ("Available" /
"Unavailable" for the specific date and time you searched, with the
reason) and a schedule summary ("Available Daily," "Available Weekdays
(Mon–Fri)," or the specific configured days) based on that doctor's actual
published schedule — never a hard-coded assumption.

## Filters

- **Referrals list:** filter by status, barangay, and free-text search.
- **CHO dashboard:** filter the demographic explorer by barangay; filter
  doctor-availability search by date, time, duration, and specialty.
- **Reports:** filter by period (monthly/quarterly/yearly) and the
  specific month/year.

## Reports & PDF Generation

Reports are generated **in your browser** — no data leaves the app to a
separate report server. Select the module and period you want (or use the
CHO "Overall Health" export for a citywide summary), and the system pulls
your already-synced records, applies your selected filters, and produces a
downloadable/printable PDF with a title, generation date, a summary of the
filters applied, page numbers, and — for bulk/tabular exports — properly
sized 9.5–11pt text for readability. If no records match your filters, the
report clearly states that instead of producing an empty or misleading
document.

## Logout

Use the account menu (usually top-right) to sign out. This ends your
session; you will need to log in again to access any patient data.

## Troubleshooting

- **"Awaiting approval" after signup:** a CHO administrator must approve
  new BHW accounts before first login.
- **Referral or note fails to save with a permission error:** confirm you
  are using the correct role's login (e.g., only CHO/Doctor accounts can
  add doctor notes; only CHO accounts can approve referrals).
- **PDF shows "No records matched the selected filters":** widen your date
  range or confirm the module/barangay filter is correct — this message
  means the query succeeded but found nothing, not that generation failed.
- **AI home-care panel doesn't appear on a check-up:** classification runs
  automatically on save; if it's missing, re-open the record — the
  classifier processes locally and does not depend on an internet
  connection.
- **Doctor availability shows "Unavailable" unexpectedly:** check the
  reason shown on the card — it may be outside published hours, a
  conflicting referral at that time slot, or the doctor's directory status
  being set to busy/unavailable. This reflects the doctor's actual
  configured schedule, not a guess.
