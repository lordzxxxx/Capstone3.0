import 'package:flutter/material.dart';

Route<T> buildSidebarPageRoute<T>({
  required Widget page,
  Offset begin = Offset.zero,
  String? routeName,
}) {
  return PageRouteBuilder<T>(
    settings: routeName == null ? null : RouteSettings(name: routeName),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return child;
      }
      final fadeAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

      return FadeTransition(opacity: fadeAnimation, child: child);
    },
  );
}
