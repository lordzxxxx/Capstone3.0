import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

void main() {
  group('WebRoutes.startupOverride', () {
    test('moves the former branded URL to the canonical root route', () {
      expect(WebRoutes.startupOverride('/'), isNull);
      expect(WebRoutes.startupOverride(''), WebRoutes.landing);
      expect(WebRoutes.startupOverride('/aidsuhis'), WebRoutes.landing);
      expect(
        WebRoutes.startupOverride('/aidsuhis?from=bookmark'),
        '/?from=bookmark',
      );
    });

    test('preserves registered deep links and query parameters', () {
      expect(WebRoutes.startupOverride('/login'), isNull);
      expect(WebRoutes.startupOverride('/bhw/patients?view=records'), isNull);
      expect(WebRoutes.startupOverride('/cho/dataQuality'), isNull);
    });

    test('lets GetX resolve unknown paths through its unknown-route page', () {
      expect(WebRoutes.startupOverride('/not-a-real-route'), isNull);
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
