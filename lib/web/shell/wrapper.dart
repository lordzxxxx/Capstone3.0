import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  late Future<User?> _initialAuthState;

  @override
  void initState() {
    super.initState();
    _initialAuthState = _restoreInitialAuthState();
  }

  Future<User?> _restoreInitialAuthState() {
    // The first event is bounded; the continuous auth stream is not.
    return FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 15),
    );
  }

  void _retryInitialAuthState() {
    setState(() {
      _initialAuthState = _restoreInitialAuthState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<User?>(
        future: _initialAuthState,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Authentication could not be restored.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _retryInitialAuthState,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            initialData: snapshot.data,
            builder: (context, authSnapshot) {
              if (authSnapshot.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: _retryInitialAuthState,
                    child: const Text('Retry authentication'),
                  ),
                );
              }
              final user = authSnapshot.data;
              return user != null ? HomePage(user: user) : const Login();
            },
          );
        },
      ),
    );
  }
}
