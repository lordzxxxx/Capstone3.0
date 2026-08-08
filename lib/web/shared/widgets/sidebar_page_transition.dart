import 'package:flutter/material.dart';

Route<T> buildSidebarPageRoute<T>({
  required Widget page,
  Offset begin = const Offset(0.08, 0),
  String? routeName,
}) {
  return PageRouteBuilder<T>(
    settings: routeName == null ? null : RouteSettings(name: routeName),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 440),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.88, curve: Curves.easeOut),
        ),
      );

      final slideAnimation = Tween<Offset>(
        begin: begin,
        end: Offset.zero,
      ).animate(curvedAnimation);

      final scaleAnimation = Tween<double>(
        begin: 0.992,
        end: 1,
      ).animate(curvedAnimation);

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(
          position: slideAnimation,
          child: ScaleTransition(scale: scaleAnimation, child: child),
        ),
      );
    },
  );
}
