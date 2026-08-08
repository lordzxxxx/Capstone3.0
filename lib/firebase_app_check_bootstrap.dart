import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

const String _webAppCheckSiteKey = String.fromEnvironment(
  'FIREBASE_APP_CHECK_WEB_KEY',
);

/// Activates attestation for Firebase and for tokens sent to the private API.
Future<void> activateFirebaseAppCheck() async {
  if (kIsWeb) {
    if (_webAppCheckSiteKey.trim().isEmpty) {
      if (kReleaseMode) {
        throw StateError(
          'FIREBASE_APP_CHECK_WEB_KEY is required for release web builds.',
        );
      }
      debugPrint(
        '[APP_CHECK] Web App Check is disabled. Pass '
        '--dart-define=FIREBASE_APP_CHECK_WEB_KEY=<site-key>.',
      );
      return;
    }
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(_webAppCheckSiteKey.trim()),
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}
