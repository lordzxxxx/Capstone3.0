import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_bootstrap.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/firebase_app_check_bootstrap.dart';
// Use local stub for firebase_dynamic_links so the project builds
// without the actual package installed. Replace with real package
// import when adding `firebase_dynamic_links` to `pubspec.yaml`.
import 'firebase_dynamic_links_stub.dart';

// Import app and web versions
import 'package:mycapstone_project/app/shell/landing.dart' as app;
import 'package:mycapstone_project/app/shell/mobile_startup.dart';
import 'package:mycapstone_project/app/features/auth/login.dart' as app_login;
import 'package:mycapstone_project/app/features/auth/signup.dart' as app_signup;
import 'package:mycapstone_project/app/features/analytics/analytics.dart'
    as app_analytics;
import 'package:mycapstone_project/app/features/referrals/referrals.dart'
    as app_referrals;
import 'package:mycapstone_project/app/theme/app_theme.dart' as app_theme;
import 'package:mycapstone_project/web/features/auth/landing.dart' as web;
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart'
    as web_communicable;
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart'
    as web_noncommunicable;
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart'
    as web_referrals;
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as web_checkup;
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart'
    as web_prenatal;
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart'
    as web_morbidity;
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart'
    as web_mortality;
import 'package:mycapstone_project/web/shared/utils/auth_guard_middleware.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Mount the Flutter shell immediately. Network services are initialized
    // after the first frame so a blocked Firebase/App Check request can never
    // leave users looking at a blank white canvas.
    runApp(const MyApp());
    unawaited(_initializeWebServices());
    return;
  }

  // Start the branded mobile shell immediately. Firebase and offline sync are
  // completed behind the startup gate so the native splash transitions into a
  // clean, animated AI-DSUHIS loading screen instead of a blank window.
  runApp(MyApp(mobileInitialization: _initializeMobileServices));
}

Future<void> _initializeMobileServices() async {
  // Mobile platforms use google-services.json/GoogleService-Info.plist.
  await Firebase.initializeApp();
  try {
    await activateFirebaseAppCheck();
  } catch (e) {
    if (!kDebugMode) rethrow;
    print('⚠️ [APP_CHECK] Could not initialize App Check on mobile: $e');
  }
  // Initialize dynamic links on mobile so password reset and other action
  // links can be handled in-app.
  await _initDynamicLinks();
  await initializeMobileOfflineSync();
}

Future<void> _initializeWebServices() async {
  try {
    print('🔵 [FIREBASE] Initializing Firebase for web...');
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
    );
    print('✅ [FIREBASE] Firebase initialized');
  } catch (e) {
    print('❌ [FIREBASE] Initialization failed: $e');
    return;
  }

  try {
    await activateFirebaseAppCheck();
  } catch (e) {
    print('⚠️ [APP_CHECK] Web activation skipped: $e');
  }

  try {
    final firestore = getFirestoreInstance();
    firestore.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
      webExperimentalAutoDetectLongPolling: false,
    );
    await firestore.enableNetwork().timeout(const Duration(seconds: 6));
    print('✅ [FIRESTORE] Ready for operations');
  } catch (e) {
    print('⚠️ [FIRESTORE] Configuration deferred: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.mobileInitialization});

  final Future<void> Function()? mobileInitialization;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AI-DSUHIS',
      // Sourced from the shared AppColors/AppTheme (lib/web/shared/theme/
      // app_theme.dart) so the app follows the same canonical teal branding
      // (0xFF00A8B5) already used across lib/web/*, instead of the one-off
      // 0xFF8ED7DA that only this file previously used.
      theme: kIsWeb ? AppTheme.light(isWeb: true) : app_theme.AppDesign.theme(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      // Platform-specific routing
      getPages: kIsWeb
          ? [
              GetPage(name: '/', page: () => const web.LandingPage()),
              GetPage(
                name: '/CommunicablePage',
                page: () => const web_communicable.CommunicablePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/NonCommunicablePage',
                page: () => const web_noncommunicable.NonCommunicablePage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/ReferralsPage',
                page: () => const web_referrals.BhwReferralPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/checkups',
                page: () => const web_checkup.CheckUpPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/prenatal',
                page: () => const web_prenatal.PrenatalPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/morbidity',
                page: () => const web_morbidity.MorbidityPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/mortality',
                page: () => const web_mortality.MortalityPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
            ]
          : [
              GetPage(name: '/', page: () => const app.LandingPage()),
              GetPage(name: '/Login', page: () => const app_login.Login()),
              GetPage(name: '/Signup', page: () => const app_signup.Signup()),
              GetPage(
                name: '/AnalyticsPage',
                page: () => const app_analytics.AnalyticsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
              GetPage(
                name: '/ReferralsPage',
                page: () => const app_referrals.ReferralsPage(),
                middlewares: [AuthGuardMiddleware()],
              ),
            ],
      home: kIsWeb
          ? const web.LandingPage()
          : MobileStartupGate(
              initialize: mobileInitialization ?? () async {},
              child: const app.LandingPage(),
            ),
    );
  }
}

Future<void> _initDynamicLinks() async {
  // Only initialize dynamic links on non-web platforms
  if (kIsWeb) return;
  try {
    final dynamicLinks = getFirebaseDynamicLinks();
    final initialLink = await dynamicLinks?.getInitialLink();
    if (initialLink?.link != null) {
      // Handle the deep link, e.g., parse parameters and navigate
      // ignore: avoid_print
      print('Dynamic Link (initial): ${initialLink!.link}');
    }

    dynamicLinks?.onLink
        .listen((dynamicLinkData) {
          final Uri deepLink = dynamicLinkData.link;
          // Handle the deep link - navigate to reset screen or handle code
          // ignore: avoid_print
          print('Dynamic Link (onLink): $deepLink');
        })
        .onError((error) {
          // ignore: avoid_print
          print('Dynamic Link error: $error');
        });
  } catch (e) {
    // ignore: avoid_print
    print('Error initializing dynamic links: $e');
  }
}

// Platform-aware stub for getFirebaseDynamicLinks
dynamic getFirebaseDynamicLinks() {
  if (kIsWeb) return null;
  // On non-web platforms, FirebaseDynamicLinks is available via conditional import above
  // Use try-catch to avoid undefined name error if not available
  try {
    // ignore: undefined_identifier
    return FirebaseDynamicLinks.instance;
  } catch (_) {
    return null;
  }
}
