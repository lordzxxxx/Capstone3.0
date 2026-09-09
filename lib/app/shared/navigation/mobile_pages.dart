import 'package:get/get.dart';

import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/shell/landing.dart' as app;
import 'package:mycapstone_project/app/features/auth/login.dart' as app_login;
import 'package:mycapstone_project/app/features/auth/signup.dart' as app_signup;
import 'package:mycapstone_project/app/features/auth/forgot.dart' as app_forgot;
import 'package:mycapstone_project/app/features/auth/verification_code.dart'
    as app_verification;
import 'package:mycapstone_project/app/features/auth/new_password.dart'
    as app_new_password;
import 'package:mycapstone_project/app/features/dashboard/homepage.dart'
    as app_dashboard;
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
import 'package:mycapstone_project/app/features/analytics/analytics.dart'
    as app_analytics;
import 'package:mycapstone_project/app/features/referrals/referrals.dart'
    as app_referrals;
import 'package:mycapstone_project/web/shared/utils/auth_guard_middleware.dart';

/// Manages all Mobile [GetPage] route definitions.
class MobilePages {
  /// Master list of all registered mobile route pages.
  static List<GetPage> get pages => [
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
            final email =
                arguments is Map ? (arguments['email'] ?? '').toString() : '';
            return app_verification.VerificationCode(email: email);
          },
        ),
        GetPage(
          name: MobileRoutes.newPassword,
          page: () {
            final arguments = Get.arguments;
            final email =
                arguments is Map ? (arguments['email'] ?? '').toString() : '';
            final code =
                arguments is Map ? (arguments['code'] ?? '').toString() : '';
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
                arguments is Map && arguments['openRegistrationOnLoad'] == true;
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
      ];
}
