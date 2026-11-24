# AI-DSUHIS Role and Module Screenshot Index

Captured from the live production site at `https://www.ai-dsuhis.com` on
November 24, 2026. Screenshots are authenticated where credentials were
available and contain only the normal workspace view; passwords are not shown.

## BHW — Barangay Health Worker

| Module | Route | Screenshot |
| --- | --- | --- |
| Operations dashboard and quick actions | `/bhw/dashboard` | [BHW dashboard](../output/playwright/role-pages/bhw-dashboard.png) |
| Patient registry and patient history entry point | `/bhw/patients?view=records` | [BHW patients](../output/playwright/role-pages/bhw-patients.png) |
| Check-up records and clinical insights | `/bhw/checkups?view=records` | [BHW checkups](../output/playwright/role-pages/bhw-checkups.png) |
| Barangay analytics and reporting filters | `/bhw/analytics` | [BHW analytics](../output/playwright/role-pages/bhw-analytics.png) |
| Referral coordination | `/bhw/referrals` | [BHW referrals](../output/playwright/role-pages/bhw-referrals.png) |

Additional BHW navigation modules present in the authenticated workspace:
prenatal care, immunization, communicable surveillance, non-communicable
surveillance, morbidity, mortality, summary generation, notifications, profile
and settings.

## CHO — City Health Office

| Module | Route | Screenshot |
| --- | --- | --- |
| Operations command center, sync status and program snapshot | `/cho/dashboard` | [CHO dashboard](../output/playwright/role-pages/cho-dashboard.png) |
| City-wide patient records | `/cho/patients` | [CHO patients](../output/playwright/role-pages/cho-patients.png) |
| City-wide check-up workspace | `/cho/checkups` | [CHO checkups](../output/playwright/role-pages/cho-checkups.png) |
| Reports and operational exports | `/cho/reports` | [CHO reports](../output/playwright/role-pages/cho-reports.png) |
| User, role and permission administration | `/cho/manage-access` | [CHO manage access](../output/playwright/role-pages/cho-manage-access.png) |

Additional CHO navigation modules present in the role-gated workspace:
prenatal, immunization, morbidity, mortality, referrals, BHW management,
announcements, data quality, audit logs, notifications, profile and settings,
super-admin and role-management controls where the account is authorized.

## Doctor — Doctor Portal

| Module | Route | Screenshot |
| --- | --- | --- |
| Protected Doctor Portal sign-in | `/doctor/login` | [Doctor login](../output/playwright/role-pages/doctor-login.png) |
| Unauthenticated portal protection result | `/doctor/dashboard` | [Doctor dashboard gate](../output/playwright/role-pages/doctor-dashboard-gated.png) |

The Doctor Portal contains the authenticated dashboard/referral workspace,
referral archive, profile, assigned-referral details, accept/update/close care
actions, referral transfer, and doctor-note history. A doctor-authenticated
workspace screenshot is not included because no doctor credential was supplied;
the route remains protected and was not bypassed or reset.

## Shared verification notes

- The live CHO dashboard displays 78 synchronized Barangay 03 patient records.
- BHW and CHO use the same canonical clinical record visibility and exclude
  synthetic demo records.
- Screenshot paths are local repository artifacts under
  `output/playwright/role-pages/`; they are intentionally not deployed as app
  assets.

## Presentation flow — use this order

The numbered copies below are the finalized sequence for the two-minute video.
Move through them in order; each step hands off to the next role or module.

1. [01 — BHW dashboard](../output/playwright/role-pages/flow/01-bhw-dashboard.png): open the field workflow.
2. [02 — BHW patients](../output/playwright/role-pages/flow/02-bhw-patients.png): register and retrieve residents.
3. [03 — BHW check-ups / AI input](../output/playwright/role-pages/flow/03-bhw-checkups-ai-input.png): enter symptoms or structured clinical fields.
4. [04 — BHW analytics](../output/playwright/role-pages/flow/04-bhw-analytics.png): review barangay-level insight.
5. [05 — BHW referrals](../output/playwright/role-pages/flow/05-bhw-referrals.png): hand off follow-up work.
6. [06 — CHO dashboard](../output/playwright/role-pages/flow/06-cho-dashboard.png): show synchronized city operations.
7. [07 — CHO patients](../output/playwright/role-pages/flow/07-cho-patients.png): review the shared registry.
8. [08 — CHO check-ups](../output/playwright/role-pages/flow/08-cho-checkups.png): review shared clinical records.
9. [09 — CHO reports](../output/playwright/role-pages/flow/09-cho-reports.png): export and coordinate operational reporting.
10. [10 — CHO manage access](../output/playwright/role-pages/flow/10-cho-manage-access.png): show roles and permissions.
11. [11 — Doctor login](../output/playwright/role-pages/flow/11-doctor-login.png): transition to the protected doctor role.
12. [12 — Doctor portal protection](../output/playwright/role-pages/flow/12-doctor-portal-protection.png): close on role-based security.

The original role-specific screenshots remain above for direct page reference;
the `flow/` copies are the finalized, ordered presentation set.
