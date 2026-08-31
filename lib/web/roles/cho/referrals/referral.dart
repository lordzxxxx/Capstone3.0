import 'package:flutter/material.dart';

import 'cho_referral_management.dart';

/// Compatibility wrapper for older imports. The active CHO referral workflow
/// lives in [CHOPreferralPage] and exposes monitoring plus admin reassignment.
class CHOReferralWorkspacePage extends StatelessWidget {
  const CHOReferralWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) => const CHOPreferralPage();
}
