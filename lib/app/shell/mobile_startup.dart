import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Branded mobile bootstrap gate. The reveal is deliberately independent from
/// service initialization: a fast device never waits for the secondary loader,
/// while a slower device gets clear feedback after the reveal completes.
class MobileStartupGate extends StatefulWidget {
  const MobileStartupGate({
    super.key,
    required this.initialize,
    required this.child,
  });

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<MobileStartupGate> createState() => _MobileStartupGateState();
}

class _MobileStartupGateState extends State<MobileStartupGate>
    with SingleTickerProviderStateMixin {
  late Future<void> _initialization;
  late final AnimationController _revealController;
  bool _revealComplete = false;

  @override
  void initState() {
    super.initState();
    _revealController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 900),
          )
          ..addStatusListener(_handleRevealStatus)
          ..forward();
    _initialization = widget.initialize();
  }

  @override
  void dispose() {
    _revealController
      ..removeStatusListener(_handleRevealStatus)
      ..dispose();
    super.dispose();
  }

  void _handleRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _revealComplete = true);
    }
  }

  void _retry() {
    setState(() {
      _revealComplete = false;
      _initialization = widget.initialize();
    });
    _revealController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        final Widget content;
        final Key phaseKey;

        if (!_revealComplete) {
          content = _StartupReveal(animation: _revealController);
          phaseKey = const ValueKey('mobile-startup-reveal');
        } else if (snapshot.hasError) {
          content = _StartupError(onRetry: _retry, error: snapshot.error);
          phaseKey = const ValueKey('mobile-startup-error');
        } else if (snapshot.connectionState == ConnectionState.done) {
          content = widget.child;
          phaseKey = const ValueKey('mobile-startup-app');
        } else {
          content = const _StartupJsonLoading();
          phaseKey = const ValueKey('mobile-startup-json-loader');
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(key: phaseKey, child: content),
        );
      },
    );
  }
}

class _StartupReveal extends StatelessWidget {
  const _StartupReveal({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppDesign.navy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) =>
                  CustomPaint(painter: _WhiteRevealPainter(animation.value)),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Image.asset(
                'assets/newlogo_white.png',
                width: 116,
                height: 116,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteRevealPainter extends CustomPainter {
  const _WhiteRevealPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final cornerRadius = math.sqrt(
      math.pow(size.width / 2, 2) + math.pow(size.height / 2, 2),
    );
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
    final eased = Curves.easeOutCubic.transform(normalizedProgress);
    final radius = 2 + (cornerRadius * 1.04 - 2) * eased;

    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _WhiteRevealPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _StartupJsonLoading extends StatelessWidget {
  const _StartupJsonLoading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: Lottie.asset(
            'assets/loading.json',
            repeat: true,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry, this.error});

  final VoidCallback onRetry;
  final Object? error;

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
                  Image.asset(
                    'assets/ai_dsuhis_round.png',
                    width: 86,
                    height: 86,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'AI-DSUHIS could not finish loading',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your connection and try again. Your unrelated device features remain available.',
                    textAlign: TextAlign.center,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppDesign.subtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
