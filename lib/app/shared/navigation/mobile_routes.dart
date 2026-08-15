/// Canonical named routes for the Flutter application.
///
/// Native navigation does not expose browser URLs, but keeping these paths
/// centralized still gives every destination one stable identity for deep
/// links, tests, analytics, and future platform routing.
abstract final class MobileRoutes {
  static const landing = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const verificationCode = '/verification-code';
  static const newPassword = '/new-password';

  static const dashboard = '/app/dashboard';
  static const checkups = '/app/checkups';
  static const prenatal = '/app/prenatal';
  static const immunization = '/app/immunization';
  static const patients = '/app/patients';
  static const communicable = '/app/communicable';
  static const nonCommunicable = '/app/non-communicable';
  static const morbidity = '/app/morbidity';
  static const mortality = '/app/mortality';
  static const analytics = '/app/analytics';
  static const referrals = '/app/referrals';

  // Kept for older mobile deep links and existing GetX calls.
  static const legacyLogin = '/Login';
  static const legacySignup = '/Signup';
  static const legacyAnalytics = '/AnalyticsPage';
  static const legacyReferrals = '/ReferralsPage';
}
