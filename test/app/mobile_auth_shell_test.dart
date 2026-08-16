import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/features/auth/widgets/mobile_auth_shell.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  testWidgets('mobile auth shell mirrors the branded web auth hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: MobileAuthShell(
          pageTitle: 'Sign in',
          heading: 'Welcome back',
          description: 'Securely access the mobile workspace.',
          onBack: () {},
          child: const Text('Form content'),
        ),
      ),
    );

    expect(find.text('AI-DSUHIS'), findsOneWidget);
    expect(find.text('Secure access'), findsNothing);
    expect(find.text('Cloud sync'), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Form content'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
