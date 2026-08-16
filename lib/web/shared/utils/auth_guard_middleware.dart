import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show RouteSettings;
import 'package:get/get.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

/// Blocks direct/URL navigation into a protected web route when no Firebase
/// user session exists, redirecting to the login page instead.
///
/// This is a navigation-level convenience, not a security boundary: the
/// real boundary is Firestore/Storage security rules, which already deny
/// every clinical read/write to an unauthenticated caller regardless of
/// what the client renders. This middleware exists so an unauthenticated
/// visitor typing e.g. `/checkups` directly into the address bar lands on
/// the login flow instead of a workflow page that would just fail on every
/// data operation.
///
/// Web mounts the GetX shell behind `WebStartupGate`, which initializes
/// Firebase and waits for the first Auth event before protected pages are
/// built. The Firebase-apps check remains defensive for tests and alternate
/// entrypoints. This middleware is a UX convenience, not a security boundary:
/// Firestore/Storage rules still enforce every clinical read and write.
class AuthGuardMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final signedIn = FirebaseAuth.instance.currentUser != null;
    if (signedIn) {
      return null;
    }
    return const RouteSettings(name: WebRoutes.login);
  }
}
