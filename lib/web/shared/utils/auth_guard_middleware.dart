import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show RouteSettings;
import 'package:get/get.dart';

/// Blocks direct/URL navigation into a protected web route when no Firebase
/// user session exists, redirecting to the landing page instead.
///
/// This is a navigation-level convenience, not a security boundary: the
/// real boundary is Firestore/Storage security rules, which already deny
/// every clinical read/write to an unauthenticated caller regardless of
/// what the client renders. This middleware exists so an unauthenticated
/// visitor typing e.g. `/checkups` directly into the address bar lands on
/// the login flow instead of a workflow page that would just fail on every
/// data operation.
///
/// Web deliberately mounts the app shell (`runApp`) before `Firebase.
/// initializeApp()` resolves (see `_initializeWebServices` in main.dart) so
/// a slow/blocked Firebase connection never leaves a blank canvas. That
/// means a direct deep-link into a protected route can reach this
/// middleware before Firebase is ready. `FirebaseAuth.instance` throws in
/// that window, so this must not call it unguarded -- doing so previously
/// crashed the very first frame instead of redirecting. Since this
/// middleware is a UX convenience and not the real security boundary, the
/// safe failure mode is to let navigation continue rather than crash: the
/// page shell may render for a moment, but every real data read/write
/// still requires Firestore/Storage rules to pass regardless.
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
    return const RouteSettings(name: '/');
  }
}
