import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shell/landing.dart' as mobile;
import 'package:mycapstone_project/web/features/auth/forgot.dart';
import 'package:mycapstone_project/web/features/auth/landing.dart' as web;
import 'package:mycapstone_project/web/features/auth/login.dart';

Future<void> _pumpAtSize(
  WidgetTester tester,
  Size size,
  Widget child, {
  Duration settleFor = const Duration(milliseconds: 100),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump(settleFor);
}

void main() {
  testWidgets('native landing remains overflow-free on a narrow phone', (
    tester,
  ) async {
    await _pumpAtSize(tester, const Size(320, 640), const mobile.LandingPage());

    expect(tester.takeException(), isNull);
  });

  testWidgets('web landing remains overflow-free on phone widths', (
    tester,
  ) async {
    for (final size in [const Size(409, 963), const Size(823, 1035)]) {
      await _pumpAtSize(tester, size, const web.LandingPage());
      expect(tester.takeException(), isNull);

      // Move past the intro loader so the real hero/auth composition is tested.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('web authentication pages remain scrollable on phone widths', (
    tester,
  ) async {
    for (final page in <Widget>[const Login(), const ForgotPassword()]) {
      await _pumpAtSize(
        tester,
        const Size(360, 640),
        page,
        settleFor: const Duration(milliseconds: 200),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
