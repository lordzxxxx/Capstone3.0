import 'package:web/web.dart' as web;

/// Same-origin path for the Android artifact shipped with the web build.
/// Override this with --dart-define=BHW_APK_URL=... when the APK is hosted
/// outside the Vercel deployment.
const String bhwApkDownloadUrl = String.fromEnvironment(
  'BHW_APK_URL',
  defaultValue: '/downloads/ai-dsuhis-bhw.apk',
);

bool get hasBhwApkDownload => bhwApkDownloadUrl.trim().isNotEmpty;

void downloadBhwApk() {
  if (!hasBhwApkDownload) return;

  final anchor = web.HTMLAnchorElement()
    ..href = bhwApkDownloadUrl
    ..download = 'ai-dsuhis-bhw.apk'
    ..rel = 'noopener';
  anchor.click();
}
