import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:mycapstone_project/app/core/services/mobile_sync_bootstrap.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/firebase_app_check_bootstrap.dart';
// Use local stub for firebase_dynamic_links so the project builds
// without the actual package installed. Replace with real package
// import when adding `firebase_dynamic_links` to `pubspec.yaml`.
import 'firebase_dynamic_links_stub.dart';

import 'package:mycapstone_project/app/shell/mobile_startup.dart';
import 'package:mycapstone_project/app/shell/mobile_session_gate.dart';
import 'package:mycapstone_project/web/shell/web_startup.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_pages.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart' as app_theme;

import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/navigation/web_pages.dart';
import 'package:mycapstone_project/web/shared/navigation/web_page_transition.dart';
import 'package:mycapstone_project/web/shared/utils/browser_location.dart';
import 'package:mycapstone_project/web/shared/widgets/app_update_notification.dart';
import 'package:mycapstone_project/web/shared/utils/pdf_fonts.dart';
import 'package:mycapstone_project/web/shared/utils/report_branding.dart';

// Local QA/dev only: --dart-define=USE_FIREBASE_EMULATOR=true redirects
// Auth/Firestore to the local emulator suite. Defaults to false so a normal
// `flutter run`/`flutter build` always targets the real Firebase project.
const bool kUseFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

// Release-mode browser automation exercises the optimized bundle against
// local emulators. Requiring this second, explicit flag prevents a normal
// release build from ever selecting local services if only the emulator flag
// is supplied accidentally.
const bool kBrowserQaMode = bool.fromEnvironment('BROWSER_QA');

String? _webInitialRoute;

void main() async {
  // Flutter 3.44 locks the web URL strategy during binding initialization.
  // Set it first so `flutter run -d chrome` and release builds both start
  // with clean, path-based routes instead of failing before runApp().
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Keep browser URLs canonical and shareable. Without this, Flutter's
  // default hash strategy turns `/bhw/prenatal?view=insights` into
  // `/#/bhw/prenatal?view=insights`, which breaks direct links and makes
  // refresh/deep-link handling inconsistent with the route definitions.
  if (kIsWeb) {
    final platformRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final requestedRoute = browserLocationRoute() ?? platformRoute;
    _webInitialRoute =
        WebRoutes.startupOverride(requestedRoute) ?? requestedRoute;
  }

  if (kIsWeb) {
    // Do not build Firebase-backed routes until Firebase Web has finished
    // initializing. FlutterFire's JS adapters can otherwise receive a Dart
    // FirebaseException during the startup race and surface a misleading
    // JavaScriptObject cast error.
    runApp(
      WebStartupGate(initialize: _initializeWebServices, child: const MyApp()),
    );
    return;
  }

  // Start the branded mobile shell immediately. Firebase and offline sync are
  // completed behind the startup gate so the native splash transitions into a
  // clean, animated AI-DSUHIS loading screen instead of a blank window.
  runApp(MyApp(mobileInitialization: _initializeMobileServices));
}

Future<void> _initializeMobileServices() async {
  // Mobile platforms use google-services.json/GoogleService-Info.plist.
  await Firebase.initializeApp().timeout(const Duration(seconds: 12));
  await _restoreFirebaseAuthSession();
  try {
    await activateFirebaseAppCheck();
  } catch (e) {
    if (!kDebugMode) rethrow;
    debugPrint('⚠️ [APP_CHECK] Could not initialize App Check on mobile: $e');
  }
  // Initialize dynamic links on mobile so password reset and other action
  // links can be handled in-app.
  await _initDynamicLinks();
  await initializeMobileOfflineSync();
}

Future<void> _initializeWebServices() async {
  try {
    debugPrint('🔵 [FIREBASE] Initializing Firebase for web...');
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyCi_JVTayAfb5cjS1CuYvZeB8Q6HyxBWfY",
          authDomain: "capstone-c98f9.firebaseapp.com",
          projectId: "capstone-c98f9",
          databaseURL: "https://capstone-c98f9-default-rtdb.firebaseio.com",
          storageBucket: "capstone-c98f9.firebasestorage.app",
          messagingSenderId: "628319595773",
          appId: "1:628319595773:web:afe9520590fad2a3192294",
          measurementId: "G-DFQ4GMPTHP",
        ),
      ).timeout(const Duration(seconds: 12));
    }
    debugPrint('✅ [FIREBASE] Firebase initialized');
  } catch (e) {
    debugPrint('❌ [FIREBASE] Initialization failed: $e');
    rethrow;
  }

  // Local-only QA/dev hook: point Auth/Firestore at the Firebase emulator
  // suite instead of production. Requires an explicit dart-define AND
  // non-release mode or an explicitly marked browser-QA artifact. Production
  // release builds still cannot reach local services by accident because the
  // QA artifact requires both compile-time flags.
  if (kUseFirebaseEmulator && (!kReleaseMode || kBrowserQaMode)) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    getFirestoreInstance().useFirestoreEmulator('localhost', 8085);
    debugPrint('🧪 [EMULATOR] Connected to local Auth/Firestore emulators');
  }

  await _restoreFirebaseAuthSession();

  try {
    // App Check is a protection layer, but it must not prevent the public
    // shell (including Firebase Auth login) from rendering when the browser
    // cannot reach the attestation provider. Protected operations still
    // request an App Check token and fail closed when one is unavailable.
    await activateFirebaseAppCheck().timeout(const Duration(seconds: 5));
  } catch (e) {
    // Keep the shell available so users can reach login and receive a useful
    // operation-level error. AI requests explicitly require an App Check
    // token, while Firestore rules still enforce Firebase authentication.
    // This avoids converting a provider/domain outage into a total outage.
    debugPrint('⚠️ [APP_CHECK] Web activation unavailable: $e');
  }

  try {
    final firestore = getFirestoreInstance();
    firestore.settings = const Settings(
      // Web pages write directly to Firestore. Persistent cache allows
      // already-loaded records to remain readable offline and lets the
      // Firestore SDK queue writes until the connection returns.
      persistenceEnabled: true,
      cacheSizeBytes: 50 * 1024 * 1024,
      webPersistentTabManager: WebPersistentMultipleTabManager(),
      webExperimentalForceLongPolling: false,
      webExperimentalAutoDetectLongPolling: true,
    );
    await firestore.enableNetwork().timeout(const Duration(seconds: 6));
    debugPrint('✅ [FIRESTORE] Ready for operations');
  } catch (e) {
    debugPrint('⚠️ [FIRESTORE] Configuration deferred: $e');
  }

  // Pre-warm PDF fonts and official logos in the background so PDF generation is instantaneous
  unawaited(loadPdfFontBundle());
  unawaited(loadReportBranding(barangayName: ''));
}

/// Waits for Firebase Auth's first event before any route guard or data
/// bootstrap reads `currentUser`.
///
/// Native Firebase Auth already persists sessions by default. Web requires an
/// explicit local persistence setting so a browser refresh keeps the session;
/// the catch is intentional because some restricted browser contexts do not
/// allow the persistence adapter, while Auth can still restore its default
/// state safely.
Future<void> _restoreFirebaseAuthSession() async {
  final auth = FirebaseAuth.instance;

  if (kIsWeb) {
    try {
      await auth
          .setPersistence(Persistence.LOCAL)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ [AUTH] Local web persistence unavailable: $error');
      }
    }
  }

  try {
    // Firebase normally emits this immediately after restoring the browser
    // session. A blocked/failed JS adapter must not leave the entire app on a
    // permanent startup spinner, however; the route shell can render and
    // Firebase will report the actionable error when a protected operation is
    // attempted.
    await auth.authStateChanges().first.timeout(const Duration(seconds: 8));
  } on TimeoutException catch (error) {
    if (kDebugMode) {
      debugPrint(
        '⚠️ [AUTH] Session restore timed out; continuing to app shell: $error',
      );
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.mobileInitialization});

  final Future<void> Function()? mobileInitialization;

  @override
  Widget build(BuildContext context) {
    final platformRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final initialRoute = kIsWeb
        ? _webInitialRoute ??
              WebRoutes.startupOverride(platformRoute) ??
              platformRoute
        : null;

    return GetMaterialApp(
      title: 'AI-DSUHIS',
      // Sourced from the shared AppColors/AppTheme and the mobile AppDesign
      // system so both platform shells use the same clinical blue, navy,
      // typography, card, button, and input defaults.
      theme: kIsWeb ? AppTheme.light(isWeb: true) : app_theme.AppDesign.theme(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      builder: kIsWeb
          ? (context, child) => Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                const AppUpdateNotification(),
              ],
            )
          : null,
      defaultTransition: kIsWeb ? Transition.fadeIn : null,
      customTransition: kIsWeb ? WebPageTransition() : null,
      transitionDuration: kIsWeb ? const Duration(milliseconds: 180) : null,
      // Keep the public landing page at the root while preserving the former
      // /aidsuhis alias and direct deep links such as /login and /bhw/dashboard.
      initialRoute: initialRoute,
      // Platform-specific routing: modularized into WebPages and MobilePages
      getPages: kIsWeb ? WebPages.pages : MobilePages.pages,
      home: kIsWeb
          ? null
          : MobileStartupGate(
              initialize: mobileInitialization ?? () async {},
              child: const MobileSessionGate(),
            ),
      unknownRoute: kIsWeb ? WebPages.unknownRoute : null,
    );
  }
}

Future<void> _initDynamicLinks() async {
  // Only initialize dynamic links on non-web platforms
  if (kIsWeb) return;
  try {
    final dynamicLinks = getFirebaseDynamicLinks();
    // Fetching the launch link is a one-time startup operation. Some platform
    // implementations can leave it pending when the device service is
    // unavailable, so never let it hold the startup gate indefinitely.
    final initialLink = dynamicLinks == null
        ? null
        : await dynamicLinks.getInitialLink().timeout(
            const Duration(seconds: 8),
          );
    if (initialLink?.link != null) {
      // Handle the deep link, e.g., parse parameters and navigate
      debugPrint('Dynamic Link (initial): ${initialLink!.link}');
    }

    dynamicLinks?.onLink
        .listen((dynamicLinkData) {
          final Uri deepLink = dynamicLinkData.link;
          debugPrint('Dynamic Link (onLink): $deepLink');
        })
        .onError((error) {
          debugPrint('Dynamic Link error: $error');
        });
  } catch (e) {
    debugPrint('Error initializing dynamic links: $e');
  }
}

// Platform-aware stub for getFirebaseDynamicLinks
dynamic getFirebaseDynamicLinks() {
  if (kIsWeb) return null;
  // On non-web platforms, FirebaseDynamicLinks is available via conditional import above
  try {
    return FirebaseDynamicLinks.instance;
  } catch (_) {
    return null;
  }
}
