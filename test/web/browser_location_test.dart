@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/utils/browser_location.dart';

void main() {
  test('reads the initial path from the browser location', () {
    expect(browserLocationRoute(), startsWith('/'));
  });
}
