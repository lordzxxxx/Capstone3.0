# AI-DSUHIS Project Architecture & Navigation Guide

This document is the master architectural guide for the AI-DSUHIS (Artificial Intelligence - Decision Support Urban Health Information System) codebase. It is designed to help engineers understand system layout, find code quickly, and follow established design patterns.

---

## 1. System Overview

AI-DSUHIS is a multi-role, dual-platform digital health suite built with Flutter and Firebase:
- **Web Client**: High-density desktop portal tailored for **Barangay Health Workers (BHW)**, **City Health Officers (CHO)**, and **Consulting Doctors**.
- **Mobile Client**: Touch-optimized, offline-first application for **BHWs** operating in field environments with intermittent connectivity.
- **Backend & Persistence**: Firebase Firestore (cloud documents), Firebase Authentication, Firebase Storage, and local SQLite for offline resilience.

---

## 2. Directory Structure Map

```text
c:\Users\THEO\Documents\Capstone3.0\
├── ARCHITECTURE.md                  # Master architecture & navigation guide (this file)
├── pubspec.yaml                     # Dependencies and asset declarations
├── lib/
│   ├── main.dart                    # Application orchestrator (~270 lines): startup, theme, route mounting
│   ├── firebase_helper.dart         # Firestore & Firebase instance resolver
│   ├── firebase_app_check_bootstrap.dart # App Check attestation initializer
│   │
│   ├── shared/                      # Cross-platform domain logic (used by BOTH Web & Mobile)
│   │   ├── index.dart               # Master barrel export for shared constants & data
│   │   ├── barangay_scope_utils.dart# Barangay filtering, access scoping & boundaries
│   │   ├── malaybalay_barangays.dart# Canonical list of 46 Malaybalay barangays
│   │   ├── official_report_layout.dart # Official Republic/LGU report header & signatures
│   │   ├── input_validation.dart    # Field validators (email, phone, dates)
│   │   ├── password_policy.dart     # Password complexity & security enforcement
│   │   ├── privacy_notice.dart      # Data privacy act disclosures & consent dialogs
│   │   ├── services/
│   │   │   └── index.dart           # AI clinical decision support & rate limiter exports
│   │   └── widgets/                 # Cross-platform clinical insight cards & banners
│   │
│   ├── app/                         # MOBILE CLIENT (Android / iOS)
│   │   ├── README.md                # Mobile architecture documentation
│   │   ├── core/                    # Mobile offline sync bootstrap & background services
│   │   │   └── services/index.dart  # Mobile core services barrel export
│   │   ├── dev/                     # Test data seeders & connection diagnostics
│   │   ├── features/                # BHW Clinical Feature Modules:
│   │   │   ├── index.dart           # Master barrel export for all mobile features & SQLite
│   │   │   ├── analytics/           # Mobile barangay health indicators
│   │   │   ├── auth/                # Login, signup, password reset
│   │   │   ├── checkups/            # Routine checkup workflow & offline SQLite
│   │   │   ├── dashboard/           # BHW mobile home & quick actions
│   │   │   ├── immunization/        # Child/adult vaccination tracking
│   │   │   ├── patients/            # Patient registry & clinical history
│   │   │   ├── prenatal/            # Maternal & prenatal health tracking
│   │   │   ├── referrals/           # Mobile referral generation
│   │   │   └── surveillance/        # Communicable, non-communicable, morbidity, mortality
│   │   ├── shared/                  # Mobile-specific shared components:
│   │   │   ├── navigation/          # mobile_routes.dart & mobile_pages.dart
│   │   │   ├── services/index.dart  # PDF service & OCR scanner service
│   │   │   ├── utils/               # Form field OCR fuzzy text matcher
│   │   │   └── widgets/index.dart   # Mobile clinical cards, pagination, & action sheets
│   │   ├── shell/                   # Mobile branded landing & startup session gates
│   │   └── theme/                   # Mobile typography & material theme
│   │
│   └── web/                         # WEB CLIENT (BHW, CHO, Doctor Portals)
│       ├── README.md                # Web architecture documentation
│       ├── features/
│       │   └── auth/                # Web auth (login, BHW registration, password recovery)
│       ├── roles/                   # Role-isolated presentation modules:
│       │   ├── bhw/                 # Barangay Health Worker web modules
│       │   │   ├── analytics/       # Barangay metrics & AI summaries
│       │   │   ├── checkups/        # Checkup registry & data tables
│       │   │   ├── dashboard/       # BHW dashboard & profile
│       │   │   ├── immunization/    # Immunization records & schedules
│       │   │   ├── patients/        # Master patient registry & clinical timeline
│       │   │   ├── prenatal/        # Prenatal visits, risk scoring & trimesters
│       │   │   ├── referrals/       # Referral creation & transfer handoff
│       │   │   └── surveillance/    # Morbidity, mortality, communicable & non-communicable
│       │   ├── cho/                 # City Health Office executive modules
│       │   │   ├── admin/           # Super Admin, RBAC role manager & user permissions
│       │   │   ├── analytics/       # City-wide epidemiological analytics & exports
│       │   │   ├── dashboard/       # Executive command center
│       │   │   ├── portal/          # Universal module workspace & support center
│       │   │   └── referrals/       # Referral triage, assignment & doctor handoff
│       │   └── doctor/              # Doctor clinical portal (referrals review, prescriptions)
│       ├── shared/                  # Web-specific shared infrastructure
│       │   ├── components/          # Sidebar, top bar, data tables, responsive layouts
│       │   ├── navigation/          # Web routing, role gates, and URL handling:
│       │   │   ├── web_routes.dart  # Web path constants & URL overrides
│       │   │   ├── web_pages.dart   # All Web GetPage definitions & role gates
│       │   │   └── web_role_gate.dart # Role-based access control widget
│       │   ├── theme/               # Web design system, typography & colors
│       │   ├── utils/               # PDF builders, browser adapters, report generators
│       │   │   ├── index.dart       # Barrel exports for all web utilities
│       │   │   ├── README.md        # Documentation of web utilities
│       │   │   ├── record_pdf_builder.dart # Core 1-page formal table PDF engine
│       │   │   └── ...              # Module PDFs, browser adapters, report tools
│       │   └── widgets/             # Web notifications, dialogs, badges
│       └── shell/                   # WebStartupGate & authentication wrapper
└── test/                            # Unit and regression test suites
    ├── pdf_page_count_test.dart     # Automated 1-page fit verification for all PDFs
    └── generate_all_filled_pdfs_test.dart # Test data populator for clinical PDFs
```

---

## 3. Web Role Architecture

The web application enforces strict role-based separation under `lib/web/roles/`:

### 1. BHW (`lib/web/roles/bhw/`)
- Scoped to the logged-in BHW's assigned Barangay.
- **Canonical Patient Registry**: Every clinical record (Check-up, Prenatal, Immunization, Mortality, Referral) must link to a verified `patientId`.
- **Clinical Modules**:
  - `checkups/`: General adult and pediatric consultations.
  - `prenatal/`: Gravida, para, expected delivery date, danger signs, and trimester monitoring.
  - `immunization/`: Doses, vaccine schedules, and growth monitoring.
  - `surveillance/`: Morbidity (derived from checkups) and Mortality records.
  - `referrals/`: Referral creation to CHO and external facilities.

### 2. CHO (`lib/web/roles/cho/`)
- City-wide administrative and epidemiological oversight.
- **Workspace Architecture** (`portal/cho_module_workspace.dart`): Reusable workspace shell hosting data tables, filtering, and audit inspection across any clinical domain.
- **Admin Center** (`admin/`): Account approvals, RBAC role assignments, permission matrix toggles, and system audit logs.
- **Referrals** (`referrals/cho_referral_management.dart`): Triage incoming barangay referrals, assign to doctors, and track clinical status.

### 3. Doctor (`lib/web/roles/doctor/`)
- Focused on telehealth and assigned patient referrals (`doctor_portal.dart`).
- Features a review queue, direct clinical history inspection, doctor orders, prescriptions, and referral status updates (Accepted, In Progress, Completed, Transferred).

---

## 4. Navigation & Routing Structure

Routing is cleanly decoupled from `main.dart`:

| Module | Location | Purpose |
|---|---|---|
| **Web Route Constants** | `lib/web/shared/navigation/web_routes.dart` | Clean string path constants (e.g. `/bhw/dashboard`, `/cho/analytics`) |
| **Web Route Pages** | `lib/web/shared/navigation/web_pages.dart` | Complete list of `GetPage` definitions, middleware, and `WebRoleGate` guards |
| **Mobile Route Constants** | `lib/app/shared/navigation/mobile_routes.dart` | Clean string path constants for mobile screens |
| **Mobile Route Pages** | `lib/app/shared/navigation/mobile_pages.dart` | Complete list of `GetPage` definitions for mobile |
| **Application Entry** | `lib/main.dart` | Mounts `WebPages.pages` or `MobilePages.pages` depending on `kIsWeb` |

---

## 5. Clinical PDF Report Architecture

All clinical forms are generated using a formal, clean, single-page table standard:
- **Builder Engine**: `lib/web/shared/utils/record_pdf_builder.dart`
  - Eliminates card containers in favor of unshaded, crisp formal tables (`border: Border.all()`).
  - Strict **1-page vertical budgeting**: Computes exact cell heights, label font sizes, and paddings so headers, tables, 4-officer signatures, and footers fit precisely on one page.
- **Module Generators**:
  - Check-up: `checkup_pdf.dart`
  - Patient Profile: `patient_pdf.dart`
  - Prenatal: `prenatal_pdf.dart`
  - Immunization: `immunization_pdf.dart`
  - Morbidity: `morbidity_pdf.dart`
  - Mortality: `mortality_pdf.dart`
  - Referral: `referral_pdf.dart`
- **Automated Verification**: `test/pdf_page_count_test.dart` verifies that all 12 PDF variants (Web + Mobile) strictly render onto **1 single page**.

---

## 6. Developer "Where Do I Find X?" Cheat Sheet

| Task | Primary Location |
|---|---|
| **Add or update a web route** | `lib/web/shared/navigation/web_routes.dart` & `web_pages.dart` |
| **Add or update a mobile route** | `lib/app/shared/navigation/mobile_routes.dart` & `mobile_pages.dart` |
| **Modify official PDF header or signatures** | `lib/shared/official_report_layout.dart` |
| **Adjust PDF table styles or 1-page fit** | `lib/web/shared/utils/record_pdf_builder.dart` |
| **Change BHW table layouts** | `lib/web/roles/bhw/<module>/<module>.dart` |
| **Edit CHO executive features** | `lib/web/roles/cho/` |
| **Edit Doctor portal** | `lib/web/roles/doctor/doctor_portal.dart` |
| **AI screening or disease prediction** | `lib/shared/services/index.dart` |
| **Update global web theme/colors** | `lib/web/shared/theme/app_theme.dart` |
| **Update mobile theme** | `lib/app/theme/app_theme.dart` |
| **Run static analysis** | `flutter analyze` |
| **Run PDF page count test** | `flutter test test/pdf_page_count_test.dart` |
