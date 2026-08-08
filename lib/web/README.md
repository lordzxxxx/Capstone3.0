# Web application architecture

The web client is separated first by user role, then by feature. BHW and CHO
pages, data helpers, and role-specific UI live under `roles`, while code used
by both roles stays under `features` or `shared`.

```text
lib/web/
|-- features/
|   `-- auth/           Shared login, signup, recovery, and access sessions
|-- roles/
|   |-- bhw/
|   |   |-- analytics/      Barangay-level analytics and AI summaries
|   |   |-- checkups/       Check-up records and persistence
|   |   |-- dashboard/      BHW dashboard and profile
|   |   |-- immunization/   Immunization records and persistence
|   |   |-- patients/       Patient registry, history, and search
|   |   |-- prenatal/       Prenatal records, widgets, and components
|   |   |-- referrals/      BHW referral workflow
|   |   `-- surveillance/   Morbidity, mortality, and disease monitoring
|   `-- cho/
|       |-- admin/          Account and role administration
|       |-- analytics/      City-wide analytics and compatibility export
|       |-- dashboard/      CHO executive dashboard
|       `-- referrals/      CHO referral review workflow
|-- shared/
|   |-- components/     Reusable navigation, dialogs, and module controls
|   |-- services/       Cross-feature access, branding, and workspace services
|   |-- utils/          Reporting, PDF, download, and printing utilities
|   `-- widgets/        Reusable web-only widgets and transitions
`-- shell/              Secondary web entry point and authentication wrapper
```

## Dependency rules

1. Role code may import its own role modules, `web/shared`, application-wide
   `lib/shared`, and core Firebase helpers.
2. Direct imports between `roles/bhw` and `roles/cho` should be avoided. Put
   genuinely shared behavior under `web/shared` or `lib/shared`.
3. Shared navigation may import both role entry points only to construct
   routes; it must not own role-specific state.
4. Module-specific database helpers stay with their owning role and feature.
5. Authentication remains role-neutral under `features/auth`.
6. New filenames use lowercase `snake_case.dart`.
7. Cross-platform mobile code under `lib/app` may consume web shared services
   temporarily, but new shared business logic should move to `lib/shared`.

The primary application entry remains `lib/main.dart`.

## Patient-first service workflow

The BHW Patient registry is the canonical identity source for clinical
services. Creating a Check-up, Prenatal, Immunization, Mortality, or Referral
record must begin with a registered-patient search and selection. Morbidity
records are derived from patient-linked Check-up assessments. If no registered
patient matches, the user must create the Patient record before continuing.

New service records retain `patientId` and `linkedPatientId`; patient names are
display data and must not be treated as the primary relationship key.

Canonical Patient registration is performed once and stores an auto-generated
Patient ID, full name, date of birth, calculated age, sex, address, barangay,
household ID, contact number, emergency contact, baseline medical history, and
optional allergies. Duplicate name/date-of-birth/contact matches are blocked
so staff reuse the existing Patient record.

The BHW Patient module has exactly two views:

- **Summary** derives barangay-level registration, household, demographic,
  health, follow-up, alert, and recent-registration indicators from the
  already scoped patient records. It does not expose CHO executive analytics.
- **Records** provides the searchable and paginated patient registry. Patient
  profile actions reuse the selected `patientId` when opening Check-up,
  Prenatal, Immunization, Mortality, and Referral workflows. The profile
  timeline reuses `PatientCenteredHistoryService` to load linked service
  records without introducing a second patient data source.
