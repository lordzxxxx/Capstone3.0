import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Prevents Firebase-backed routes from being built before Firebase Web has
/// finished initializing.
///
/// FlutterFire's web adapters cross a JavaScript interop boundary. If a page
/// starts a Firestore/Auth operation during that initialization window, a
/// Dart FirebaseException can be handed to the adapter where it expects a
/// JavaScript error object. The resulting cast message hides the real cause
/// and renders Flutter's red error screen. Keeping the app shell behind this
/// gate makes initialization ordering deterministic and gives failures a
/// recoverable UI instead.
class WebStartupGate extends StatefulWidget {
  const WebStartupGate({
    super.key,
    required this.initialize,
    required this.child,
  });

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<WebStartupGate> createState() => _WebStartupGateState();
}

class _WebStartupGateState extends State<WebStartupGate> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = widget.initialize();
  }

  void _retry() {
    setState(() {
      _initialization = widget.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // This gate is mounted before MyApp/MaterialApp. Keep the entire startup
    // tree direction-aware so loading and failure text never depends on an
    // inherited Directionality that does not exist yet.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _WebStartupError(onRetry: _retry);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _WebStartupLoading();
          }
          return widget.child;
        },
      ),
    );
  }
}

class _WebStartupLoading extends StatelessWidget {
  const _WebStartupLoading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundDark,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/newlogo_white.png',
              width: 92,
              height: 92,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Preparing your AI-DSUHIS workspace…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textOnDarkMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WebStartupError extends StatelessWidget {
  const _WebStartupError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: AppColors.warning,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Workspace could not be prepared',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check your connection and try again. No page was opened before the secure Firebase connection was ready.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
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
      ),
    );
  }
}
