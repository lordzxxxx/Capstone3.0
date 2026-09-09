import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:mycapstone_project/web/features/auth/landing.dart' as web;
import 'package:mycapstone_project/web/features/auth/login.dart' as web_login;
import 'package:mycapstone_project/web/features/auth/bhw_registration.dart'
    as web_bhw_registration;
import 'package:mycapstone_project/web/features/auth/forgot.dart' as web_forgot;
import 'package:mycapstone_project/web/features/auth/auth_action.dart'
    as web_auth_action;
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/navigation/web_route_middleware.dart';
import 'package:mycapstone_project/web/shared/navigation/web_role_gate.dart';
import 'package:mycapstone_project/web/shared/utils/auth_guard_middleware.dart';

import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart'
    as web_bhw_dashboard;
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart'
    as web_bhw_patients;
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as web_checkup;
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart'
    as web_prenatal;
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart'
    as web_bhw_immunization;
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart'
    as web_communicable;
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart'
    as web_noncommunicable;
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart'
    as web_morbidity;
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart'
    as web_mortality;
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart'
    as web_referrals;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart'
    as web_bhw_summary;
import 'package:mycapstone_project/web/roles/bhw/analytics/bhw_analytics.dart'
    as web_bhw_analytics;
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_profile.dart'
    as web_bhw_profile;

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

import 'package:mycapstone_project/web/roles/doctor/doctor_portal.dart'
    as web_doctor_portal;

/// Manages all Web [GetPage] route definitions and access role gates.
class WebPages {
  static const Set<String> bhwWebRoles = <String>{'bhw'};
  static const Set<String> choWebRoles = <String>{
    'cho',
    'cho_admin',
    'cho_super_admin',
  };
  static const Set<String> choAdminWebRoles = <String>{
    'cho_admin',
    'cho_super_admin',
  };
  static const Set<String> doctorWebRoles = <String>{'doctor'};

  static Widget _guardWebPage({
    required Set<String> allowedRoles,
    required Widget child,
    String? requiredPermission,
  }) {
    return WebRoleGate(
      allowedRoles: allowedRoles,
      requiredPermission: requiredPermission,
      child: child,
    );
  }

  /// Master list of all registered web route pages.
  static List<GetPage> get pages => [
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
          name: WebRoutes.bhwLogin,
          page: () => const web_login.Login(expectedRole: 'bhw'),
        ),
        GetPage(
          name: WebRoutes.choLogin,
          page: () => const web_login.Login(expectedRole: 'cho'),
        ),
        GetPage(
          name: WebRoutes.doctorLogin,
          page: () => const web_login.Login(expectedRole: 'doctor'),
        ),
        GetPage(
          name: WebRoutes.signup,
          page: () => const web_bhw_registration.BhwRegistrationPage(),
        ),
        GetPage(
          name: WebRoutes.bhwSignup,
          page: () => const web_bhw_registration.BhwRegistrationPage(),
        ),
        GetPage(
          name: WebRoutes.forgotPassword,
          page: () => const web_forgot.ForgotPassword(),
        ),
        GetPage(
          name: WebRoutes.authResetPassword,
          page: () => const web_auth_action.AuthActionPage(),
        ),
        GetPage(
          name: WebRoutes.doctorAccountSetup,
          page: () => const web_auth_action.AuthActionPage(),
        ),
        GetPage(
          name: WebRoutes.notFound,
          page: () => const WebNotFoundPage(),
        ),
        GetPage(
          name: WebRoutes.bhwDashboard,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'dashboard.view',
            child: const web_bhw_dashboard.HomePage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwPatients,
          page: () {
            final arguments = Get.arguments;
            final openRegistration =
                arguments is Map && arguments['openRegistrationOnLoad'] == true;
            return _guardWebPage(
              allowedRoles: bhwWebRoles,
              requiredPermission: 'patients.view',
              child: web_bhw_patients.PatientRecordPage(
                openRegistrationOnLoad: openRegistration,
              ),
            );
          },
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwCheckups,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'checkups.view',
            child: const web_checkup.CheckUpPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwPrenatal,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'prenatal.view',
            child: const web_prenatal.PrenatalPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwImmunization,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'immunization.view',
            child: const web_bhw_immunization.ImmunizationPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwCommunicable,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'surveillance.view',
            child: const web_communicable.CommunicablePage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwNonCommunicable,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'surveillance.view',
            child: const web_noncommunicable.NonCommunicablePage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwMorbidity,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'surveillance.view',
            child: const web_morbidity.MorbidityPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwMortality,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'surveillance.view',
            child: const web_mortality.MortalityPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwReferrals,
          page: () {
            final arguments = Get.arguments;
            final initialPatient = arguments is Map
                ? arguments['initialPatient'] as Map<String, dynamic>?
                : null;
            final initialObservations = arguments is Map
                ? arguments['initialObservations'] as String?
                : null;
            return _guardWebPage(
              allowedRoles: bhwWebRoles,
              requiredPermission: 'referrals.create',
              child: web_referrals.BhwReferralPage(
                initialPatient: initialPatient,
                initialObservations: initialObservations,
              ),
            );
          },
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwSummary,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'reports.view',
            child: const web_bhw_summary.HealthMetricsPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwAnalytics,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'reports.view',
            child: const web_bhw_analytics.BHWAnalyticsPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.bhwProfile,
          page: () => _guardWebPage(
            allowedRoles: bhwWebRoles,
            requiredPermission: 'profile.view',
            child: const web_bhw_profile.BHWProfilePage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choDashboard,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'dashboard.view',
            child: const web_cho_dashboard.ChoDashboard(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choPatients,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'patients.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.patients,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choCheckups,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'checkups.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.checkups,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choPrenatal,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'prenatal.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.prenatal,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choImmunization,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'immunization.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.immunization,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choMorbidity,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'surveillance.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.morbidity,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choMortality,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'surveillance.view',
            child: web_cho_module.ChoModuleWorkspace(
              config: web_cho_config.ChoModuleConfig.mortality,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choReferrals,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'referrals.view',
            child: const web_cho_referrals.CHOPreferralPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choBhwManagement,
          page: () => _guardWebPage(
            allowedRoles: choAdminWebRoles,
            requiredPermission: 'bhw.requests.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.bhwManagement,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choReports,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'reports.view',
            child: const web_cho_analytics.AnalyticsPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choAnnouncements,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'notifications.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.announcements,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choDataQuality,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'data_quality.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.dataQuality,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choAuditLogs,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'audit.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.auditLogs,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choNotifications,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'notifications.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.notifications,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choProfile,
          page: () => _guardWebPage(
            allowedRoles: choWebRoles,
            requiredPermission: 'profile.view',
            child: const web_cho_support.ChoSupportCenter(
              section: web_cho_support.ChoSupportSection.profile,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choSuperAdmin,
          page: () => _guardWebPage(
            allowedRoles: choAdminWebRoles,
            requiredPermission: 'cho.users.view',
            child: const web_cho_super_admin.ChoSuperAdminCenter(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choRoleManager,
          page: () => _guardWebPage(
            allowedRoles: choAdminWebRoles,
            requiredPermission: 'rbac.view',
            child: const web_cho_role_manager.RoleManager(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.choManageAccess,
          page: () => _guardWebPage(
            allowedRoles: choAdminWebRoles,
            requiredPermission: 'rbac.view',
            child: const web_cho_role_manager.RoleManager(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.doctorDashboard,
          page: () => _guardWebPage(
            allowedRoles: doctorWebRoles,
            requiredPermission: 'referrals.assigned.view',
            child: const web_doctor_portal.DoctorPortalPage(),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.doctorArchive,
          page: () => _guardWebPage(
            allowedRoles: doctorWebRoles,
            requiredPermission: 'referrals.assigned.view',
            child: const web_doctor_portal.DoctorPortalPage(
              tab: web_doctor_portal.DoctorPortalTab.archive,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.doctorProfile,
          page: () => _guardWebPage(
            allowedRoles: doctorWebRoles,
            requiredPermission: 'profile.view',
            child: const web_doctor_portal.DoctorPortalPage(
              tab: web_doctor_portal.DoctorPortalTab.profile,
            ),
          ),
          middlewares: [AuthGuardMiddleware()],
        ),
        GetPage(
          name: WebRoutes.doctorReferrals,
          page: () => _guardWebPage(
            allowedRoles: doctorWebRoles,
            requiredPermission: 'referrals.assigned.view',
            child: const web_doctor_portal.DoctorPortalPage(),
          ),
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
          name: WebRoutes.legacyChoBhwAccess,
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
      ];

  /// The fallback route when a requested web page does not exist.
  static GetPage get unknownRoute => GetPage(
        name: WebRoutes.notFound,
        page: () => const WebNotFoundPage(),
      );
}

/// The 404 Not Found presentation widget for Web.
class WebNotFoundPage extends StatelessWidget {
  const WebNotFoundPage({super.key});

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
