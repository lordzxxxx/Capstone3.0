import 'package:flutter_test/flutter_test.dart';
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
}
