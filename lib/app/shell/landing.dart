import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/shared/widgets/privacy_notice_button.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';

// Unified Transparent Liquid Glass Theme matching the Web Navbar
abstract final class _LiquidGlassTheme {
  static const deepNavy = Color(0xFF0F2642);
  static const surfaceNavy = Color(0xFF132F52);
  static const glassBorder = Color(0x38FFFFFF); // ~22% white
  static const glassHighlight = Color(0x52FFFFFF); // ~32% white
  static const activeCardBg = Color(0x2EFFFFFF); // ~18% white
  static const inactiveCardBg = Color(0x12FFFFFF); // ~7% white
  static const iconBadgeBg = Color(0x24FFFFFF); // ~14% white
  static const textPrimary = Colors.white;
  static const textMuted = Color(0xFFE3EDF8);
  static const secondaryMuted = Color(0xFFA5C4E5);
}

/// Mobile entry screen with responsive hero branding, authentication panel,
/// and an interactive transparent liquid frosted-glass navigation drawer and glassable information modals.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      drawerScrimColor: Colors.black.withValues(alpha: 0.25),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
          child: Builder(
            builder: (ctx) => _AnimatedGlassButton(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
      drawer: _buildLandingDrawer(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg2.2.png', fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _LiquidGlassTheme.deepNavy.withValues(alpha: 0.88),
                  AppDesign.navy.withValues(alpha: 0.82),
                  _LiquidGlassTheme.surfaceNavy.withValues(alpha: 0.90),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final hero = _buildHero(context, compact: compact);
                final auth = _buildAuthPanel(context);
                if (compact) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
    final logoSize = compact ? 124.0 : 170.0;
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
            color: Colors.white.withValues(alpha: 0.88),
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthPanel(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppDesign.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to continue to your authorized healthcare portal.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppDesign.muted,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Get.toNamed(MobileRoutes.login),
                icon: const Icon(Icons.login_rounded, size: 19),
                label: const Text('Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesign.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => Get.toNamed(MobileRoutes.signup),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                label: const Text('Create account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesign.ink,
                  side: const BorderSide(color: AppDesign.border, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Get.offAll(
                  () => const HomePage(),
                  arguments: const {'offline': true},
                ),
                icon: const Icon(Icons.cloud_off_rounded, size: 18, color: AppDesign.muted),
                label: const Text('Continue offline', style: TextStyle(color: AppDesign.muted, fontWeight: FontWeight.w600)),
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
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppDesign.border),
      ),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }

  // =========================================================================
  // TRANSPARENT LIQUID GLASS NAVIGATION DRAWER WITH ENHANCED TRANSITIONS
  // =========================================================================

  Widget _buildLandingDrawer(BuildContext context) {
    return SizedBox(
      width: 290,
      child: Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _LiquidGlassTheme.deepNavy.withValues(alpha: 0.38),
                    _LiquidGlassTheme.surfaceNavy.withValues(alpha: 0.28),
                  ],
                ),
                border: const Border(
                  right: BorderSide(color: _LiquidGlassTheme.glassBorder, width: 1.2),
                ),
              ),
              child: SafeArea(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                  children: [
                    // Pure Navigator Header
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.explore_outlined, color: _LiquidGlassTheme.secondaryMuted, size: 17),
                          SizedBox(width: 8),
                          Text(
                            'NAVIGATOR',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              color: _LiquidGlassTheme.secondaryMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Staggered & Animated Liquid Glass Navigation Buttons
                    _AnimatedGlassNavTile(
                      index: 0,
                      label: 'Home',
                      icon: Icons.home_rounded,
                      isActive: true,
                      onTap: () => _handleNavTap(context, _showHomeModal),
                    ),
                    const SizedBox(height: 10),
                    _AnimatedGlassNavTile(
                      index: 1,
                      label: 'About',
                      icon: Icons.info_outline_rounded,
                      isActive: false,
                      onTap: () => _handleNavTap(context, _showAboutModal),
                    ),
                    const SizedBox(height: 10),
                    _AnimatedGlassNavTile(
                      index: 2,
                      label: 'Features',
                      icon: Icons.featured_play_list_outlined,
                      isActive: false,
                      onTap: () => _handleNavTap(context, _showFeaturesModal),
                    ),
                    const SizedBox(height: 10),
                    _AnimatedGlassNavTile(
                      index: 3,
                      label: 'How It Works',
                      icon: Icons.alt_route_rounded,
                      isActive: false,
                      onTap: () => _handleNavTap(context, _showHowItWorksModal),
                    ),
                    const SizedBox(height: 10),
                    _AnimatedGlassNavTile(
                      index: 4,
                      label: 'Security',
                      icon: Icons.shield_outlined,
                      isActive: false,
                      onTap: () => _handleNavTap(context, _showSecurityModal),
                    ),
                    const SizedBox(height: 10),
                    _AnimatedGlassNavTile(
                      index: 5,
                      label: 'Contact',
                      icon: Icons.contact_mail_outlined,
                      isActive: false,
                      onTap: () => _handleNavTap(context, _showContactModal),
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

  /// Smoothly dismisses the drawer with an easing delay before opening the modal.
  Future<void> _handleNavTap(
    BuildContext context,
    void Function(BuildContext) showModal,
  ) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (context.mounted) {
      showModal(context);
    }
  }

  // =========================================================================
  // TRANSPARENT GLASSABLE MODALS (TRANSLUCENT FROSTED GLASS THEME)
  // =========================================================================

  void _showContentModal(
    BuildContext context, {
    required String eyebrow,
    required String title,
    required String subtitle,
    required Widget content,
    IconData icon = Icons.info_outline_rounded,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _LiquidGlassTheme.deepNavy.withValues(alpha: 0.48),
                    _LiquidGlassTheme.surfaceNavy.withValues(alpha: 0.38),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: const Border(top: BorderSide(color: _LiquidGlassTheme.glassHighlight, width: 1.5)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Glassable Modal Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.40),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _LiquidGlassTheme.iconBadgeBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _LiquidGlassTheme.glassBorder),
                                ),
                                child: Icon(icon, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      eyebrow.toUpperCase(),
                                      style: const TextStyle(
                                        fontFamily: 'Manrope',
                                        color: _LiquidGlassTheme.secondaryMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontFamily: 'Manrope',
                                        color: _LiquidGlassTheme.textPrimary,
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: _LiquidGlassTheme.secondaryMuted),
                                onPressed: () => Navigator.of(sheetContext).pop(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _LiquidGlassTheme.glassBorder),
                    // Scrollable Clinical & Institutional Content
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (subtitle.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _LiquidGlassTheme.glassBorder),
                                ),
                                child: Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontFamily: 'Manrope',
                                    color: _LiquidGlassTheme.textMuted,
                                    fontSize: 13.5,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            content,
                          ],
                        ),
                      ),
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

  Widget _buildProfessionalCard({
    required IconData icon,
    required String title,
    required String body,
    Color iconColor = Colors.white,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _LiquidGlassTheme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _LiquidGlassTheme.iconBadgeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _LiquidGlassTheme.glassBorder),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    color: _LiquidGlassTheme.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    color: _LiquidGlassTheme.textMuted,
                    fontSize: 12.8,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. HOME: EXECUTIVE PLATFORM INFRASTRUCTURE ---
  void _showHomeModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.home_rounded,
      eyebrow: 'Unified Healthcare Infrastructure',
      title: 'Enterprise Platform Architecture',
      subtitle:
          'AI-DSUHIS (AI-Driven Solution For Unified Health Information System) establishes a bi-directional clinical data bridge connecting frontline Barangay Health Stations with the City Health Office.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfessionalCard(
            icon: Icons.hub_rounded,
            title: 'Municipal Health System Interoperability',
            body: 'Unifies decentralized barangay health records into a coordinated, municipal-wide health ecosystem with standardized DOH coding.',
          ),
          _buildProfessionalCard(
            icon: Icons.offline_pin_rounded,
            title: 'Offline-First Edge Data Pipeline',
            body: 'Enables continuous field data capture in remote areas with automatic background transactional synchronization upon connectivity restoration.',
          ),
          _buildProfessionalCard(
            icon: Icons.psychology_alt_rounded,
            title: 'Clinical AI Decision Support System',
            body: 'Automates symptom triage categorization, highlights emergency red flags, and provides ICD-10 diagnostic suggestion algorithms.',
          ),
          _buildProfessionalCard(
            icon: Icons.security_rounded,
            title: 'Role-Governed Jurisdictional Security',
            body: 'Enforces strict cryptographic authentication, immutable activity auditing, and rigorous barangay-scoped data partitioning.',
          ),
        ],
      ),
    );
  }

  // --- 2. ABOUT: INSTITUTIONAL OBJECTIVES & IMPACT ---
  void _showAboutModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.info_outline_rounded,
      eyebrow: 'Institutional Objectives & Impact',
      title: 'Modernizing Public Health Governance',
      subtitle:
          'AI-DSUHIS addresses foundational operational bottlenecks in community-level healthcare delivery, eliminating fragmentation, manual encoding backlogs, and delayed public health surveillance.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfessionalCard(
            icon: Icons.inventory_2_rounded,
            title: 'Elimination of Fragmented Records',
            body: 'Consolidates paper-based logbooks and siloed registries into a single Master Patient Index (MPI) with continuous longitudinal medical tracking.',
          ),
          _buildProfessionalCard(
            icon: Icons.document_scanner_rounded,
            title: 'Optical Intake & Redundancy Reduction',
            body: 'Employs on-device optical character recognition (OCR) to convert physical clinic forms into validated structured records without duplicate data entry.',
          ),
          _buildProfessionalCard(
            icon: Icons.query_stats_rounded,
            title: 'Real-Time Epidemiological Surveillance',
            body: 'Transforms point-of-care consultations into real-time morbidity summaries (MBD-2026), mortality notifications (MOR-2026), and municipal health indicators.',
          ),
        ],
      ),
    );
  }

  // --- 3. FEATURES: CLINICAL & EPIDEMIOLOGICAL SUITE ---
  void _showFeaturesModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.featured_play_list_outlined,
      eyebrow: 'Clinical & Epidemiological Suite',
      title: 'End-to-End Healthcare Operations',
      subtitle:
          'Integrated functional modules designed in alignment with standard Department of Health (DOH) clinical protocols and local government operational workflows.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfessionalCard(
            icon: Icons.badge_rounded,
            title: 'Master Patient & Household Registry',
            body: 'Maintains unique national/local patient identifiers, demographic registries, family profiling, and geocoded household mapping.',
          ),
          _buildProfessionalCard(
            icon: Icons.medical_services_rounded,
            title: 'Consultations & 4-Tab Triage Referrals',
            body: 'Streamlines check-ups with a 4-tab referral queue, urgency triage (Routine, Urgent, Emergency), specialist matching, and community follow-up visit logs.',
          ),
          _buildProfessionalCard(
            icon: Icons.pregnant_woman_rounded,
            title: 'Obstetric Prenatal & EPI Immunization',
            body: 'Dedicated tracking for high-risk maternal obstetric history, trimester visits, tetanus toxoid schedules, and childhood vaccine dose compliance.',
          ),
          _buildProfessionalCard(
            icon: Icons.camera_enhance_rounded,
            title: 'Mobile OCR Optical Digitization',
            body: 'Scans paper clinical forms (CHK, PNC, IMZ, MBD, MOR, PAT, REF) via mobile camera with automatic character recognition and field validation.',
          ),
          _buildProfessionalCard(
            icon: Icons.analytics_rounded,
            title: 'Morbidity & Mortality Surveillance',
            body: 'Live surveillance tracking for communicable and non-communicable diseases, ICD-10 mortality classification, and printable official PDF reports.',
          ),
          _buildProfessionalCard(
            icon: Icons.auto_awesome_rounded,
            title: 'Clinical AI Decision Support Guardrails',
            body: 'Surfaces non-prescriptive supportive guidance, risk indicators, and mandatory clinician-in-the-loop review prompts.',
          ),
        ],
      ),
    );
  }

  // --- 4. HOW IT WORKS: DATA GOVERNANCE PIPELINE ---
  void _showHowItWorksModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.alt_route_rounded,
      eyebrow: 'Operational Architecture',
      title: '5-Tier Data Governance Pipeline',
      subtitle:
          'A structured five-tier data pipeline ensuring clinical accuracy, administrative compliance, and synchronized municipal decision-making.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DATA GOVERNANCE LIFECYCLE',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: _LiquidGlassTheme.secondaryMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          _buildProfessionalCard(
            icon: Icons.edit_location_alt_rounded,
            title: 'Tier 1: Point-of-Care Data Intake',
            body: 'Barangay Health Workers record consultations, vitals, obstetric notes, and home visits in the field.',
          ),
          _buildProfessionalCard(
            icon: Icons.fact_check_rounded,
            title: 'Tier 2: Edge Validation & Optical Parsing',
            body: 'Client-side rules validate clinical fields while mobile OCR digitizes physical intake forms.',
          ),
          _buildProfessionalCard(
            icon: Icons.sync_lock_rounded,
            title: 'Tier 3: Cloud Synchronization Engine',
            body: 'Encrypted replication reconciles offline local SQLite storage with central Firestore collections.',
          ),
          _buildProfessionalCard(
            icon: Icons.assignment_ind_rounded,
            title: 'Tier 4: Specialist Triage & Clinical Review',
            body: 'City Health Office physicians evaluate referrals, assign attending doctors, and document diagnoses.',
          ),
          _buildProfessionalCard(
            icon: Icons.insights_rounded,
            title: 'Tier 5: Executive Surveillance Intelligence',
            body: 'Automated engines aggregate disease trends, immunization coverage, and health program KPIs.',
          ),
          const SizedBox(height: 14),
          const Text(
            'STAKEHOLDER ROLE MATRIX',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: _LiquidGlassTheme.secondaryMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          _buildProfessionalCard(
            icon: Icons.health_and_safety_rounded,
            title: 'Barangay Health Workers (BHW)',
            body: 'Frontline community enumeration, vital signs intake, immunization schedules, and home visit logs.',
          ),
          _buildProfessionalCard(
            icon: Icons.local_hospital_rounded,
            title: 'City Health Office (CHO) Clinicians',
            body: 'Specialist case review, diagnostic consultation, prescription directives, and referral disposition.',
          ),
          _buildProfessionalCard(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Health System Administrators',
            body: 'User role credentialing, scope governance, audit trail verification, and infrastructure security.',
          ),
        ],
      ),
    );
  }

  // --- 5. SECURITY: DATA GOVERNANCE & AI BOUNDARIES ---
  void _showSecurityModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.shield_outlined,
      eyebrow: 'Data Governance & Clinical Safety',
      title: 'Security, Privacy & AI Boundaries',
      subtitle:
          'Engineered in strict accordance with the Philippine Data Privacy Act of 2012 (RA 10173), DOH guidelines, and international health information security standards.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfessionalCard(
            icon: Icons.lock_outline_rounded,
            title: 'Role-Based Access Control (RBAC)',
            body: 'Patient health records are strictly partitioned by barangay jurisdiction and accessible only through verified, multi-factor authenticated roles.',
          ),
          _buildProfessionalCard(
            icon: Icons.gavel_rounded,
            title: 'Clinical AI Decision Support Guardrails',
            body: 'AI guidance operates strictly as a non-diagnostic decision-support aid. The system explicitly prohibits autonomous diagnosis, automated medication prescribing, or replacing clinical judgment.',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _LiquidGlassTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Regulatory Compliance & Operator Terms',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: _LiquidGlassTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Access to AI-DSUHIS is restricted to authorized public healthcare practitioners. All transactions are logged for regulatory compliance.',
                  style: TextStyle(fontFamily: 'Manrope', color: _LiquidGlassTheme.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => _showLegalDialog(
                        context,
                        'AI-DSUHIS Data Privacy Policy',
                        PrivacyNoticeContent.dialogText,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesign.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Data Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    OutlinedButton(
                      onPressed: () => _showLegalDialog(
                        context,
                        'AI-DSUHIS Operator Terms of Service',
                        'Use AI-DSUHIS only for authorized health-service work. AI guidance is supportive information; clinical decisions, referrals, and prescriptions remain the responsibility of qualified health professionals.',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _LiquidGlassTheme.glassBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Terms of Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. CONTACT: PROJECT DIRECTORATE & GOVERNANCE ---
  void _showContactModal(BuildContext context) {
    _showContentModal(
      context,
      icon: Icons.contact_mail_outlined,
      eyebrow: 'Project Directorate & Governance',
      title: 'AI-DSUHIS Research & Development',
      subtitle:
          'Developed under the Healthcare Systems & Technology Initiative of the College of Technologies in coordination with public health institutions.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfessionalCard(
            icon: Icons.star_rounded,
            title: 'Project Lead & Clinical Analyst',
            body: 'TRISHA JEANNE ALSOLA',
          ),
          _buildProfessionalCard(
            icon: Icons.terminal_rounded,
            title: 'Principal Software Engineers',
            body: 'ATHEO JESSAR CALIAO\nLORD LYLE KIMPERT AGREDA\nDHARRYL DAVE CLERIGO',
          ),
          _buildProfessionalCard(
            icon: Icons.school_rounded,
            title: 'Capstone Academic Adviser',
            body: 'DR. MARILOU O. ESPINA\nDean, College of Technologies',
          ),
          _buildProfessionalCard(
            icon: Icons.alternate_email_rounded,
            title: 'Institutional Communications',
            body: 'aidsuhis@gmail.com\n(For official institutional and technical correspondence only. Strictly no transmission of unencrypted identifiable patient records.)',
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '© 2026 AI-DSUHIS • Unified Health Information System\nAll Rights Reserved',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                color: _LiquidGlassTheme.secondaryMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegalDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AlertDialog(
            backgroundColor: _LiquidGlassTheme.deepNavy.withValues(alpha: 0.50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: _LiquidGlassTheme.glassBorder),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: _LiquidGlassTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            content: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  color: _LiquidGlassTheme.textMuted,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesign.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive liquid glass button with tactile scaling and hover micro-animations.
class _AnimatedGlassButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _AnimatedGlassButton({
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  State<_AnimatedGlassButton> createState() => _AnimatedGlassButtonState();
}

class _AnimatedGlassButtonState extends State<_AnimatedGlassButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: _isHovered ? 0.24 : 0.16),
                  Colors.white.withValues(alpha: _isHovered ? 0.12 : 0.07),
                ],
              ),
              border: Border.all(
                color: _isHovered
                    ? _LiquidGlassTheme.glassHighlight
                    : _LiquidGlassTheme.glassBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _LiquidGlassTheme.deepNavy.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Interactive liquid glass navigation tile with staggered entry, press scale, and glow transitions.
class _AnimatedGlassNavTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final int index;
  final VoidCallback onTap;

  const _AnimatedGlassNavTile({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.index,
    required this.onTap,
  });

  @override
  State<_AnimatedGlassNavTile> createState() => _AnimatedGlassNavTileState();
}

class _AnimatedGlassNavTileState extends State<_AnimatedGlassNavTile> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.isActive || _isHovered;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 260 + (widget.index * 40)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset((1.0 - value) * -18.0, 0),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: highlighted
                    ? (widget.isActive
                        ? _LiquidGlassTheme.activeCardBg
                        : Colors.white.withValues(alpha: 0.14))
                    : _LiquidGlassTheme.inactiveCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highlighted
                      ? _LiquidGlassTheme.glassHighlight
                      : _LiquidGlassTheme.glassBorder,
                  width: 1,
                ),
                boxShadow: highlighted
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: highlighted ? 0.22 : 0.09,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      widget.icon,
                      color: highlighted
                          ? Colors.white
                          : _LiquidGlassTheme.secondaryMuted,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14.5,
                        fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
                        color: highlighted
                            ? Colors.white
                            : _LiquidGlassTheme.textPrimary.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                  AnimatedSlide(
                    offset: _isHovered || _isPressed
                        ? const Offset(0.2, 0)
                        : Offset.zero,
                    duration: const Duration(milliseconds: 140),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: Colors.white.withValues(
                        alpha: highlighted ? 0.88 : 0.35,
                      ),
                    ),
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
