import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Public, non-authenticated product information that follows the existing
/// landing hero. This stays separate from the auth panel so the login and
/// registration flows remain unchanged.
class LandingSections extends StatelessWidget {
  const LandingSections({
    super.key,
    required this.aboutKey,
    required this.featuresKey,
    required this.howItWorksKey,
    required this.securityKey,
    required this.contactKey,
    required this.onAccessSystem,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
  });

  final GlobalKey aboutKey;
  final GlobalKey featuresKey;
  final GlobalKey howItWorksKey;
  final GlobalKey securityKey;
  final GlobalKey contactKey;
  final VoidCallback onAccessSystem;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildAboutSection(),
        _buildHowItWorksSection(),
        _buildFeaturesSection(),
        _buildTrustAndPreviewSection(),
        _buildFaqSection(),
        _buildContactSection(),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _LandingSection(
      anchorKey: aboutKey,
      eyebrow: 'WHY AI-DSUHIS',
      title: 'One connected workspace for community health teams',
      body:
          'AI-DSUHIS brings the information used in community-health work into one coordinated place for authorized Barangay Health Workers and City Health Office teams.',
      child: _buildInfoGrid(const [
        _CardData(
          icon: Icons.folder_copy_outlined,
          title: 'Fragmented records',
          body:
              'Keep patient and service information organized across the workflows that teams already use.',
        ),
        _CardData(
          icon: Icons.edit_note_outlined,
          title: 'Repetitive encoding',
          body:
              'Use structured forms and mobile OCR assistance to reduce avoidable re-entry while keeping fields reviewable.',
        ),
        _CardData(
          icon: Icons.assessment_outlined,
          title: 'Delayed reporting',
          body:
              'Prepare summaries and reports from the same role-scoped records used for day-to-day work.',
        ),
      ]),
    );
  }

  Widget _buildHowItWorksSection() {
    return _LandingSection(
      anchorKey: howItWorksKey,
      tinted: true,
      eyebrow: 'HOW IT WORKS',
      title: 'From barangay information to coordinated review',
      body:
          'The system connects field-level record keeping with city-level review while keeping access aligned with the user’s role and assigned scope.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildWorkflow(),
          const SizedBox(height: 40),
          Text('WHO USES THE SYSTEM', style: _eyebrowStyle(AppColors.primary)),
          const SizedBox(height: 12),
          _buildRoleGrid(),
        ],
      ),
    );
  }

  Widget _buildWorkflow() {
    const steps = [
      _FlowStep(
        icon: Icons.groups_outlined,
        title: 'Barangay Health Workers',
        body: 'Capture and update health information.',
      ),
      _FlowStep(
        icon: Icons.description_outlined,
        title: 'Health information',
        body: 'Structured records, forms, and follow-up details.',
      ),
      _FlowStep(
        icon: Icons.hub_outlined,
        title: 'AI-DSUHIS',
        body: 'Connect the authorized workflow in one workspace.',
      ),
      _FlowStep(
        icon: Icons.account_balance_outlined,
        title: 'City Health Office',
        body: 'Review role-scoped barangay information.',
      ),
      _FlowStep(
        icon: Icons.insights_outlined,
        title: 'Reports & insights',
        body: 'Support monitoring, referrals, and planning.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        if (compact) {
          return Column(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                _buildFlowStep(steps[index], compact: true),
                if (index < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_downward_rounded,
                        size: 18,
                        color: AppColors.primary.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              Expanded(child: _buildFlowStep(steps[index])),
              if (index < steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Center(
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: AppColors.primary.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFlowStep(_FlowStep step, {bool compact = false}) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconBadge(icon: step.icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title, style: _cardTitleStyle()),
              const SizedBox(height: 5),
              Text(step.body, style: _cardBodyStyle()),
            ],
          ),
        ),
      ],
    );

    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 86) : null,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: content,
    );
  }

  Widget _buildRoleGrid() {
    const roles = [
      _CardData(
        icon: Icons.medical_information_outlined,
        title: 'Barangay Health Workers',
        body: 'Record community-level services, follow-ups, and referrals.',
      ),
      _CardData(
        icon: Icons.account_balance_outlined,
        title: 'City Health Office',
        body:
            'Review city-facing information, reports, and operational workspaces.',
      ),
      _CardData(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Authorized administrators',
        body: 'Manage approved accounts and role-governed system operations.',
      ),
    ];
    return _buildInfoGrid(roles);
  }

  Widget _buildFeaturesSection() {
    return _LandingSection(
      anchorKey: featuresKey,
      eyebrow: 'FEATURES',
      title: 'Tools that support the complete health-information workflow',
      body:
          'Each feature is designed around the records, service modules, and review responsibilities already present in AI-DSUHIS.',
      child: _buildInfoGrid(const [
        _CardData(
          icon: Icons.person_search_outlined,
          title: 'Patient & household records',
          body:
              'Maintain structured information for authorized health-service work.',
        ),
        _CardData(
          icon: Icons.assignment_outlined,
          title: 'Check-ups & referrals',
          body:
              'Document check-ups and move referral information through the appropriate review path.',
        ),
        _CardData(
          icon: Icons.vaccines_outlined,
          title: 'Prenatal & immunization',
          body:
              'Use dedicated workflows for prenatal care and immunization monitoring.',
        ),
        _CardData(
          icon: Icons.document_scanner_outlined,
          title: 'OCR-assisted entry',
          body:
              'Scan supported forms on mobile, review extracted fields, and continue through normal validation.',
        ),
        _CardData(
          icon: Icons.bar_chart_outlined,
          title: 'Reports & analytics',
          body:
              'Prepare summaries, formal reports, and dashboard views for monitoring and planning.',
        ),
        _CardData(
          icon: Icons.auto_graph_outlined,
          title: 'AI-assisted health insights',
          body:
              'Surface supportive guidance, warning signs, and human-review prompts for health workers.',
        ),
      ]),
    );
  }

  Widget _buildInfoGrid(List<_CardData> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width >= 920
            ? (width - 32) / 3
            : width >= 600
            ? (width - 16) / 2
            : width;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: _buildInfoCard(card)),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(_CardData card) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: card.icon, color: AppColors.primary),
          const SizedBox(height: 15),
          Text(card.title, style: _cardTitleStyle()),
          const SizedBox(height: 7),
          Text(card.body, style: _cardBodyStyle()),
        ],
      ),
    );
  }

  Widget _buildTrustAndPreviewSection() {
    return _LandingSection(
      anchorKey: securityKey,
      tinted: true,
      eyebrow: 'AI, REPORTING & PRIVACY',
      title: 'Supportive technology with clear boundaries',
      body:
          'The public experience describes what the verified implementation does—and keeps professional review at the center of every AI-assisted workflow.',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 780;
              final aiCard = _buildAiCard();
              final privacyCard = _buildPrivacyCard();
              if (stacked) {
                return Column(
                  children: [aiCard, const SizedBox(height: 16), privacyCard],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: aiCard),
                  const SizedBox(width: 16),
                  Expanded(child: privacyCard),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSystemPreview(),
        ],
      ),
    );
  }

  Widget _buildAiCard() {
    return _DetailCard(
      icon: Icons.psychology_outlined,
      title: 'AI-assisted health insights',
      body:
          'Active symptom guidance uses authenticated requests and reviewed content to surface supportive information, emergency warnings, referral prompts, and human-review messaging.',
      footer:
          'AI-DSUHIS does not diagnose patients, prescribe medication, or replace qualified clinical judgment.',
    );
  }

  Widget _buildPrivacyCard() {
    return _DetailCard(
      icon: Icons.verified_user_outlined,
      title: 'Security & data privacy',
      body:
          'Protected workflows use Firebase Authentication and Firestore security rules. Access is governed by approved roles and assigned barangay scope.',
      bullets: const [
        'Authentication is required for protected workspaces.',
        'App Check is required for the active AI guidance endpoint.',
        'AI output carries review and limitation messaging.',
      ],
      actions: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: onOpenPrivacy,
            child: const Text('Privacy and permissions'),
          ),
          TextButton(
            onPressed: onOpenTerms,
            child: const Text('Terms of service'),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemPreview() {
    return Semantics(
      container: true,
      label: 'Illustrative AI-DSUHIS workspace preview with no patient data',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.55),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            final workspace = _buildPreviewWorkspace(compact: compact);
            if (compact) return workspace;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPreviewSidebar(),
                const SizedBox(width: 18),
                Expanded(child: workspace),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewSidebar() {
    const items = ['Dashboard', 'Patient records', 'Check-ups', 'Reports'];
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI-DSUHIS',
            style: TextStyle(
              fontFamily: AppTheme.displayFontFamily,
              color: AppColors.textOnDark,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                items[index],
                style: TextStyle(
                  color: AppColors.textOnDark.withValues(
                    alpha: index == 0 ? 1 : 0.64,
                  ),
                  fontSize: 12,
                  fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewWorkspace({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Role-scoped workspace',
                    style: TextStyle(
                      fontFamily: AppTheme.displayFontFamily,
                      color: AppColors.textOnDark,
                      fontSize: compact ? 20 : 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'A representative view of the records, follow-up, and reporting areas available after authorized sign-in.',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 16),
              _PreviewPill(label: 'No live records shown'),
            ],
          ],
        ),
        if (compact) ...[
          const SizedBox(height: 14),
          _PreviewPill(label: 'No live records shown'),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final area in const [
              _PreviewArea(
                icon: Icons.people_alt_outlined,
                label: 'Patient registry',
              ),
              _PreviewArea(
                icon: Icons.assignment_turned_in_outlined,
                label: 'Service records',
              ),
              _PreviewArea(
                icon: Icons.compare_arrows_outlined,
                label: 'Referrals',
              ),
              _PreviewArea(
                icon: Icons.insights_outlined,
                label: 'Reports & insights',
              ),
            ])
              if (compact)
                SizedBox(width: double.infinity, child: area)
              else
                area,
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textOnDarkMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Illustrative interface only. Public pages never display production patient information.',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaqSection() {
    const questions = [
      _FaqData(
        question: 'Who can access AI-DSUHIS?',
        answer:
            'The public site is an entry point for authorized Barangay Health Workers, City Health Office personnel, doctors, and approved system administrators. Protected workspaces remain behind sign-in and role checks.',
      ),
      _FaqData(
        question: 'What is AI used for?',
        answer:
            'The active AI feature provides non-prescriptive symptom guidance and decision support, including supportive information, warning signs, referral prompts, and human-review messaging.',
      ),
      _FaqData(
        question: 'Does AI-DSUHIS diagnose patients?',
        answer:
            'No. AI-assisted output supports review by qualified health professionals. It is not a diagnosis, treatment, medication, or prescription tool.',
      ),
      _FaqData(
        question: 'How is access controlled?',
        answer:
            'Firebase Authentication, role checks, approval policies, and Firestore security rules work together to limit protected information to the appropriate role and assigned barangay scope.',
      ),
      _FaqData(
        question: 'Does the system support different screen sizes?',
        answer:
            'Yes. The Flutter web experience adapts its navigation, cards, workflow presentation, and authentication layout for desktop, tablet, and mobile widths.',
      ),
    ];

    return _LandingSection(
      eyebrow: 'FAQ',
      title: 'Clear answers before you sign in',
      body:
          'A concise overview of access, AI boundaries, privacy, and responsive use.',
      child: Column(
        children: [
          for (final item in questions) ...[
            _buildFaqItem(item),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildFaqItem(_FaqData item) {
    return Container(
      decoration: _cardDecoration(),
      child: Material(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(item.question, style: _cardTitleStyle()),
          children: [Text(item.answer, style: _cardBodyStyle())],
        ),
      ),
    );
  }

  Widget _buildContactSection() {
    return _LandingSection(
      anchorKey: contactKey,
      dark: true,
      eyebrow: 'AUTHORIZED ACCESS',
      title: 'Ready to enter the workspace?',
      body:
          'AI-DSUHIS is intended for authorized health-service work. Sign in to continue, or use the account flow that matches your approved role.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onAccessSystem,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Access system'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  static BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    );
  }

  static TextStyle _eyebrowStyle(Color color) {
    return TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
      color: color,
    );
  }

  static TextStyle _cardTitleStyle() {
    return const TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w800,
      height: 1.25,
      color: AppColors.textPrimary,
    );
  }

  static TextStyle _cardBodyStyle() {
    return const TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.5,
      color: AppColors.textSecondary,
    );
  }
}

class _LandingSection extends StatelessWidget {
  const _LandingSection({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.child,
    this.anchorKey,
    this.tinted = false,
    this.dark = false,
  });

  final GlobalKey? anchorKey;
  final String eyebrow;
  final String title;
  final String body;
  final Widget child;
  final bool tinted;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: anchorKey,
      width: double.infinity,
      color: dark
          ? AppColors.backgroundDark
          : tinted
          ? AppColors.canvasLight
          : AppColors.backgroundLight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final horizontal = compact ? 20.0 : 48.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              compact ? 52 : 72,
              horizontal,
              compact ? 52 : 72,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: LandingSections._eyebrowStyle(
                        dark ? AppColors.primary : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFontFamily,
                          fontSize: compact ? 27 : 38,
                          fontWeight: FontWeight.w700,
                          height: 1.12,
                          letterSpacing: -0.4,
                          color: dark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        body,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: compact ? 14 : 15.5,
                          fontWeight: FontWeight.w500,
                          height: 1.55,
                          color: dark
                              ? AppColors.textOnDarkMuted
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    child,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
    this.bullets = const [],
    this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? footer;
  final List<String> bullets;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: LandingSections._cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, color: AppColors.primary),
          const SizedBox(height: 15),
          Text(title, style: LandingSections._cardTitleStyle()),
          const SizedBox(height: 8),
          Text(body, style: LandingSections._cardBodyStyle()),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bullet,
                        style: LandingSections._cardBodyStyle(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(footer!, style: LandingSections._cardBodyStyle()),
            ),
          ],
          if (actions != null) ...[const SizedBox(height: 8), actions!],
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: AppColors.textOnDarkMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppColors.textOnDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardData {
  const _CardData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _FlowStep {
  const _FlowStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _FaqData {
  const _FaqData({required this.question, required this.answer});

  final String question;
  final String answer;
}
