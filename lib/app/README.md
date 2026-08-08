# Mobile application architecture

The mobile client follows the same feature-first organization as the web
client. Pages, analytics, and persistence helpers are colocated by health
program, while cross-feature infrastructure is separated into core and shared
layers.

```text
lib/app/
|-- core/
|   `-- services/       AI, Firebase Functions, sync, and platform adapters
|-- dev/                Development-only data seeding utilities
|-- features/
|   |-- analytics/      Mobile-wide analytics and summary generation
|   |-- auth/           Login, signup, verification, and password recovery
|   |-- checkups/       Check-up records, analytics, and persistence
|   |-- dashboard/      BHW home and barangay views
|   |-- immunization/   Immunization records, analytics, and persistence
|   |-- patients/       Patient registry, persistence, and medical history
|   |-- prenatal/       Prenatal records, analytics, and persistence
|   |-- referrals/      Mobile referral workflow
|   `-- surveillance/
|       |-- communicable/
|       |-- morbidity/
|       |-- mortality/
|       `-- non_communicable/
|-- shared/
|   `-- widgets/        Reusable mobile presentation components
`-- shell/              Mobile landing page, wrapper, and secondary entry point
```

## Dependency rules

1. Feature code may depend on `core`, `shared`, and application-wide
   `lib/shared` utilities.
2. Core services must not depend on presentation pages.
3. Database helpers remain inside the feature that owns their records.
4. Development seeders stay under `dev` and must not be used by production UI.
5. New files use lowercase `snake_case.dart` names.

The primary cross-platform application entry remains `lib/main.dart`.
