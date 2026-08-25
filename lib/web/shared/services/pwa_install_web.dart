import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// The browser exposes this event type even though it is not part of the
/// standard DOM typings bundled by package:web.
extension type _BeforeInstallPromptEvent._(JSObject _) implements web.Event {
  external JSPromise<JSAny?> prompt();
}

/// Owns the browser's deferred PWA install prompt.
///
/// The prompt is captured, but never opened automatically. Browsers require
/// the prompt to be triggered by a user gesture, so the BHW must tap the
/// visible install action.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._() {
    _installed = web.window.matchMedia('(display-mode: standalone)').matches;

    _beforeInstallListener = ((web.Event event) {
      event.preventDefault();
      _deferredPrompt = _BeforeInstallPromptEvent._(event);
      _canPrompt = true;
      notifyListeners();
    }).toJS;
    web.window.addEventListener('beforeinstallprompt', _beforeInstallListener);

    _installedListener = ((web.Event _) {
      _deferredPrompt = null;
      _canPrompt = false;
      _installed = true;
      notifyListeners();
    }).toJS;
    web.window.addEventListener('appinstalled', _installedListener);
  }

  static final PwaInstallService instance = PwaInstallService._();

  late final JSFunction _beforeInstallListener;
  late final JSFunction _installedListener;
  _BeforeInstallPromptEvent? _deferredPrompt;
  bool _canPrompt = false;
  bool _installed = false;

  bool get isInstalled => _installed;
  bool get canPrompt => _canPrompt && _deferredPrompt != null;

  /// Keep a visible fallback action for browsers such as iOS Safari where
  /// `beforeinstallprompt` is not implemented. The dialog explains the
  /// browser's Add to Home Screen path instead of pretending an install
  /// prompt exists.
  bool get shouldShowAction => !_installed;

  Future<bool> promptInstall() async {
    final prompt = _deferredPrompt;
    if (prompt == null) return false;

    await prompt.prompt().toDart;
    _deferredPrompt = null;
    _canPrompt = false;
    notifyListeners();
    return true;
  }
}
