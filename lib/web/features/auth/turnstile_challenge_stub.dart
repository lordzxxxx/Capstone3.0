import 'package:flutter/widgets.dart';

class TurnstileChallenge extends StatelessWidget {
  const TurnstileChallenge({
    super.key,
    required this.action,
    required this.onTokenChanged,
    this.resetNonce = 0,
  });

  final String action;
  final ValueChanged<String?> onTokenChanged;
  final int resetNonce;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
