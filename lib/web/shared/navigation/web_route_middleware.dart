import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Redirects an older browser path to its canonical web route while retaining
/// supported query parameters such as module `view` state.
///
/// This is only a navigation compatibility layer. It does not grant access;
/// the destination route still runs its normal authentication middleware.
class LegacyWebRouteMiddleware extends GetMiddleware {
  LegacyWebRouteMiddleware(this.canonicalRoute);

  final String canonicalRoute;

  @override
  RouteSettings? redirect(String? route) {
    final current = Uri.tryParse(route ?? '');
    if (current == null || current.path == canonicalRoute) {
      return null;
    }

    final canonical = current.replace(path: canonicalRoute);
    return RouteSettings(name: canonical.toString());
  }
}
