import 'package:flutter/material.dart';

Route<T> buildAuthPageRoute<T>({
  required Widget page,
  Offset begin = const Offset(0.06, 0),
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 420),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.82, curve: Curves.easeOut),
        ),
      );

      final slideAnimation = Tween<Offset>(
        begin: begin,
        end: Offset.zero,
      ).animate(curvedAnimation);

      final scaleAnimation = Tween<double>(
        begin: 0.985,
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

Future<T?> pushAuthPage<T>(
  BuildContext context,
  Widget page, {
  Offset begin = const Offset(0.06, 0),
}) {
  return Navigator.of(
    context,
  ).push<T>(buildAuthPageRoute<T>(page: page, begin: begin));
}

Future<T?> replaceWithAuthPage<T>(
  BuildContext context,
  Widget page, {
  Offset begin = const Offset(0.06, 0),
}) {
  return Navigator.of(context).pushReplacement<T, Object?>(
    buildAuthPageRoute<T>(page: page, begin: begin),
  );
}
