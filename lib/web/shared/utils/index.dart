// Barrel exports for web-specific utilities, categorized by function.

// 1. Clinical PDF Generators & Builders
export 'record_pdf_builder.dart';
export 'pdf_fonts.dart';
export 'checkup_pdf.dart';
export 'patient_pdf.dart';
export 'prenatal_pdf.dart';
export 'immunization_pdf.dart';
export 'morbidity_pdf.dart';
export 'mortality_pdf.dart';
export 'referral_pdf.dart';
export 'summary_pdf.dart';
export 'summary_docx.dart';

// 2. Reporting & Launchers
export 'dashboard_report_launcher.dart';
export 'bhw_report_generation.dart';
export 'report_branding.dart';
export 'report_generation.dart';

// 3. Clinical Data & Risk Mappings
export 'clinical_record_mapping.dart';
export 'vital_risk_flags.dart';

// 4. Browser Platform Adapters
export 'browser_history.dart';
export 'browser_location.dart';
export 'browser_online_state.dart';
export 'browser_reload.dart';
export 'csv_download.dart';
export 'file_download.dart';
export 'report_download.dart';
export 'report_print.dart';
export 'web_file_picker.dart';

// 5. Auth & Middleware
export 'auth_guard_middleware.dart';
