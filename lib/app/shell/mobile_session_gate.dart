import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/shell/landing.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Chooses the first mobile screen from the restored Firebase session.
///
/// This is deliberately separate from the startup gate: Firebase services
/// must be initialized before this widget is built, while Auth still needs
/// one initial stream event to tell us whether a local session exists.
class MobileSessionGate extends StatelessWidget {
  const MobileSessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SessionRestoreLoading();
        }

        final user = snapshot.data;
        if (user != null) {
          return HomePage(user: user);
        }
        return const LandingPage();
      },
    );
  }
}

class _SessionRestoreLoading extends StatelessWidget {
  const _SessionRestoreLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.page,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/ai_dsuhis_round.png',
              width: 72,
              height: 72,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppDesign.blue,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Restoring your session…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
