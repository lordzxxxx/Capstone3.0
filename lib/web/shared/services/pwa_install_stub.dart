import 'package:flutter/foundation.dart';

/// No-op implementation used by the mobile/desktop Flutter targets.
///
/// The install prompt is a browser capability and must not be initialized
/// while the native app is running.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._();

  static final PwaInstallService instance = PwaInstallService._();

  bool get isInstalled => false;
  bool get canPrompt => false;
  bool get shouldShowAction => false;

  Future<bool> promptInstall() async => false;
}
