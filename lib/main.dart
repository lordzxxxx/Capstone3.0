import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_bootstrap.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/firebase_app_check_bootstrap.dart';
// Use local stub for firebase_dynamic_links so the project builds
// without the actual package installed. Replace with real package
// import when adding `firebase_dynamic_links` to `pubspec.yaml`.
import 'firebase_dynamic_links_stub.dart';

// Import app and web versions
import 'package:mycapstone_project/app/shell/landing.dart' as app;
import 'package:mycapstone_project/app/shell/mobile_startup.dart';
import 'package:mycapstone_project/app/shell/mobile_session_gate.dart';
import 'package:mycapstone_project/app/shell/web_startup.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart'
    as app_dashboard;
import 'package:mycapstone_project/app/features/auth/login.dart' as app_login;
import 'package:mycapstone_project/app/features/auth/signup.dart' as app_signup;
import 'package:mycapstone_project/app/features/analytics/analytics.dart'
    as app_analytics;
import 'package:mycapstone_project/app/features/referrals/referrals.dart'
    as app_referrals;
import 'package:mycapstone_project/app/features/checkups/checkup.dart'
    as app_checkups;
import 'package:mycapstone_project/app/features/prenatal/prenatal.dart'
    as app_prenatal;
import 'package:mycapstone_project/app/features/immunization/immunization.dart'
    as app_immunization;
import 'package:mycapstone_project/app/features/patients/patient.dart'
    as app_patients;
import 'package:mycapstone_project/app/features/surveillance/communicable/communicable_list.dart'
    as app_communicable;
import 'package:mycapstone_project/app/features/surveillance/non_communicable/non_communicable.dart'
    as app_non_communicable;
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_list.dart'
    as app_morbidity;
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality.dart'
    as app_mortality;
import 'package:mycapstone_project/app/features/auth/forgot.dart' as app_forgot;
import 'package:mycapstone_project/app/features/auth/verification_code.dart'
    as app_verification;
import 'package:mycapstone_project/app/features/auth/new_password.dart'
    as app_new_password;
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart' as app_theme;
import 'package:mycapstone_project/web/features/auth/landing.dart' as web;
import 'package:mycapstone_project/web/features/auth/login.dart' as web_login;
import 'package:mycapstone_project/web/features/auth/signup.dart' as web_signup;
import 'package:mycapstone_project/web/features/auth/forgot.dart' as web_forgot;
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart'
    as web_bhw_dashboard;
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart'
    as web_bhw_patients;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart'
    as web_bhw_summary;
import 'package:mycapstone_project/web/roles/bhw/analytics/bhw_analytics.dart'
    as web_bhw_analytics;
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart'
    as web_bhw_immunization;
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_profile.dart'
    as web_bhw_profile;
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart'
    as web_communicable;
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart'
    as web_noncommunicable;
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart'
    as web_referrals;
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as web_checkup;
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart'
    as web_prenatal;
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart'
    as web_morbidity;
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart'
    as web_mortality;
import 'package:mycapstone_project/web/shared/utils/auth_guard_middleware.dart';
import 'package:mycapstone_project/web/shared/navigation/web_route_middleware.dart';
import 'package:mycapstone_project/web/roles/cho/dashboard/cho_dashboard.dart'
    as web_cho_dashboard;
import 'package:mycapstone_project/web/roles/cho/portal/cho_module_workspace.dart'
    as web_cho_module;
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart'
    as web_cho_config;
import 'package:mycapstone_project/web/roles/cho/portal/cho_support_center.dart'
    as web_cho_support;
import 'package:mycapstone_project/web/roles/cho/analytics/cho_analytics.dart'
    as web_cho_analytics;
import 'package:mycapstone_project/web/roles/cho/admin/cho_super_admin_center.dart'
    as web_cho_super_admin;
import 'package:mycapstone_project/web/roles/cho/admin/role_manager.dart'
    as web_cho_role_manager;
import 'package:mycapstone_project/web/roles/cho/referrals/cho_referral_management.dart'
    as web_cho_referrals;
import 'package:mycapstone_project/web/roles/bhw/referrals/referrals.dart'
    as web_doctor_referrals;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Do not build Firebase-backed routes until Firebase Web has finished
    // initializing. FlutterFire's JS adapters can otherwise receive a Dart
    // FirebaseException during the startup race and surface a misleading
    // JavaScriptObject cast error.
    runApp(
      WebStartupGate(initialize: _initializeWebServices, child: const MyApp()),
    );
    return;
  }

  // Start the branded mobile shell immediately. Firebase and offline sync are
  // completed behind the startup gate so the native splash transitions into a
  // clean, animated AI-DSUHIS loading screen instead of a blank window.
  runApp(MyApp(mobileInitialization: _initializeMobileServices));
}

Future<void> _initializeMobileServices() async {
  // Mobile platforms use google-services.json/GoogleService-Info.plist.
  await Firebase.initializeApp().timeout(const Duration(seconds: 12));
  await _restoreFirebaseAuthSession();
  try {
    await activateFirebaseAppCheck();
  } catch (e) {
    if (!kDebugMode) rethrow;
    print('⚠️ [APP_CHECK] Could not initialize App Check on mobile: $e');
  }
  // Initialize dynamic links on mobile so password reset and other action
  // links can be handled in-app.
  await _initDynamicLinks();
  await initializeMobileOfflineSync();
}

Future<void> _initializeWebServices() async {
  try {
    print('🔵 [FIREBASE] Initializing Firebase for web...');
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyCi_JVTayAfb5cjS1CuYvZeB8Q6HyxBWfY",
          authDomain: "capstone-c98f9.firebaseapp.com",
          projectId: "capstone-c98f9",
          databaseURL: "https://capstone-c98f9-default-rtdb.firebaseio.com",
          storageBucket: "capstone-c98f9.firebasestorage.app",
          messagingSenderId: "628319595773",
          appId: "1:628319595773:web:afe9520590fad2a3192294",
          measurementId: "G-DFQ4GMPTHP",
        ),
      ).timeout(const Duration(seconds: 12));
    }
    print('✅ [FIREBASE] Firebase initialized');
  } catch (e) {
    print('❌ [FIREBASE] Initialization failed: $e');
    rethrow;
  }

  await _restoreFirebaseAuthSession();

  try {
    // App Check is a protection layer, but it must not prevent the public
    // shell from rendering when the browser cannot reach the attestation
    // provider. Firebase-backed actions will still surface their normal
    // authorization/error state when they are attempted.
    await activateFirebaseAppCheck().timeout(const Duration(seconds: 5));
  } catch (e) {
    print('⚠️ [APP_CHECK] Web activation skipped: $e');
  }

  try {
    final firestore = getFirestoreInstance();
    firestore.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
      webExperimentalAutoDetectLongPolling: false,
    );
    await firestore.enableNetwork().timeout(const Duration(seconds: 6));
    print('✅ [FIRESTORE] Ready for operations');
  } catch (e) {
    print('⚠️ [FIRESTORE] Configuration deferred: $e');
  }
}

/// Waits for Firebase Auth's first event before any route guard or data
/// bootstrap reads `currentUser`.
///
/// Native Firebase Auth already persists sessions by default. Web requires an
/// explicit local persistence setting so a browser refresh keeps the session;
/// the catch is intentional because some restricted browser contexts do not
/// allow the persistence adapter, while Auth can still restore its default
/// state safely.
Future<void> _restoreFirebaseAuthSession() async {
  final auth = FirebaseAuth.instance;

  if (kIsWeb) {
    try {
      await auth
          .setPersistence(Persistence.LOCAL)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      if (kDebugMode) {
        print('⚠️ [AUTH] Local web persistence unavailable: $error');
      }
    }
  }

  try {
    // Firebase normally emits this immediately after restoring the browser
    // session. A blocked/failed JS adapter must not leave the entire app on a
    // permanent startup spinner, however; the route shell can render and
    // Firebase will report the actionable error when a protected operation is
    // attempted.
    await auth.authStateChanges().first.timeout(const Duration(seconds: 8));
  } on TimeoutException catch (error) {
    if (kDebugMode) {
      print(
        '⚠️ [AUTH] Session restore timed out; continuing to app shell: $error',
      );
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.mobileInitialization});

  final Future<void> Function()? mobileInitialization;

  @override
  Widget build(BuildContext context) {
    final browserRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final initialRoute = kIsWeb && (browserRoute.isEmpty || browserRoute == '/')
        ? WebRoutes.landing
        : null;

    return GetMaterialApp(
      title: 'AI-DSUHIS',
      // Sourced from the shared AppColors/AppTheme and the mobile AppDesign
      // system so both platform shells use the same clinical blue, navy,
      // typography, card, button, and input defaults.
      theme: kIsWeb ? AppTheme.light(isWeb: true) : app_theme.AppDesign.theme(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      // Move the root entry to the branded path while preserving direct deep
      // links such as /login and /bhw/dashboard.
      initialRoute: initialRoute,
      // Platform-specific routing
      getPages: kIsWeb
          ? [
              GetPage(
                name: WebRoutes.landing,
                page: () => const web.LandingPage(),
              ),
              GetPage(
                name: WebRoutes.legacyLanding,
                page: () => const web.LandingPage(),
              ),
              GetPage(
                name: WebRoutes.login,
                page: () => const web_login.Login(),
              ),
              GetPage(
                name: WebRoutes.signup,
                page: () => const web_signup.Signup(),
              ),
              GetPage(
                name: WebRoutes.forgotPassword,
                page: () => const web_forgot.ForgotPassword(),
              ),
              GetPage(
                name: WebRoutes.bhwDashboard,
                page: () => const web_bhw_dashboard.HomePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwPatients,
                page: () {
                  final arguments = Get.arguments;
                  final openRegistration =
                      arguments is Map &&
                      arguments['openRegistrationOnLoad'] == true;
                  return web_bhw_patients.PatientRecordPage(
                    openRegistrationOnLoad: openRegistration,
                  );
                },
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwCheckups,
                page: () => const web_checkup.CheckUpPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwPrenatal,
                page: () => const web_prenatal.PrenatalPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwImmunization,
                page: () => const web_bhw_immunization.ImmunizationPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwCommunicable,
                page: () => const web_communicable.CommunicablePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwNonCommunicable,
                page: () => const web_noncommunicable.NonCommunicablePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwMorbidity,
                page: () => const web_morbidity.MorbidityPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwMortality,
                page: () => const web_mortality.MortalityPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwReferrals,
                page: () => const web_referrals.BhwReferralPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwSummary,
                page: () => const web_bhw_summary.HealthMetricsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwAnalytics,
                page: () => const web_bhw_analytics.BHWAnalyticsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.bhwProfile,
                page: () => const web_bhw_profile.BHWProfilePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choDashboard,
                page: () => const web_cho_dashboard.ChoDashboard(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choPatients,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.patients,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choCheckups,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.checkups,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choPrenatal,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.prenatal,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choImmunization,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.immunization,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choMorbidity,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.morbidity,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choMortality,
                page: () => web_cho_module.ChoModuleWorkspace(
                  config: web_cho_config.ChoModuleConfig.mortality,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choReferrals,
                page: () => const web_cho_referrals.CHOPreferralPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choBhwManagement,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.bhwManagement,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choReports,
                page: () => const web_cho_analytics.AnalyticsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choAnnouncements,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.announcements,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choDataQuality,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.dataQuality,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choAuditLogs,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.auditLogs,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choNotifications,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.notifications,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choProfile,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.profile,
                ),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choSuperAdmin,
                page: () => const web_cho_super_admin.ChoSuperAdminCenter(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.choRoleManager,
                page: () => const web_cho_role_manager.RoleManager(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: WebRoutes.doctorReferrals,
                page: () => const web_doctor_referrals.ReferralsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              // Compatibility aliases for existing links and bookmarks.
              GetPage(
                name: WebRoutes.legacyCommunicable,
                page: () => const web_communicable.CommunicablePage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwCommunicable),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyNonCommunicable,
                page: () => const web_noncommunicable.NonCommunicablePage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwNonCommunicable),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyReferrals,
                page: () => const web_referrals.BhwReferralPage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwReferrals),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyCheckups,
                page: () => const web_checkup.CheckUpPage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwCheckups),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyPrenatal,
                page: () => const web_prenatal.PrenatalPage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwPrenatal),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyMorbidity,
                page: () => const web_morbidity.MorbidityPage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwMorbidity),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyMortality,
                page: () => const web_mortality.MortalityPage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwMortality),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyBhwProfile,
                page: () => const web_bhw_profile.BHWProfilePage(),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.bhwProfile),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyChoBhwManagement,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.bhwManagement,
                ),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.choBhwManagement),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyChoDataQuality,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.dataQuality,
                ),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.choDataQuality),
                  AuthGuardMiddleware(),
                ],
              ),
              GetPage(
                name: WebRoutes.legacyChoAuditLogs,
                page: () => const web_cho_support.ChoSupportCenter(
                  section: web_cho_support.ChoSupportSection.auditLogs,
                ),
                middlewares: [
                  LegacyWebRouteMiddleware(WebRoutes.choAuditLogs),
                  AuthGuardMiddleware(),
                ],
              ),
            ]
          : [
              GetPage(
                name: MobileRoutes.landing,
                page: () => const app.LandingPage(),
              ),
              GetPage(
                name: MobileRoutes.login,
                page: () => const app_login.Login(),
              ),
              GetPage(
                name: MobileRoutes.signup,
                page: () => const app_signup.Signup(),
              ),
              GetPage(
                name: MobileRoutes.forgotPassword,
                page: () => const app_forgot.ForgotPassword(),
              ),
              GetPage(
                name: MobileRoutes.verificationCode,
                page: () {
                  final arguments = Get.arguments;
                  final email = arguments is Map
                      ? (arguments['email'] ?? '').toString()
                      : '';
                  return app_verification.VerificationCode(email: email);
                },
              ),
              GetPage(
                name: MobileRoutes.newPassword,
                page: () {
                  final arguments = Get.arguments;
                  final email = arguments is Map
                      ? (arguments['email'] ?? '').toString()
                      : '';
                  final code = arguments is Map
                      ? (arguments['code'] ?? '').toString()
                      : '';
                  return app_new_password.NewPassword(email: email, code: code);
                },
              ),
              GetPage(
                name: MobileRoutes.dashboard,
                page: () => const app_dashboard.HomePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.checkups,
                page: () => const app_checkups.CheckUpPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.prenatal,
                page: () => const app_prenatal.PrenatalPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.immunization,
                page: () => const app_immunization.ImmunizationPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.patients,
                page: () {
                  final arguments = Get.arguments;
                  final openRegistration =
                      arguments is Map &&
                      arguments['openRegistrationOnLoad'] == true;
                  return app_patients.PatientRecordPage(
                    openRegistrationOnLoad: openRegistration,
                  );
                },
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.communicable,
                page: () => const app_communicable.CommunicableListPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.nonCommunicable,
                page: () => const app_non_communicable.NonCommunicablePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.morbidity,
                page: () => const app_morbidity.MorbidityListPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.mortality,
                page: () => const app_mortality.MortalityPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.analytics,
                page: () => const app_analytics.AnalyticsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.referrals,
                page: () => const app_referrals.ReferralsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              // Compatibility aliases for previously published mobile paths.
              GetPage(
                name: MobileRoutes.legacyLogin,
                page: () => const app_login.Login(),
              ),
              GetPage(
                name: MobileRoutes.legacySignup,
                page: () => const app_signup.Signup(),
              ),
              GetPage(
                name: MobileRoutes.legacyAnalytics,
                page: () => const app_analytics.AnalyticsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: MobileRoutes.legacyReferrals,
                page: () => const app_referrals.ReferralsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
            ],
      home: kIsWeb
          ? null
          : MobileStartupGate(
              initialize: mobileInitialization ?? () async {},
              child: const MobileSessionGate(),
            ),
      unknownRoute: GetPage(
        name: WebRoutes.notFound,
        page: () => const _WebNotFoundPage(),
      ),
    );
  }
}

class _WebNotFoundPage extends StatelessWidget {
  const _WebNotFoundPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(title: const Text('AI-DSUHIS')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.link_off_outlined,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The requested page does not exist or is no longer available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Get.offAllNamed(WebRoutes.landing),
                child: const Text('Return to landing page'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _initDynamicLinks() async {
  // Only initialize dynamic links on non-web platforms
  if (kIsWeb) return;
  try {
    final dynamicLinks = getFirebaseDynamicLinks();
    final initialLink = await dynamicLinks?.getInitialLink();
    if (initialLink?.link != null) {
      // Handle the deep link, e.g., parse parameters and navigate
      // ignore: avoid_print
      print('Dynamic Link (initial): ${initialLink!.link}');
    }

    dynamicLinks?.onLink
        .listen((dynamicLinkData) {
          final Uri deepLink = dynamicLinkData.link;
          // Handle the deep link - navigate to reset screen or handle code
          // ignore: avoid_print
          print('Dynamic Link (onLink): $deepLink');
        })
        .onError((error) {
          // ignore: avoid_print
          print('Dynamic Link error: $error');
        });
  } catch (e) {
    // ignore: avoid_print
    print('Error initializing dynamic links: $e');
  }
}

// Platform-aware stub for getFirebaseDynamicLinks
dynamic getFirebaseDynamicLinks() {
  if (kIsWeb) return null;
  // On non-web platforms, FirebaseDynamicLinks is available via conditional import above
  // Use try-catch to avoid undefined name error if not available
  try {
    // ignore: undefined_identifier
    return FirebaseDynamicLinks.instance;
  } catch (_) {
    return null;
  }
}
