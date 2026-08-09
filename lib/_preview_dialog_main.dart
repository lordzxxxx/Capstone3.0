import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/widgets/login_success_sweet_alert.dart';

void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0A1F24),
        body: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showLoginSuccessSweetAlert(
                context: context,
                title: 'Login successful',
                message: 'Your account is verified. Continue to the dashboard.',
                confirmButtonText: 'Open Dashboard',
              );
            });
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }
}
