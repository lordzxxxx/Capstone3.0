import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/features/auth/signup.dart';
import 'package:mycapstone_project/web/features/auth/bhw_registration.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = Color(0xFF0E2F34);
const Color _panelSurface = Color(0xFF061920);

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  static bool _hasShownIntroLoader = false;

  bool _showIntroLoader = !_hasShownIntroLoader;
  bool _didPrecacheLogo = false;

  @override
  void initState() {
    super.initState();
    if (_showIntroLoader) {
      Future<void>.delayed(const Duration(milliseconds: 1150), () {
        if (!mounted) return;
        setState(() => _showIntroLoader = false);
        _hasShownIntroLoader = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheLogo) return;
    precacheImage(const AssetImage('assets/bg3.png'), context);
    _didPrecacheLogo = true;
  }

  Future<String?> _showRoleSelectionDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _primaryAqua.withValues(alpha: 0.18)),
        ),
        title: const Text(
          'Register As',
          style: TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Choose your account type. BHW requests require City Health Office approval. Administrator accounts are not available through public registration.',
          style: TextStyle(color: _lightOffWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.8)),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('CHO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _lightOffWhite,
              backgroundColor: _panelSurface,
              side: const BorderSide(color: _primaryAqua, width: 1.5),
            ),
            child: const Text('City Health Office (CHO)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('BHW'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryAqua,
              foregroundColor: _darkDeepTeal,
            ),
            child: const Text('Barangay Health Worker (BHW)'),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropOrb({required double size, required Color color}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_darkDeepTeal, _darkDeepTeal, _sidebarDark],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -100,
            child: _buildBackdropOrb(
              size: 340,
              color: _primaryAqua.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            top: size.height * 0.10,
            right: size.width * 0.16,
            child: _buildBackdropOrb(
              size: 220,
              color: _secondaryIceBlue.withValues(alpha: 0.14),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -120,
            child: _buildBackdropOrb(
              size: 360,
              color: _sidebarDark.withValues(alpha: 0.82),
            ),
          ),
          SafeArea(
            child: SizedBox.expand(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 620),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: _showIntroLoader
                    ? _buildLandingLoader()
                    : _buildLandingContent(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandingLoader() {
    return Center(
      key: const ValueKey('landing_loader'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
          decoration: BoxDecoration(
            color: _sidebarDark,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.18),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_panelSurface, _sidebarDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/bg3.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.medical_services_rounded,
                        size: 64,
                        color: _primaryAqua,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  valueColor: AlwaysStoppedAnimation<Color>(_primaryAqua),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Preparing AI-DSUHIS',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading your healthcare portal',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.72),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandingContent(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('landing_content'),
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 1100;

        if (isWideScreen) {
          return Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 36, 18, 36),
                  child: _buildHeroPanel(
                    logoSize: 200,
                    titleSize: 72,
                    subtitleSize: 24,
                    contentPadding: const EdgeInsets.all(60),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 36, 36, 36),
                  child: Center(
                    child: SingleChildScrollView(
                      child: _buildAccessPanel(context, compact: false),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            children: [
              _buildHeroPanel(
                logoSize: 160,
                titleSize: 44,
                subtitleSize: 18,
                contentPadding: const EdgeInsets.all(28),
              ),
              const SizedBox(height: 20),
              _buildAccessPanel(context, compact: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroPanel({
    required double logoSize,
    required double titleSize,
    required double subtitleSize,
    required EdgeInsets contentPadding,
  }) {
    final partnerLogoSize = logoSize >= 200 ? 98.0 : 78.0;

    final heroContent = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryAqua.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/bg3.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.medical_services_rounded,
                  size: 100,
                  color: _primaryAqua,
                );
              },
            ),
          ),
        ),
        SizedBox(height: logoSize >= 200 ? 28 : 20),
        _buildPartnerLogos(partnerLogoSize),
        SizedBox(height: logoSize >= 200 ? 34 : 24),
        Text(
          'AI-DSUHIS',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            color: _lightOffWhite,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text(
          'AI-Driven Solution For Unified Health Information System',
          style: TextStyle(
            fontSize: subtitleSize,
            color: _lightOffWhite.withValues(alpha: 0.82),
            fontWeight: FontWeight.w300,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            _buildFeatureBadge(
              Icons.health_and_safety_rounded,
              'Health Monitoring',
            ),
            _buildFeatureBadge(Icons.analytics_rounded, 'Advanced Analytics'),
            _buildFeatureBadge(Icons.security_rounded, 'Secure & Private'),
            _buildFeatureBadge(Icons.cloud_sync_rounded, 'Cloud Sync'),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final availableHeight = hasBoundedHeight
            ? (constraints.maxHeight - contentPadding.vertical).clamp(
                0.0,
                double.infinity,
              )
            : 0.0;

        final content = hasBoundedHeight
            ? Positioned.fill(
                child: Padding(
                  padding: contentPadding,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: availableHeight),
                      child: Center(child: heroContent),
                    ),
                  ),
                ),
              )
            : Center(
                child: Padding(padding: contentPadding, child: heroContent),
              );

        return Stack(
          children: [
            Positioned(
              top: -90,
              left: -90,
              child: _buildBackdropOrb(
                size: 260,
                color: _primaryAqua.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              bottom: -70,
              right: -60,
              child: _buildBackdropOrb(
                size: 220,
                color: _secondaryIceBlue.withValues(alpha: 0.12),
              ),
            ),
            content,
          ],
        );
      },
    );
  }

  Widget _buildPartnerLogos(double size) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _buildPartnerLogoItem('assets/logo2.png', size),
        _buildPartnerLogoItem('assets/logo3.png', size),
      ],
    );
  }

  Widget _buildPartnerLogoItem(String assetPath, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.image_not_supported_outlined,
            color: _primaryAqua,
            size: size * 0.55,
          );
        },
      ),
    );
  }

  Widget _buildAccessPanel(BuildContext context, {required bool compact}) {
    return Container(
      constraints: compact ? null : const BoxConstraints(maxWidth: 500),
      padding: EdgeInsets.all(compact ? 0 : 40),
      child: Container(
        padding: EdgeInsets.all(compact ? 28 : 40),
        decoration: BoxDecoration(
          color: _sidebarDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome Back',
              style: TextStyle(
                fontSize: compact ? 32 : 42,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: compact ? 32 : 48),
            _buildActionButton(
              context: context,
              label: 'Login as BHW',
              icon: Icons.login_rounded,
              isPrimary: true,
              onPressed: () {
                replaceWithAuthPage(context, const Login());
              },
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              context: context,
              label: 'Login as CHO',
              icon: Icons.health_and_safety,
              isPrimary: false,
              onPressed: () {
                replaceWithAuthPage(context, const Login());
              },
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              context: context,
              label: 'Create Account',
              icon: Icons.person_add_alt_1_rounded,
              isPrimary: false,
              onPressed: () async {
                final selectedRole = await _showRoleSelectionDialog(context);
                if (selectedRole == null || !context.mounted) return;
                replaceWithAuthPage(
                  context,
                  selectedRole == 'BHW'
                      ? const BhwRegistrationPage()
                      : Signup(preselectedRole: selectedRole),
                );
              },
            ),
            SizedBox(height: compact ? 28 : 40),
            Text(
              '(c) 2026 AI-DSUHIS. All rights reserved.',
              style: TextStyle(
                fontSize: 14,
                color: _mutedCoolGray.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryAqua, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 65,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: _primaryAqua.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: isPrimary
          ? ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 24),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryAqua,
                foregroundColor: _darkDeepTeal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 24),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _lightOffWhite,
                backgroundColor: _panelSurface,
                side: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.85),
                  width: 1.6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
    );
  }
}
