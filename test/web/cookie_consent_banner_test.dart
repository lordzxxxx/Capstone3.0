import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/widgets/cookie_consent_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the notice and persists agreement', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(children: [CookieConsentBanner()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cookies and browser storage'), findsOneWidget);
    expect(find.byKey(const ValueKey('cookie-consent-agree')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cookie-consent-agree')));
    await tester.pumpAndSettle();

    expect(find.text('Cookies and browser storage'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(CookieConsentBanner.preferenceKey),
      isTrue,
    );
  });

  testWidgets('does not show after a previous agreement', (tester) async {
    SharedPreferences.setMockInitialValues({
      CookieConsentBanner.preferenceKey: true,
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(children: [CookieConsentBanner()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cookies and browser storage'), findsNothing);
  });
}
