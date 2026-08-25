@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/utils/browser_online_state.dart';
import 'package:web/web.dart' as web;

void main() {
  test('forwards browser offline and online events', () async {
    final values = <bool>[];
    final subscription = browserOnlineChanges().listen(values.add);

    web.window.dispatchEvent(web.Event('offline'));
    web.window.dispatchEvent(web.Event('online'));
    await pumpEventQueue();

    expect(values, <bool>[false, true]);
    await subscription.cancel();
  });
}
