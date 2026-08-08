import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/features/auth/signup.dart';
import 'package:mycapstone_project/web/features/auth/bhw_registration.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _primaryAquaBright = Color(0xFF29C7D1);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = Color(0xFF0E2F34);
const Color _panelSurface = Color(0xFF061920);

// Plus Jakarta Sans is already the established typeface for the auth flow
// (login.dart, signup.dart, bhw_registration.dart) — applied here too so the
// landing page matches instead of falling back to the platform default font.
TextStyle _display({
  required double size,
  FontWeight weight = FontWeight.w800,
  Color color = _lightOffWhite,
  double? letterSpacing,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: 1.1,
);

TextStyle _body({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color color = _lightOffWhite,
  double? height,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

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
    precacheImage(const AssetImage('assets/newlogo.png'), context);
    precacheImage(const AssetImage('assets/newsystembg_web.webp'), context);
    _didPrecacheLogo = true;
  }

  Future<String?> _showRoleSelectionDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Register As', style: _display(size: 20)),
        content: Text(
          'Choose your account type. BHW requests require City Health Office approval. Administrator accounts are not available through public registration.',
          style: _body(size: 14, color: _lightOffWhite.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: _body(
                size: 14,
                weight: FontWeight.w600,
                color: _lightOffWhite.withValues(alpha: 0.8),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('CHO'),
            style: FilledButton.styleFrom(
              backgroundColor: _panelSurface,
              foregroundColor: _lightOffWhite,
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

  Widget _buildSystemLogo({required double size, BoxFit fit = BoxFit.contain}) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
      ]),
      child: Image.asset(
        'assets/newlogo.png',
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.health_and_safety_rounded,
          color: _primaryAqua,
          size: size * 0.65,
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
          // Hero background image (never stretched/distorted — BoxFit.cover
          // crops to fill while preserving aspect ratio). Falls back to the
          // original flat gradient if the asset ever fails to load.
          Positioned.fill(
            child: Image.asset(
              'assets/newsystembg_web.webp',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_darkDeepTeal, _darkDeepTeal, _sidebarDark],
                    ),
                  ),
                );
              },
            ),
          ),
          // Dark-teal scrim over the photo, at partial opacity, so the hero
          // text/CTA panels stay readable while the image remains visible.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.backgroundDark.withValues(alpha: 0.55),
                    AppColors.backgroundDark.withValues(alpha: 0.68),
                    AppColors.surfaceDark.withValues(alpha: 0.82),
                  ],
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
          // The landing route is deliberately a constrained application
          // surface.  It owns its viewport and never participates in the
          // document's scrollable flow (other routes keep their normal
          // scrolling behaviour).
          SafeArea(
            child: ClipRect(
              child: SizedBox.expand(
                child: AnimatedSwitcher(
                  // Only fade the loader/content state.  The hero itself is
                  // not translated or scaled during/after a resize.
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: _showIntroLoader
                      ? _buildLandingLoader()
                      : _buildLandingContent(context),
                ),
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
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
            decoration: BoxDecoration(
              color: _sidebarDark,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.26),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
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
                  child: ClipOval(child: _buildSystemLogo(size: 84)),
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
                Text(
                  'Preparing AI-DSUHIS',
                  style: _display(size: 22, letterSpacing: 0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'Loading your healthcare portal',
                  style: _body(
                    size: 14,
                    color: _lightOffWhite.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandingContent(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('landing_content'),
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final isDesktop = constraints.maxWidth >= 980;
        final logoSize = isDesktop
            ? _responsive(height, 0.16, 108, 178)
            : _responsive(height, 0.13, 88, 138);
        final titleSize = isDesktop
            ? _responsive(height, 0.066, 42, 72)
            : _responsive(height, 0.050, 32, 48);
        final subtitleSize = isDesktop
            ? _responsive(height, 0.022, 16, 23)
            : _responsive(height, 0.019, 14, 19);
        final contentPadding = isDesktop
            ? EdgeInsets.symmetric(
                horizontal: _responsive(constraints.maxWidth, 0.025, 22, 48),
                vertical: _responsive(height, 0.014, 10, 18),
              )
            : EdgeInsets.symmetric(
                horizontal: _responsive(constraints.maxWidth, 0.045, 14, 24),
                vertical: _responsive(height, 0.012, 10, 16),
              );

        final hero = _buildHeroPanel(
          logoSize: logoSize,
          titleSize: titleSize,
          subtitleSize: subtitleSize,
          contentPadding: contentPadding,
          isDesktop: isDesktop,
        );

        if (isDesktop) {
          // One stable parent alignment system for both columns.  Neither
          // side is independently offset, translated, or content-scaled.
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: SizedBox(
                width: constraints.maxWidth.clamp(0.0, 1440.0).toDouble(),
                height: constraints.maxHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: hero),
                    Expanded(
                      flex: 8,
                      child: Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: _buildAccessPanel(context, compact: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Tablet/mobile switches intentionally at a meaningful width.  The
        // landing route still owns the viewport and does not add a scroll
        // view; dimensions above are chosen from the available height.
        return Center(
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: hero),
                SizedBox(height: _responsive(height, 0.018, 10, 18)),
                Flexible(child: _buildAccessPanel(context, compact: true)),
              ],
            ),
          ),
        );
      },
    );
  }

  double _responsive(double basis, double fraction, double min, double max) {
    return (basis * fraction).clamp(min, max).toDouble();
  }

  Widget _buildHeroPanel({
    required double logoSize,
    required double titleSize,
    required double subtitleSize,
    required EdgeInsets contentPadding,
    required bool isDesktop,
  }) {
    final partnerLogoSize = _responsive(logoSize, 0.48, 52, 86);

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
          child: _buildSystemLogo(size: logoSize),
        ),
        SizedBox(height: _responsive(logoSize, 0.14, 10, 20)),
        _buildPartnerLogos(partnerLogoSize),
        SizedBox(height: _responsive(logoSize, 0.16, 12, 22)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_lightOffWhite, _primaryAquaBright],
          ).createShader(bounds),
          child: Text(
            'AI-DSUHIS',
            style: _display(size: titleSize, letterSpacing: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: _responsive(titleSize, 0.24, 8, 16)),
        Text(
          'AI-Driven Solution For Unified Health Information System',
          style: _body(
            size: subtitleSize,
            weight: FontWeight.w400,
            color: _lightOffWhite.withValues(alpha: 0.78),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: _responsive(subtitleSize, 0.9, 12, 24)),
        _buildFeatureGrid(desktop: isDesktop, compact: logoSize < 150),
      ],
    );
    return Padding(
      padding: contentPadding,
      child: Center(child: heroContent),
    );
  }

  Widget _buildPartnerLogos(double size) {
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPartnerLogoItem('assets/logo2.png', size),
          SizedBox(width: _responsive(size, 0.16, 8, 14)),
          _buildPartnerLogoItem('assets/logo3.png', size),
        ],
      ),
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
        padding: EdgeInsets.all(compact ? 26 : 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _sidebarDark,
              _sidebarDark.withValues(alpha: 0.96),
              _panelSurface,
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: _primaryAqua.withValues(alpha: 0.10),
              blurRadius: 70,
              offset: const Offset(0, 32),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryAquaBright, _primaryAqua],
                ),
              ),
              child: const Icon(
                Icons.shield_moon_outlined,
                color: _darkDeepTeal,
                size: 26,
              ),
            ),
            SizedBox(height: compact ? 18 : 22),
            Text(
              'Welcome Back',
              style: _display(size: compact ? 30 : 38, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to your healthcare portal.',
              style: _body(
                size: 14.5,
                weight: FontWeight.w500,
                color: _lightOffWhite.withValues(alpha: 0.62),
              ),
            ),
            SizedBox(height: compact ? 28 : 36),
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
              style: _body(
                size: 13,
                weight: FontWeight.w500,
                color: _mutedCoolGray.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid({required bool desktop, required bool compact}) {
    final gap = compact ? 8.0 : 12.0;
    final features = <(IconData, String)>[
      (Icons.health_and_safety_rounded, 'Health Monitoring'),
      (Icons.analytics_rounded, 'Advanced Analytics'),
      (Icons.security_rounded, 'Secure & Private'),
      (Icons.cloud_sync_rounded, 'Cloud Sync'),
    ];

    Widget cell((IconData, String) feature) {
      return _buildFeatureBadge(
        feature.$1,
        feature.$2,
        compact: compact,
        stretch: true,
      );
    }

    if (desktop) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: cell(features[0])),
              SizedBox(width: gap),
              Expanded(child: cell(features[1])),
              SizedBox(width: gap),
              Expanded(child: cell(features[2])),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(width: gap),
              Expanded(child: cell(features[3])),
              SizedBox(width: gap),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      );
    }

    // Mobile/tablet uses a deliberate 2 × 2 grid rather than implicit wrap.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: cell(features[0])),
            SizedBox(width: gap),
            Expanded(child: cell(features[1])),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(child: cell(features[2])),
            SizedBox(width: gap),
            Expanded(child: cell(features[3])),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureBadge(
    IconData icon,
    String label, {
    required bool compact,
    bool stretch = false,
  }) {
    final iconSize = compact ? 28.0 : 34.0;
    final textSize = compact ? 11.5 : 13.5;
    final badge = Container(
      height: compact ? 44 : 52,
      width: stretch ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: stretch
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryAquaBright.withValues(alpha: 0.9),
                  _primaryAqua.withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Icon(icon, color: _darkDeepTeal, size: compact ? 15 : 18),
          ),
          SizedBox(width: compact ? 7 : 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: _body(size: textSize, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return stretch ? SizedBox(width: double.infinity, child: badge) : badge;
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPrimary
                ? Colors.black.withValues(alpha: 0.12)
                : _primaryAqua.withValues(alpha: 0.14),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isPrimary ? _darkDeepTeal : _primaryAquaBright,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: _body(
            size: 16,
            weight: FontWeight.w700,
            color: isPrimary ? _darkDeepTeal : _lightOffWhite,
          ),
        ),
      ],
    );

    if (isPrimary) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_primaryAquaBright, _primaryAqua],
          ),
          boxShadow: [
            BoxShadow(
              color: _primaryAqua.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      );
    }

    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.07),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          hoverColor: _primaryAqua.withValues(alpha: 0.10),
          child: Center(child: child),
        ),
      ),
    );
  }
}
