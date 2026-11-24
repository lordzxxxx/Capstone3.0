# AI-DSUHIS — Combined 2:00 Video Presentation Script

Use the corresponding screenshot index for the cut points. The timings total
exactly two minutes and are written for a screen recording with a calm,
confident delivery at approximately 135–145 words per minute.

## 0:00–0:10 — Opening and platform purpose

**Show:** BHW dashboard, then CHO dashboard.

> AI-DSUHIS connects barangay health work, city operations, and protected doctor
> coordination in one role-aware platform. Each user sees the tools appropriate
> to their responsibility, while shared clinical records stay synchronized.

## 0:10–0:38 — BHW workflow

**Show:** BHW dashboard → patient records → check-ups → analytics.

> The Barangay Health Worker can register residents, record check-ups, create
> summaries, and open prenatal or immunization services. Patient Records keeps
> each identity connected to its care history. Check-ups and Analytics turn
> barangay activity into follow-up insights, while surveillance, referrals,
> notifications, and profile tools support daily field work.

## 0:38–1:02 — AI training, input, process and output

**Show:** BHW check-up or Summary Generation view, then the AI review/output
panel.

> The AI starts with symptom text or structured check-up fields. Its trained
> disease model uses 75,194 training records, 228 binary symptom features, and
> 100 labeled classes. At runtime, input is normalized, authenticated, and
> checked against supported terms. A local TF-IDF, keyword, and metadata ranker
> retrieves source-backed guidance. The output is a reviewable explanation with
> precautions, referral or emergency prompts, confidence, and source context.
> OCR can prefill paper-form fields, but staff must verify them. This is support,
> not an automated diagnosis, prescription, or treatment decision.

## 1:02–1:32 — CHO operations

**Show:** CHO dashboard → patients → check-ups → reports.

> The City Health Office sees the wider operational picture: synchronization,
> population, referrals, clinical attention, and program performance. Its
> patient and check-up workspaces expose the same authorized records without
> double-counting mirrors. CHO staff can review every health program, export
> reports, and use demographics, analytics, insights, and geographic
> surveillance for city-level coordination.

## 1:32–1:54 — Governance and collaboration

**Show:** CHO Manage Access, then CHO referrals or BHW referrals.

> Governance is built in. CHO administrators manage approved accounts, roles,
> and permissions, while referrals connect barangay services, city review, and
> clinical follow-through. Data quality, audit logs, announcements, and BHW
> management support the operational controls.

## 1:54–1:58 — Doctor portal

**Show:** Doctor login or approved doctor management view.

> Doctors enter a protected portal for assigned referrals and clinical
> follow-through, with profile, archive, transfer, and doctor-note tools.

## 1:58–2:00 — Closing

**Show:** CHO dashboard with synchronization status visible.

> AI-DSUHIS connects registration, evidence-led guidance, oversight, and care.

### Recording note

Do not display passwords or private patient details. The supplied BHW and CHO
accounts were used for authenticated screenshots. A doctor credential was not
provided, so the Doctor Portal was described from its protected routes and
implemented modules without bypassing account security.
