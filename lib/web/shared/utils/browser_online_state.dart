import 'dart:async';

import 'browser_online_state_stub.dart'
    if (dart.library.js_interop) 'browser_online_state_web.dart'
    as implementation;

/// Browser-level online state when available; `null` on native platforms.
bool? browserIsOnline() => implementation.browserIsOnline();

Stream<bool> browserOnlineChanges() => implementation.browserOnlineChanges();
