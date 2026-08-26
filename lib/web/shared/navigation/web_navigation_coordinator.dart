import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Serializes web route changes and closes an open mobile drawer before the
/// next page is created. This prevents rapid taps from starting competing
/// route transitions and keeps the new page visible immediately.
class WebNavigationCoordinator {
  WebNavigationCoordinator._();

  static bool _isNavigating = false;

  static bool get isNavigating => _isNavigating;

  static Future<void> run(
    BuildContext context,
    Future<void> Function() navigation,
  ) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await _closeMobileDrawer(context);
      if (!context.mounted) return;
      await navigation();
    } finally {
      _isNavigating = false;
    }
  }

  static Future<void> goToNamed(BuildContext context, String route) {
    return run(context, () async {
      if (route == Get.currentRoute) return;
      // Do not await this future: it resolves only when the destination is
      // popped, which would leave the coordinator locked indefinitely.
      Get.offNamed<void>(route);
    });
  }

  static Future<void> _closeMobileDrawer(BuildContext context) async {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen != true) return;
    await Navigator.of(context).maybePop();
  }
}
