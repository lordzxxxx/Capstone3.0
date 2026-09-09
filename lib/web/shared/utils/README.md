# Web Shared Utilities

This directory contains cross-cutting utilities, PDF builders, browser platform abstractions, and reporting engines used throughout the web client.

```text
lib/web/shared/utils/
├── index.dart                      # Barrel exports for all utilities
├── Clinical PDF Generation/
│   ├── record_pdf_builder.dart     # Core table builder & single-page layout engine
│   ├── pdf_fonts.dart              # Custom PDF font loaders (Helvetica / Roboto)
│   ├── checkup_pdf.dart            # Check-up record PDF report
│   ├── patient_pdf.dart            # Patient registration & health profile PDF
│   ├── prenatal_pdf.dart           # Prenatal record PDF report
│   ├── immunization_pdf.dart       # Immunization record PDF report
│   ├── morbidity_pdf.dart          # Morbidity case report PDF
│   ├── mortality_pdf.dart          # Mortality report PDF
│   ├── referral_pdf.dart           # Clinical referral handoff PDF
│   ├── summary_pdf.dart            # Analytics summary PDF
│   └── summary_docx.dart           # Analytics Word DOCX exporter
├── Reporting & Launchers/
│   ├── dashboard_report_launcher.dart  # Modal report previewer and generator dialog
│   ├── bhw_report_generation.dart      # Aggregation logic for barangay reports
│   ├── report_branding.dart            # City Health Office & Barangay headers/logos
│   └── report_generation.dart          # Base report generator interface
├── Clinical & Risk Helpers/
│   ├── clinical_record_mapping.dart    # Normalizes records for table displays
│   └── vital_risk_flags.dart           # Vitals threshold evaluator (BP, HR, SpO2)
├── Browser Platform Adapters/
│   ├── browser_history.dart            # Browser navigation history (_stub & _web)
│   ├── browser_location.dart           # Window URL and pathname extractor (_stub & _web)
│   ├── browser_online_state.dart       # Web network connectivity listener (_stub & _web)
│   ├── browser_reload.dart             # Programmatic browser window reload (_stub & _web)
│   ├── csv_download.dart               # In-memory CSV file downloader (_stub & _web)
│   ├── file_download.dart              # Generic blob/byte file downloader (_stub & _web)
│   ├── report_download.dart            # PDF blob downloader (_stub & _web)
│   ├── report_print.dart               # Direct browser window print trigger (_stub & _web)
│   └── web_file_picker.dart            # HTML file input picker wrapper (_stub & _web)
└── Auth & Middleware/
    └── auth_guard_middleware.dart      # Route guard redirecting unauthenticated users
```
