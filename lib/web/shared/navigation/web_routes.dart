import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';

/// Canonical browser paths for the web portals.
///
/// Keep route strings in one place so drawer navigation, login redirects, and
/// GetX route registration cannot drift apart. Legacy paths remain registered
/// in `main.dart` for compatibility, but all new navigation uses these paths.
abstract final class WebRoutes {
  /// Root is the canonical public entry path. The former branded path remains
  /// registered as a compatibility alias so existing bookmarks still work.
  static const landing = '/';
  static const legacyLanding = '/aidsuhis';
  static const login = '/login';
  static const bhwLogin = '/bhw/login';
  static const choLogin = '/cho/login';
  static const signup = '/signup';
  static const bhwSignup = '/bhw/signup';
  static const forgotPassword = '/forgot-password';
  static const notFound = '/not-found';

  static const bhwDashboard = '/bhw/dashboard';
  static const bhwPatients = '/bhw/patients';
  static const bhwCheckups = '/bhw/checkups';
  static const bhwPrenatal = '/bhw/prenatal';
  static const bhwImmunization = '/bhw/immunization';
  static const bhwCommunicable = '/bhw/communicable';
  static const bhwNonCommunicable = '/bhw/non-communicable';
  static const bhwMorbidity = '/bhw/morbidity';
  static const bhwMortality = '/bhw/mortality';
  static const bhwReferrals = '/bhw/referrals';
  static const bhwSummary = '/bhw/summary';
  static const bhwAnalytics = '/bhw/analytics';
  static const bhwProfile = '/bhw/profile';

  static const choDashboard = '/cho/dashboard';
  static const choPatients = '/cho/patients';
  static const choCheckups = '/cho/checkups';
  static const choPrenatal = '/cho/prenatal';
  static const choImmunization = '/cho/immunization';
  static const choMorbidity = '/cho/morbidity';
  static const choMortality = '/cho/mortality';
  static const choReferrals = '/cho/referrals';
  static const choBhwManagement = '/cho/bhw-management';
  static const choReports = '/cho/reports';
  static const choAnnouncements = '/cho/announcements';
  static const choDataQuality = '/cho/data-quality';
  static const choAuditLogs = '/cho/audit-logs';
  static const choNotifications = '/cho/notifications';
  static const choProfile = '/cho/profile';
  static const choSuperAdmin = '/cho/super-admin';
  static const choManageAccess = '/cho/manage-access';
  // Legacy name retained for existing bookmarks and integrations.
  static const choRoleManager = '/cho/role-manager';
  static const doctorDashboard = '/doctor/dashboard';
  static const doctorArchive = '/doctor/archive';
  static const doctorProfile = '/doctor/profile';
  // Legacy path kept for existing email links and bookmarks.
  static const doctorReferrals = '/doctor/referrals';

  static String choDestination(ChoDestination destination) {
    return switch (destination) {
      ChoDestination.dashboard => choDashboard,
      ChoDestination.patients => choPatients,
      ChoDestination.checkups => choCheckups,
      ChoDestination.prenatal => choPrenatal,
      ChoDestination.immunization => choImmunization,
      ChoDestination.morbidity => choMorbidity,
      ChoDestination.mortality => choMortality,
      ChoDestination.referrals => choReferrals,
      ChoDestination.bhwManagement => choBhwManagement,
      ChoDestination.manageChoAccess => choManageAccess,
      ChoDestination.reports => choReports,
      ChoDestination.announcements => choAnnouncements,
      ChoDestination.dataQuality => choDataQuality,
      ChoDestination.auditLogs => choAuditLogs,
      ChoDestination.notifications => choNotifications,
      ChoDestination.profile => choProfile,
    };
  }

  // Existing public paths retained as compatibility aliases.
  static const legacyCommunicable = '/CommunicablePage';
  static const legacyNonCommunicable = '/NonCommunicablePage';
  static const legacyReferrals = '/ReferralsPage';
  static const legacyCheckups = '/checkups';
  static const legacyPrenatal = '/prenatal';
  static const legacyMorbidity = '/morbidity';
  static const legacyMortality = '/mortality';
  static const legacyBhwProfile = '/bhw-profile';
  static const legacyChoBhwManagement = '/cho/bhwManagement';
  // Legacy BHW access links redirect to the consolidated BHW Management page.
  static const legacyChoBhwAccess = '/cho/bhw-access';
  static const legacyChoDataQuality = '/cho/dataQuality';
  static const legacyChoAuditLogs = '/cho/auditLogs';

  static const registeredPaths = <String>{
    landing,
    legacyLanding,
    login,
    bhwLogin,
    choLogin,
    signup,
    bhwSignup,
    forgotPassword,
    notFound,
    bhwDashboard,
    bhwPatients,
    bhwCheckups,
    bhwPrenatal,
    bhwImmunization,
    bhwCommunicable,
    bhwNonCommunicable,
    bhwMorbidity,
    bhwMortality,
    bhwReferrals,
    bhwSummary,
    bhwAnalytics,
    bhwProfile,
    choDashboard,
    choPatients,
    choCheckups,
    choPrenatal,
    choImmunization,
    choMorbidity,
    choMortality,
    choReferrals,
    choBhwManagement,
    choReports,
    choAnnouncements,
    choDataQuality,
    choAuditLogs,
    choNotifications,
    choProfile,
    choSuperAdmin,
    choManageAccess,
    choRoleManager,
    doctorDashboard,
    doctorArchive,
    doctorProfile,
    doctorReferrals,
    legacyCommunicable,
    legacyNonCommunicable,
    legacyReferrals,
    legacyCheckups,
    legacyPrenatal,
    legacyMorbidity,
    legacyMortality,
    legacyBhwProfile,
    legacyChoBhwManagement,
    legacyChoBhwAccess,
    legacyChoDataQuality,
    legacyChoAuditLogs,
  };

  /// Selects only the startup overrides that GetX cannot infer safely.
  ///
  /// Known deep links and unknown paths return `null` so GetX can resolve the
  /// registered route or its `unknownRoute` page. The former branded landing
  /// path alone needs an explicit override to open the canonical root path.
  static String? startupOverride(String defaultRouteName) {
    final uri = Uri.tryParse(defaultRouteName);
    if (uri == null) return landing;
    final path = uri.path;
    if (path.isEmpty) return landing;
    if (path == legacyLanding) return uri.replace(path: landing).toString();
    return null;
  }
}
