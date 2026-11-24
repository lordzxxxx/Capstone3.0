# AI-DSUHIS Platform Recording Script

This script matches the recorded local build from November 24, 2026. Replace
names, timing, or narration as needed before publishing. Do not show passwords
or private clinical details in a public recording.

## BHW workflow — approximately 1 minute

**0:00–0:09 — Dashboard**

> Welcome to the AI-DSUHIS Barangay Health Worker portal. This dashboard gives
> Barangay 03 staff immediate access to patient registration, checkups,
> summaries, analytics, prenatal care, and immunization services.

**0:09–0:24 — Patient records**

> The patient workspace now loads the synchronized Barangay 03 registry. It
> contains 78 real resident records, with names and available profile details
> shared consistently across the authorized BHW and City Health Office views.

**0:24–0:39 — Checkups**

> The checkup workspace retains all 20 imported consultation records and their
> patient links. Legacy records without a service date remain visible, but are
> not assigned to a monthly or six-month chart until a valid date is recorded.

**0:39–0:55 — Analytics**

> Analytics uses the same synchronized clinical sources, excludes synthetic
> seed records, and avoids counting mirrored Firestore documents twice. This
> keeps operational totals, insights, and surveillance views consistent.

## CHO workflow — approximately 1 minute

**0:00–0:10 — Command center**

> The City Health Operations Command Center reports that all Firestore sources
> are synchronized and resolves the 78 Barangay 03 patient records available to
> authorized CHO staff.

**0:10–0:26 — Patient workspace**

> The CHO patient workspace reads the same canonical resident records used by
> the BHW portal. Legacy patient-name fields are normalized so resident names no
> longer appear blank.

**0:26–0:42 — Checkup workspace**

> The clinical workspace exposes the synchronized checkup records without
> duplicating root and barangay-scoped mirrors. Existing undated consultations
> remain available for review while date-based statistics remain evidence-led.

**0:42–0:58 — Clinical insights**

> CHO insights, program summaries, and geographic surveillance now consume the
> same filtered and deduplicated sources. Synthetic records are excluded from
> production totals and mapping.

## Doctor access administration — approximately 30 seconds

**0:00–0:10 — Managed accounts**

> CHO administrators manage approved BHW and doctor accounts from one secured
> access center. Active doctors remain visible without exposing passwords.

**0:10–0:22 — Roles and permissions**

> The permissions view separates account identity from operational access and
> keeps authorization under CHO control rather than relying on hidden frontend
> controls.

**0:22–0:30 — Return to users**

> Administrators can review account status and assigned access while clinical
> work remains protected inside each role-specific portal.

> Recording note: this segment uses the authenticated CHO administration page.
> A doctor-authenticated portal was not recorded because no doctor credential
> was provided, and no account password was reset or bypassed.
