import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Short, low-distraction route motion for the operational web portal.
/// Reduced-motion users receive the final page without an animated fade.
class WebPageTransition extends CustomTransition {
  WebPageTransition();

  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: curve ?? Curves.easeOutCubic,
    );
    return FadeTransition(opacity: curved, child: child);
  }
}
