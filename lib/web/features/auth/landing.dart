import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/features/auth/signup.dart';
import 'package:mycapstone_project/web/features/auth/bhw_registration.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';
import 'package:mycapstone_project/web/shared/widgets/liquid_glass_navbar.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';

const Color _primaryAqua = AppColors.primary;
const Color _primaryAquaBright = Color(0xFF4EA1FF);
const Color _secondaryIceBlue = AppColors.secondary;
// Clean solid navy used for the access panel's buttons — flatter and more
// restrained than the teal gradient, per request.
const Color _darkBlue = Color(0xFF123A5C);
const Color _darkDeepTeal = AppColors.backgroundDark;
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = AppColors.surfaceDark;
const Color _panelSurface = Color(0xFF0B1F3A);

// Manrope is the established typeface for the auth flow (login.dart,
// signup.dart, bhw_registration.dart) — applied here too so the landing
// page matches instead of falling back to the platform default font.
TextStyle _display({
  required double size,
  FontWeight weight = FontWeight.w800,
  Color color = _lightOffWhite,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'Manrope',
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
}) => TextStyle(
  fontFamily: 'Manrope',
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

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  static bool _hasShownIntroLoader = false;

  bool _showIntroLoader = !_hasShownIntroLoader;
  bool _didPrecacheLogo = false;
  final ScrollController _landingScrollController = ScrollController();

  // Slow, continuous "Ken Burns" breathing zoom on the backdrop photo.
  late final AnimationController _bgController;
  // One-shot staggered entrance for the hero branding and access panel.
  late final AnimationController _contentController;
  late final Animation<double> _heroEntrance;
  late final Animation<double> _panelEntrance;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _heroEntrance = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
    );
    _panelEntrance = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
    if (_showIntroLoader) {
      Future<void>.delayed(const Duration(milliseconds: 1150), () {
        if (!mounted) return;
        setState(() => _showIntroLoader = false);
        _hasShownIntroLoader = true;
        _contentController.forward();
      });
    } else {
      _contentController.forward();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    _landingScrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_landingScrollController.hasClients) return;
    _landingScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheLogo) return;
    precacheImage(const AssetImage('assets/newlogo_white.png'), context);
    precacheImage(const AssetImage('assets/bg2.2.png'), context);
    _didPrecacheLogo = true;
  }

  Widget _fadeSlideIn({
    required Animation<double> animation,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }

  Future<String?> _showRoleSelectionDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD9E5F2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 32,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.3),
                        ),
                      ),
                      child: _buildSystemLogo(size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create your AI-DSUHIS account',
                        style: _display(
                          size: 19,
                          letterSpacing: 0.1,
                          color: _darkDeepTeal,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: _darkDeepTeal.withValues(alpha: 0.64),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose your access role',
                  style: _display(size: 25, color: _darkDeepTeal),
                ),
                const SizedBox(height: 7),
                Text(
                  'Select the workspace that matches your responsibilities. Public BHW requests are reviewed by the City Health Office before activation.',
                  style: _body(size: 13.5, color: _mutedCoolGray, height: 1.45),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryAqua.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: _primaryAquaBright,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Your role controls the forms, approvals, and portal features available after sign-in.',
                          style: _body(
                            size: 12.5,
                            color: _darkDeepTeal.withValues(alpha: 0.82),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 500
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildRoleOption(
                          width: cardWidth,
                          icon: Icons.account_balance_outlined,
                          title: 'City Health Office',
                          label: 'CHO',
                          description:
                              'City-wide operations, oversight, and health administration.',
                          accent: _primaryAquaBright,
                          onTap: () => Navigator.of(dialogContext).pop('CHO'),
                        ),
                        _buildRoleOption(
                          width: cardWidth,
                          icon: Icons.groups_outlined,
                          title: 'Barangay Health Worker',
                          label: 'BHW',
                          description:
                              'Barangay-level care delivery and patient follow-up.',
                          accent: _primaryAqua,
                          badge: 'Approval required',
                          onTap: () => Navigator.of(dialogContext).pop('BHW'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: _darkDeepTeal.withValues(alpha: 0.72),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption({
    required double width,
    required IconData icon,
    required String title,
    required String label,
    required String description,
    required Color accent,
    required VoidCallback onTap,
    String? badge,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.34)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: _body(
                                size: 14,
                                weight: FontWeight.w800,
                                color: _darkDeepTeal,
                              ),
                            ),
                          ),
                          Text(
                            label,
                            style: _body(
                              size: 11,
                              weight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: _body(
                          size: 12,
                          color: _mutedCoolGray,
                          height: 1.35,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge,
                            style: _body(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: accent.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    // Pre-processed white-on-transparent PNG (derived from newlogo.png's
    // luminance) — avoids ColorFilter.matrix, whose offset-scale behavior
    // is inconsistent across Flutter's web renderers.
    return Image.asset(
      'assets/newlogo_white.png',
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.health_and_safety_rounded,
        color: _primaryAqua,
        size: size * 0.65,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Manrope'),
      ),
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        body: Stack(
          children: [
            // Hero background image (never stretched/distorted — BoxFit.cover
            // crops to fill while preserving aspect ratio). Falls back to the
            // original flat gradient if the asset ever fails to load. Uses the
            // same bg2.2.png photo as login/signup so the whole auth flow
            // reads as one visual system.
            Positioned.fill(
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.045).animate(
                  CurvedAnimation(
                    parent: _bgController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: Image.asset(
                  'assets/bg2.2.png',
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
            ),
            // Deep navy/teal/blue layered scrim over the photo so the hero
            // text/CTA panels stay readable while the image remains visible.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.backgroundDark.withValues(alpha: 0.72),
                      _secondaryIceBlue.withValues(alpha: 0.55),
                      AppColors.surfaceDark.withValues(alpha: 0.86),
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
            // The hero keeps its stable viewport composition. The branded
            // footer lives below it in the landing scroll surface so it can
            // contain the full team/legal information without compressing or
            // reflowing the hero and authentication panel.
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
                        : _buildLandingScroll(context),
                  ),
                ),
              ),
            ),
            // Fixed floating glass navbar — sits in the outer stack (not the
            // scroll view) so it stays pinned while the page scrolls beneath
            // it, and never shifts hero/footer layout.
            if (!_showIntroLoader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: FadeTransition(
                    opacity: _heroEntrance,
                    child: _buildLandingNavbar(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandingNavbar(BuildContext context) {
    return LiquidGlassNavbar(
      logo: _buildSystemLogo(size: 28),
      brandLabel: 'AI-DSUHIS',
      onBrandTap: _scrollToTop,
      items: [
        LiquidGlassNavItem(label: 'Home', active: true, onTap: _scrollToTop),
        LiquidGlassNavItem(
          label: 'About',
          onTap: () => _showGlassInfoDialog(
            context,
            icon: Icons.info_outline_rounded,
            title: 'About AI-DSUHIS',
            body: const [
              'AI-DSUHIS (AI-Driven Solution For Unified Health Information '
                  'System) unifies patient records, check-ups, immunization, '
                  'prenatal care, and disease surveillance for Barangay Health '
                  'Workers and the Malaybalay City Health Office in one '
                  'coordinated platform.',
              'It brings together health monitoring, advanced analytics, '
                  'secure and private access, and cloud sync so every '
                  "barangay's data stays connected, current, and protected.",
            ],
          ),
        ),
        LiquidGlassNavItem(
          label: 'Mission & Vision',
          onTap: () => _showGlassInfoDialog(
            context,
            icon: Icons.flag_outlined,
            title: 'Mission & Vision',
            body: const [
              'Mission: To equip Barangay Health Workers and the City Health '
                  'Office with a unified, AI-assisted platform that makes '
                  'health-service work faster, better coordinated, and '
                  'centered on the people it serves.',
              'Vision: A city where every barangay\'s health data is '
                  'centralized, secure, and instantly accessible — enabling '
                  'coordinated, human-led care across Malaybalay.',
            ],
          ),
        ),
        LiquidGlassNavItem(
          label: 'Terms and Conditions',
          onTap: () => _showGlassInfoDialog(
            context,
            icon: Icons.gavel_outlined,
            title: 'Terms and Conditions',
            body: const [
              'Use AI-DSUHIS only for authorized health-service work. AI '
                  'guidance is supportive information; clinical decisions, '
                  'referrals, and prescriptions remain the responsibility of '
                  'qualified health professionals.',
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showGlassInfoDialog(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> body,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          // The shadow lives on this outer, unclipped box. Putting it on the
          // same decoration as the ClipRRect'd card below caused the blurred
          // shadow to be sliced off right at the rounded corner, reading as
          // a stray second line above the card's real border.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33123A5C),
                  blurRadius: 36,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                // Blurs the page behind the dialog for the glass backdrop
                // feel; the card itself is opaque white to match this app's
                // existing white-card pattern (see _showRoleSelectionDialog).
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(32, 30, 32, 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFD9E5F2)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _primaryAqua.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _primaryAqua.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: _primaryAquaBright,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              style: _display(
                                size: 23,
                                letterSpacing: 0.1,
                                color: _darkDeepTeal,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: _darkDeepTeal.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.65,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final paragraph in body) ...[
                                Text(
                                  paragraph,
                                  style: _body(
                                    size: 15,
                                    weight: FontWeight.w400,
                                    color: _mutedCoolGray,
                                    height: 1.55,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: _primaryAqua,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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

  Widget _buildLandingScroll(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('landing_scroll'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _landingScrollController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            children: [
              // Desktop keeps a viewport-sized hero for its stable two-column
              // composition. Mobile content is deliberately unconstrained in
              // height so its intrinsic content can flow into this scroll
              // view without producing a RenderFlex overflow when the
              // browser height changes.
              if (constraints.maxWidth < 980)
                SizedBox(
                  width: constraints.maxWidth,
                  child: _buildLandingContent(context),
                )
              else
                SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: _buildLandingContent(context),
                ),
              _buildLandingFooter(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLandingContent(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('landing_content'),
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final isDesktop = constraints.maxWidth >= 980;
        final logoSize = isDesktop
            ? _responsive(height, 0.27, 220, 300)
            : _responsive(height, 0.22, 160, 220);
        final titleSize = isDesktop
            ? _responsive(height, 0.086, 56, 96)
            : _responsive(height, 0.064, 40, 60);
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

        final hero = _fadeSlideIn(
          animation: _heroEntrance,
          child: _buildHeroPanel(
            logoSize: logoSize,
            titleSize: titleSize,
            subtitleSize: subtitleSize,
            contentPadding: contentPadding,
            isDesktop: isDesktop,
          ),
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
                          child: _fadeSlideIn(
                            animation: _panelEntrance,
                            child: _buildAccessPanel(context, compact: false),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Tablet/mobile content is intentionally intrinsic-height. The
        // surrounding SingleChildScrollView owns vertical overflow, so the
        // hero and access card do not compete for a fixed viewport height.
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Release the vertical constraint inherited from browser
                // viewport resizes while keeping the hero at the available
                // width. The outer scroll view owns vertical movement.
                UnconstrainedBox(
                  constrainedAxis: Axis.horizontal,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: constraints.maxWidth, child: hero),
                ),
                SizedBox(height: _responsive(height, 0.018, 10, 18)),
                _fadeSlideIn(
                  animation: _panelEntrance,
                  child: _buildAccessPanel(context, compact: true),
                ),
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
    final partnerLogoSize = _responsive(logoSize, 0.46, 70, 96);

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
        // Keep the wordmark a crisp solid white so it remains readable over
        // every part of the photographic backdrop.
        Text(
          'AI-DSUHIS',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.05,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: _responsive(titleSize, 0.24, 8, 16)),
        Text(
          'AI-Driven Solution For Unified Health Information System',
          style: _body(
            size: subtitleSize,
            weight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.90),
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
        padding: EdgeInsets.all(compact ? 24 : 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5EEF0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome Back',
              style: _display(
                size: compact ? 24 : 28,
                weight: FontWeight.w800,
                color: _darkDeepTeal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to continue to your healthcare portal.',
              style: _body(
                size: 14,
                weight: FontWeight.w500,
                color: _mutedCoolGray,
              ),
            ),
            SizedBox(height: compact ? 22 : 28),
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
            SizedBox(height: compact ? 20 : 24),
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
      return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(child: cell(features[0])),
          SizedBox(width: gap),
          Expanded(child: cell(features[1])),
          SizedBox(width: gap),
          Expanded(child: cell(features[2])),
          SizedBox(width: gap),
          Expanded(child: cell(features[3])),
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
    final iconSize = compact ? 28.0 : 30.0;
    final textSize = compact ? 11.5 : 12.0;
    final badge = Container(
      height: compact ? 44 : 52,
      width: stretch ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 7,
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
              style: _body(
                size: textSize,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
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
    // Icon stays pinned to the left edge (consistent x-position across all
    // three buttons regardless of label length). The label centers in the
    // space *between* two equal gutters — the icon slot on the left and a
    // matching blank spacer on the right — rather than on the full button
    // width, otherwise the icon's footprint made the right-hand gap read
    // much bigger than the left, i.e. lopsided instead of balanced.
    const iconSlotWidth = 34.0 + 14.0;
    final child = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPrimary
                ? Colors.white.withValues(alpha: 0.16)
                : _darkBlue.withValues(alpha: 0.10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isPrimary ? Colors.white : _darkBlue,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: _body(
                size: 16,
                weight: FontWeight.w700,
                color: isPrimary ? Colors.white : _darkBlue,
              ),
            ),
          ),
        ),
        const SizedBox(width: iconSlotWidth),
      ],
    );

    // Flat, solid navy for both variants — primary is fully filled, secondary
    // is a light tint of the same color — instead of the previous teal
    // gradient + neutral-gray split, for a cleaner, single-color system.
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isPrimary ? _darkBlue : _darkBlue.withValues(alpha: 0.06),
        border: isPrimary
            ? null
            : Border.all(color: _darkBlue.withValues(alpha: 0.16)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          hoverColor: isPrimary
              ? Colors.white.withValues(alpha: 0.08)
              : _darkBlue.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildLandingFooter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 860;
    final horizontalPadding = compact ? 24.0 : 64.0;

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSystemLogo(size: compact ? 52 : 64),
            const SizedBox(width: 14),
            Text(
              'AI-DSUHIS',
              style: _display(
                size: compact ? 24 : 30,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Unified health information for coordinated, human-led care.',
          style: _body(
            size: 14,
            weight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
      ],
    );

    final team = _buildFooterColumn(
      title: 'Team',
      children: [
        _buildFooterLabel('TEAM LEADER'),
        _buildFooterName('TRISHA JEANNE ALSOLA'),
        const SizedBox(height: 14),
        _buildFooterLabel('MAIN DEVELOPERS'),
        _buildFooterName('ATHEO JESSAR CALIAO'),
        _buildFooterName('LORD LYLE KIMPERT AGREDA'),
        _buildFooterName('DHARRYL DAVE CLERIGO'),
        const SizedBox(height: 14),
        _buildFooterLabel('CAPSTONE ADVISER'),
        _buildFooterName('DR. MARILOU O. ESPINA'),
        _buildFooterName('DEAN, COLLEGE OF TECHNOLOGIES'),
      ],
    );

    final legal = _buildFooterColumn(
      title: 'Information',
      children: [
        Text(
          'Responsible access for City Health Office and Barangay Health Worker teams.',
          style: _body(
            size: 13,
            weight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        _buildFooterLink(
          context,
          'Privacy Policy',
          'AI-DSUHIS Privacy Policy',
          PrivacyNoticeContent.dialogText,
        ),
        _buildFooterLink(
          context,
          'Terms of Service',
          'AI-DSUHIS Terms of Service',
          'Use AI-DSUHIS only for authorized health-service work. AI guidance is supportive information; clinical decisions, referrals, and prescriptions remain the responsibility of qualified health professionals.',
        ),
      ],
    );

    final columns = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brand,
              const SizedBox(height: 36),
              team,
              const SizedBox(height: 32),
              legal,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: brand),
              const SizedBox(width: 44),
              Expanded(flex: 3, child: team),
              const SizedBox(width: 44),
              Expanded(flex: 3, child: legal),
            ],
          );

    return Container(
      width: double.infinity,
      color: const Color(0xFF061B3A),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 42 : 58,
        horizontalPadding,
        compact ? 26 : 34,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: compact ? -18 : 10,
            bottom: compact ? 48 : 36,
            child: IgnorePointer(
              child: Text(
                'AI-DSUHIS',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: compact ? 76 : 170,
                  fontWeight: FontWeight.w700,
                  height: 0.8,
                  letterSpacing: -5,
                  color: Colors.white.withValues(alpha: 0.035),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              columns,
              const SizedBox(height: 44),
              Divider(color: Colors.white.withValues(alpha: 0.16), height: 1),
              const SizedBox(height: 18),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFooterCopyright(),
                    const SizedBox(height: 12),
                    _buildFooterLegalLinks(context),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildFooterCopyright(),
                    _buildFooterLegalLinks(context),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterColumn({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: _display(size: 17, color: Colors.white, letterSpacing: 0.1),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  Widget _buildFooterLabel(String text) {
    return Text(
      text,
      style: _body(
        size: 10,
        weight: FontWeight.w700,
        color: _primaryAquaBright,
        height: 1.2,
      ),
    );
  }

  Widget _buildFooterName(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        text,
        style: _body(
          size: 12.5,
          weight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.82),
          height: 1.25,
        ),
      ),
    );
  }

  Widget _buildFooterLink(
    BuildContext context,
    String label,
    String title,
    String message,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => _showLegalDialog(context, title, message),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 5),
          foregroundColor: Colors.white,
          textStyle: _body(size: 13, weight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildFooterCopyright() {
    return Text(
      '© 2026 AI-DSUHIS. All rights reserved.',
      style: _body(
        size: 12,
        weight: FontWeight.w400,
        color: Colors.white.withValues(alpha: 0.68),
      ),
    );
  }

  Widget _buildFooterLegalLinks(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 4,
      children: [
        _buildFooterLink(
          context,
          'Privacy Policy',
          'AI-DSUHIS Privacy Policy',
          PrivacyNoticeContent.dialogText,
        ),
        _buildFooterLink(
          context,
          'Terms of Service',
          'AI-DSUHIS Terms of Service',
          'Use AI-DSUHIS only for authorized health-service work. AI guidance is supportive information; clinical decisions, referrals, and prescriptions remain the responsibility of qualified health professionals.',
        ),
      ],
    );
  }

  Future<void> _showLegalDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
