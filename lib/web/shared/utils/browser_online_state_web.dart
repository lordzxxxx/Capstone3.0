import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool browserIsOnline() => web.window.navigator.onLine;

Stream<bool> browserOnlineChanges() {
  late final StreamController<bool> controller;
  JSFunction? onlineListener;
  JSFunction? offlineListener;

  controller = StreamController<bool>.broadcast(
    onListen: () {
      onlineListener = ((web.Event _) => controller.add(true)).toJS;
      offlineListener = ((web.Event _) => controller.add(false)).toJS;
      web.window.addEventListener('online', onlineListener);
      web.window.addEventListener('offline', offlineListener);
    },
    onCancel: () {
      final online = onlineListener;
      final offline = offlineListener;
      if (online != null) web.window.removeEventListener('online', online);
      if (offline != null) web.window.removeEventListener('offline', offline);
    },
  );
  return controller.stream;
}
