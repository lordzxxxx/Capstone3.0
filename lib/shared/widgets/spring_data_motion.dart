import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// A restrained spring transition for data-driven surfaces.
///
/// The widget does not own or reload data. It only reacts when [dataKey]
/// changes, which keeps Firestore/local-sync behavior in the existing parent
/// widgets while making updates easier to follow visually.
class SpringDataMotion extends StatefulWidget {
  const SpringDataMotion({
    super.key,
    required this.child,
    this.dataKey,
    this.animateOnMount = true,
  });

  final Widget child;
  final Object? dataKey;
  final bool animateOnMount;

  @override
  State<SpringDataMotion> createState() => _SpringDataMotionState();
}

class _SpringDataMotionState extends State<SpringDataMotion>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 360,
    damping: 30,
  );

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 1);
    if (widget.animateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(covariant SpringDataMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataKey != widget.dataKey) {
      _play();
    }
  }

  void _play() {
    if (!mounted) return;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = 1;
      return;
    }

    _controller.stop();
    _controller.value = 0;
    _controller.animateWith(SpringSimulation(_spring, 0, 1, 0));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    final scale = Tween<double>(begin: 0.992, end: 1).animate(_controller);
    final opacity = Tween<double>(begin: 0.9, end: 1).animate(_controller);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: opacity.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale.value.clamp(0.98, 1.02),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Stable keys for chart/table data that is reconstructed during build.
abstract final class SpringDataKey {
  static String entries(Iterable<MapEntry<Object?, Object?>> values) {
    return values.map((entry) => '${entry.key}:${entry.value}').join('|');
  }
}
