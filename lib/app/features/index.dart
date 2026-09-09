// Master barrel exports for all mobile feature modules, analytics, and SQLite helpers.

// 1. Dashboard & Core Navigation
export 'dashboard/homepage.dart';
export 'dashboard/barangay.dart';

// 2. Authentication
export 'auth/login.dart';
export 'auth/signup.dart';
export 'auth/forgot.dart';
export 'auth/verification_code.dart';
export 'auth/new_password.dart';

// 3. Clinical Modules & Offline SQLite Persistence
export 'checkups/checkup.dart';
export 'checkups/checkup_database_helper.dart';
export 'checkups/checkup_analytics.dart';

export 'patients/patient.dart';
export 'patients/patient_database_helper.dart';
export 'patients/patient_analytics.dart';
export 'patients/patient_history_dialogs.dart';

export 'prenatal/prenatal.dart';
export 'prenatal/prenatal_database_helper.dart';
export 'prenatal/prenatal_analytics.dart';

export 'immunization/immunization.dart';
export 'immunization/immunization_database_helper.dart';
export 'immunization/immunization_analytics.dart';

export 'referrals/referrals.dart';
export 'referrals/referral_analytics.dart';

// 4. Disease Surveillance
export 'surveillance/communicable/communicable.dart';
export 'surveillance/morbidity/morbidity.dart';
export 'surveillance/morbidity/morbidity_database_helper.dart';
export 'surveillance/mortality/mortality.dart';
export 'surveillance/mortality/mortality_database_helper.dart';
export 'surveillance/non_communicable/non_communicable.dart';

// 5. Analytics
export 'analytics/analytics.dart';
export 'analytics/health_metrics.dart';
