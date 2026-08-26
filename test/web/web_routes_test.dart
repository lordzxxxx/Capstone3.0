import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

void main() {
  group('WebRoutes.startupOverride', () {
    test('moves the root compatibility URL to the branded landing route', () {
      expect(WebRoutes.startupOverride('/'), WebRoutes.landing);
      expect(WebRoutes.startupOverride(''), WebRoutes.landing);
    });

    test('preserves registered deep links and query parameters', () {
      expect(WebRoutes.startupOverride('/login'), isNull);
      expect(WebRoutes.startupOverride('/bhw/patients?view=records'), isNull);
      expect(WebRoutes.startupOverride('/cho/dataQuality'), isNull);
    });

    test('sends only unknown paths to the not-found page', () {
      expect(
        WebRoutes.startupOverride('/not-a-real-route'),
        WebRoutes.notFound,
      );
    });
  });

  test('all BHW and CHO sidebar destinations resolve to registered routes', () {
    const bhwSidebarRoutes = [
      WebRoutes.bhwDashboard,
      WebRoutes.bhwPatients,
      WebRoutes.bhwCheckups,
      WebRoutes.bhwSummary,
      WebRoutes.bhwAnalytics,
      WebRoutes.bhwPrenatal,
      WebRoutes.bhwImmunization,
      WebRoutes.bhwCommunicable,
      WebRoutes.bhwNonCommunicable,
      WebRoutes.bhwMorbidity,
      WebRoutes.bhwMortality,
      WebRoutes.bhwReferrals,
      WebRoutes.bhwProfile,
    ];

    expect(bhwSidebarRoutes.every(WebRoutes.registeredPaths.contains), isTrue);
    for (final destination in ChoDestination.values) {
      expect(
        WebRoutes.registeredPaths,
        contains(WebRoutes.choDestination(destination)),
      );
    }
  });
}
