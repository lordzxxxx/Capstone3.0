import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/features/auth/signup.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/shared/widgets/privacy_notice_button.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Mobile entry screen that uses the same fixed two-part composition as the
/// web landing page: branded hero content and a clear authentication panel.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg2.2.png', fit: BoxFit.cover),
          Container(color: AppDesign.navy.withValues(alpha: 0.82)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final hero = _buildHero(context, compact: compact);
                final auth = _buildAuthPanel(context);
                if (compact) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      children: [hero, const SizedBox(height: 24), auth],
                    ),
                  );
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: hero),
                        const SizedBox(width: 36),
                        SizedBox(width: 360, child: auth),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, {required bool compact}) {
    final logoSize = compact ? 128.0 : 176.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: compact ? Alignment.center : Alignment.centerLeft,
          child: Image.asset(
            'assets/ai_dsuhis_round.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _partnerLogo('assets/logo1.png'),
            const SizedBox(width: 14),
            _partnerLogo('assets/logo2.png'),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'AI-DSUHIS',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            color: Colors.white,
            fontSize: compact ? 34 : 48,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'AI-Driven Solution For Unified Health Information System',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.86),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _FeatureChip(
              icon: Icons.favorite_outline,
              label: 'Health Monitoring',
            ),
            _FeatureChip(
              icon: Icons.analytics_outlined,
              label: 'Advanced Analytics',
            ),
            _FeatureChip(
              icon: Icons.shield_outlined,
              label: 'Secure & Private',
            ),
            _FeatureChip(icon: Icons.cloud_outlined, label: 'Cloud Sync'),
          ],
        ),
      ],
    );
  }

  Widget _buildAuthPanel(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to your healthcare portal.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Get.to(() => const Login()),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Login'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Get.to(() => const Signup()),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Get.offAll(
                  () => const HomePage(),
                  arguments: const {'offline': true},
                ),
                child: const Text('Continue offline'),
              ),
            ),
            const SizedBox(height: 4),
            const Center(child: PrivacyNoticeButton()),
          ],
        ),
      ),
    );
  }

  Widget _partnerLogo(String asset) {
    return Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppDesign.border),
      ),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
