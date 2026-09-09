# Mobile Application Architecture & Developer Guide

The AI-DSUHIS mobile client is designed specifically for **Barangay Health Workers (BHWs)** operating in community and field clinic environments where internet connectivity is intermittent. It is built using a **feature-first**, **offline-first** architecture.

---

## 1. Directory Structure

```text
lib/app/
├── README.md                       # Mobile architecture documentation (this file)
│
├── core/                           # Mobile infrastructure & offline sync
│   └── services/
│       ├── index.dart              # Barrel export for all mobile core services
│       ├── mobile_sync_bootstrap.dart # SQLite-to-Firestore synchronization orchestrator
│       ├── mobile_sync_utils.dart  # Network connectivity listeners & online state
│       ├── cloud_functions_config.dart # Firebase Cloud Functions endpoints
│       └── tflite_stub.dart        # Platform-conditional TFLite stub
│
├── dev/                            # Development-only seeders & diagnostics
│   ├── barangay_test_data_seeder.dart # Local test records populator
│   └── firestore_connection_test.dart # Connectivity diagnostic script
│
├── features/                       # BHW Clinical Feature Modules
│   ├── index.dart                  # Master barrel export for all mobile features
│   ├── analytics/                  # Health indicators & trend charts
│   ├── auth/                       # Login, signup, verification, password recovery
│   ├── checkups/                   # Consultation records, analytics & SQLite helper
│   ├── dashboard/                  # BHW mobile home, barangay picker & quick actions
│   ├── immunization/               # Vaccines, dose schedules & SQLite helper
│   ├── patients/                   # Master patient registry, timeline & SQLite helper
│   ├── prenatal/                   # Maternal health, trimester tracking & SQLite helper
│   ├── referrals/                  # Mobile referral generation & tracking
│   └── surveillance/               # Disease surveillance:
│       ├── communicable/           # Communicable disease cases
│       ├── morbidity/              # Morbidity registry & SQLite helper
│       ├── mortality/              # Mortality records & SQLite helper
│       └── non_communicable/       # Chronic disease tracking
│
├── shared/                         # Mobile-specific shared components
│   ├── navigation/
│   │   ├── mobile_routes.dart      # Route string constants
│   │   └── mobile_pages.dart       # Modular GetPage declarations
│   ├── services/
│   │   ├── index.dart              # Barrel export (PDF generation, OCR scanning)
│   │   ├── clinical_form_pdf_service.dart # Mobile PDF generation
│   │   └── ocr_document_scanner_service.dart # Google ML Kit document scanner
│   ├── utils/
│   │   └── ocr_fuzzy_matcher.dart  # Form field text extractor & matcher
│   └── widgets/
│       ├── index.dart              # Barrel export for mobile widgets
│       ├── app_metric_card.dart    # KPI summary card
│       ├── health_record_card.dart # Clinical record card layout
│       ├── mobile_compact_controls.dart # Compact mobile toolbars
│       ├── mobile_pagination_controls.dart # Page navigation & items per page
│       ├── mobile_record_action_sheet.dart # Bottom sheet for record actions
│       ├── ocr_record_action.dart  # OCR camera scanning action button
│       └── privacy_notice_button.dart # In-app privacy policy viewer
│
├── shell/                          # Mobile startup & session gates
│   ├── landing.dart                # Mobile branded landing page
│   ├── mobile_startup.dart         # Mobile splash & initialization gate
│   ├── mobile_session_gate.dart    # Auth listener & route switcher
│   └── wrapper.dart                # Backward-compatible session wrapper
│
└── theme/                          # Mobile styling
    └── app_theme.dart              # AppDesign system, typography & colors
```

---

## 2. Offline-First Architecture & Sync Lifecycle

1. **Local SQLite Persistence**:
   - Each clinical module owns a dedicated database helper (e.g., `PatientDatabaseHelper`, `CheckupDatabaseHelper`, `PrenatalDatabaseHelper`, `ImmunizationDatabaseHelper`, `MorbidityDatabaseHelper`, `MortalityDatabaseHelper`).
   - Writes always commit to local SQLite first. Every local record maintains:
     - `isSynced` (0 = pending, 1 = synced)
     - `lastModified` (timestamp for conflict resolution)
     - `patientId` / `linkedPatientId` (relational identity key)

2. **Sync Bootstrap (`core/services/mobile_sync_bootstrap.dart`)**:
   - Runs in the background and activates upon network reconnect.
   - Pushes unsynced local rows (`isSynced == 0`) to Cloud Firestore under the assigned barangay scope (`barangays/{barangayId}/{collection}`).
   - Pulls recent updates from Firestore and reconciles conflicts using `lastModified`.

---

## 3. Optical Character Recognition (OCR) Pipeline

The mobile app includes a client-side document scanner powered by Google ML Kit:
- **Scanner Service** (`shared/services/ocr_document_scanner_service.dart`): Captures document images using the device camera or gallery.
- **Fuzzy Matcher** (`shared/utils/ocr_fuzzy_matcher.dart`): Uses token distance algorithms to extract patient names, dates of birth, blood pressure readings, and symptoms from physical paper health forms.
- **Record Action Trigger** (`shared/widgets/ocr_record_action.dart`): Floats on clinical pages allowing BHWs to auto-fill form fields by pointing the camera at physical paper records.

---

## 4. Mobile Navigation & Routing

Routing is managed via GetX and isolated in `shared/navigation/`:
- **Route Constants** (`mobile_routes.dart`): Defines string routes (e.g., `MobileRoutes.dashboard`, `MobileRoutes.checkups`).
- **Route Pages** (`mobile_pages.dart`): Configures `GetPage` instances, page transitions, arguments parsing, and auth middleware.
- **Shell Startup** (`shell/mobile_startup.dart`): Renders an animated branded splash screen while SQLite tables and Firebase Auth sessions are initialized.

---

## 5. Dependency Rules

1. **Feature isolation**: Features must not directly access another feature's internal SQLite database helper. Use public services or shared models.
2. **Cross-platform logic**: Core domain rules, barangay scopes, input validation, and AI screening engines live in `lib/shared/`.
3. **No Web imports**: Code in `lib/app/` must never import from `lib/web/`. Web startup code has been migrated to `lib/web/shell/`.
4. **Naming convention**: All file names use lowercase `snake_case.dart`.
