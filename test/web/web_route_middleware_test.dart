import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/navigation/web_route_middleware.dart';

void main() {
  test(
    'legacy route redirects to the canonical path and preserves view state',
    () {
      final redirect = LegacyWebRouteMiddleware(
        '/bhw/checkups',
      ).redirect('/checkups?view=records');

      expect(redirect?.name, '/bhw/checkups?view=records');
    },
  );

  test('canonical route does not redirect again', () {
    final redirect = LegacyWebRouteMiddleware(
      '/bhw/checkups',
    ).redirect('/bhw/checkups?view=insights');

    expect(redirect, isNull);
  });
}
