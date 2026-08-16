import 'dart:async';

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
class MobileSessionGate extends StatefulWidget {
  const MobileSessionGate({super.key});

  @override
  State<MobileSessionGate> createState() => _MobileSessionGateState();
}

class _MobileSessionGateState extends State<MobileSessionGate> {
  late Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = _createAuthStream();
  }

  Stream<User?> _createAuthStream() {
    return FirebaseAuth.instance.authStateChanges().timeout(
      const Duration(seconds: 8),
      onTimeout: (sink) {
        sink.addError(
          TimeoutException('Firebase session restoration timed out'),
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _authStream = _createAuthStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SessionRestoreError(onRetry: _retry);
        }
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

class _SessionRestoreError extends StatelessWidget {
  const _SessionRestoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.page,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppDesign.blue,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Session could not be restored',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your connection and try again. Your local records remain on this device.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
