import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_profile.dart';
import 'package:mycapstone_project/web/roles/bhw/analytics/bhw_analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/widgets/sidebar_page_transition.dart';
import 'package:mycapstone_project/web/shared/navigation/web_navigation_coordinator.dart';
import 'package:mycapstone_project/web/shared/widgets/bhw_notifications.dart';
import 'package:mycapstone_project/web/shared/widgets/bhw_apk_download_action.dart';
import 'package:mycapstone_project/web/shared/components/web_navigation_item.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:get/get.dart';

abstract final class _BhwDrawerColors {
  static const background = AppColors.backgroundDark;
  static const surface = AppColors.surfaceDark;
  static const surfaceAlt = AppColors.secondary;
  static const border = Color(0xFF1C3D66);
  static const aqua = AppColors.primary;
  static const text = AppColors.textOnDark;
  static const muted = Color(0xFFE3EDF8);
}

enum WebSidebarItem {
  dashboard,
  profile,
  referrals,
  checkups,
  summaryGeneration,
  analytics,
  prenatalCare,
  immunization,
  patientRecords,
  communicable,
  nonCommunicable,
  morbidity,
  mortality,
}

class WebAppSidebar extends StatefulWidget {
  final String userName;
  final WebSidebarItem activeItem;

  /// Drawer instances on phones should show labels even though the viewport
  /// itself is compact.
  final bool forceExpanded;

  const WebAppSidebar({
    super.key,
    required this.userName,
    required this.activeItem,
    this.forceExpanded = false,
  });

  /// Globally persisted collapsed preference during session.
  static final ValueNotifier<bool> isCollapsedNotifier = ValueNotifier<bool>(
    false,
  );

  static bool _logoutInProgress = false;

  @override
  State<WebAppSidebar> createState() => _WebAppSidebarState();
}

class _WebAppSidebarState extends State<WebAppSidebar> {
  late Future<UserAccessScope?> _scopeFuture;

  @override
  void initState() {
    super.initState();
    // Do not create a new Firestore-backed future on every rebuild. Hover,
    // collapse, and pressed-state updates should never refetch user scope.
    _scopeFuture = UserAccessScopeService.instance.loadCurrentScope();
  }

  void _toggleCollapse() {
    WebAppSidebar.isCollapsedNotifier.value =
        !WebAppSidebar.isCollapsedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WebAppSidebar.isCollapsedNotifier,
      builder: (context, isCollapsed, _) {
        // Keep the content usable when the browser is narrower than a normal
        // desktop. The user can still expand the rail later on a wide screen,
        // but narrow screens never lose their main working area to the nav.
        final compactViewport = MediaQuery.sizeOf(context).width < 1180;
        final effectiveCollapsed =
            !widget.forceExpanded && (isCollapsed || compactViewport);
        return FutureBuilder<UserAccessScope?>(
          future: _scopeFuture,
          builder: (context, scopeSnapshot) {
            final scope = scopeSnapshot.data;
            final assignedBarangay = [scope?.barangay, scope?.barangayCode]
                .whereType<String>()
                .firstWhere(
                  (value) => value.trim().isNotEmpty,
                  orElse: () => 'Barangay assignment unavailable',
                );

            // The rail stays in the page layout while the content route
            // changes. Disable Hero flights so navigation never animates or
            // carries the sidebar with the destination page.
            return HeroMode(
              enabled: false,
              child: Hero(
                tag: 'web_app_sidebar',
                flightShuttleBuilder:
                    (
                      flightContext,
                      animation,
                      flightDirection,
                      fromHeroContext,
                      toHeroContext,
                    ) {
                      return Material(
                        type: MaterialType.transparency,
                        child: toHeroContext.widget,
                      );
                    },
                child: Material(
                  type: MaterialType.transparency,
                  child: AnimatedContainer(
                    // Snap to the compact rail when the browser crosses the
                    // responsive breakpoint. Animating 300 -> 76 while the
                    // viewport is already narrow briefly leaves the page only
                    // a few pixels wide and causes otherwise-correct rows to
                    // overflow during a browser resize.
                    duration: compactViewport
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeInOutCubic,
                    width: effectiveCollapsed ? 76.0 : 300.0,
                    height: double.infinity,
                    decoration: const BoxDecoration(
                      color: _BhwDrawerColors.background,
                      border: Border(
                        right: BorderSide(
                          color: _BhwDrawerColors.border,
                          width: 1,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(2, 0),
                        ),
                      ],
                    ),
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: effectiveCollapsed ? 76.0 : 300.0,
                            maxWidth: effectiveCollapsed ? 76.0 : 300.0,
                            minHeight: constraints.maxHeight,
                            maxHeight: constraints.maxHeight,
                            child: SafeArea(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildBrandHeader(effectiveCollapsed),
                                  _buildUserSection(
                                    widget.userName,
                                    assignedBarangay,
                                    effectiveCollapsed,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: effectiveCollapsed ? 8 : 10,
                                        vertical: 4,
                                      ),
                                      children: [
                                        _buildSectionHeader(
                                          'OVERVIEW',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.dashboard_outlined,
                                          label: 'Dashboard',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.dashboard,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.dashboard,
                                            () => const HomePage(),
                                            routeName: WebRoutes.bhwDashboard,
                                          ),
                                        ),
                                        _buildSectionHeader(
                                          'PATIENT SERVICES',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.people_alt_outlined,
                                          label: 'Patient Records',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.patientRecords,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.patientRecords,
                                            () => const PatientRecordPage(),
                                            routeName: WebRoutes.bhwPatients,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.medical_services_outlined,
                                          label: 'Check-ups',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.checkups,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.checkups,
                                            () =>
                                                const checkup_page.CheckUpPage(),
                                            routeName: WebRoutes.bhwCheckups,
                                          ),
                                        ),
                                        _buildSectionHeader(
                                          'INSIGHTS',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.auto_graph_rounded,
                                          label: 'Summary Generation',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.summaryGeneration,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.summaryGeneration,
                                            () => const HealthMetricsPage(),
                                            routeName: WebRoutes.bhwSummary,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.insights_rounded,
                                          label: 'Analytics',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.analytics,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.analytics,
                                            () => const BHWAnalyticsPage(),
                                            routeName: WebRoutes.bhwAnalytics,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.pregnant_woman_rounded,
                                          label: 'Prenatal',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.prenatalCare,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.prenatalCare,
                                            () => const PrenatalPage(),
                                            routeName: WebRoutes.bhwPrenatal,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.vaccines_outlined,
                                          label: 'Immunization',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.immunization,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.immunization,
                                            () => const ImmunizationPage(),
                                            routeName:
                                                WebRoutes.bhwImmunization,
                                          ),
                                        ),
                                        _buildSectionHeader(
                                          'CASE MONITORING',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.coronavirus_outlined,
                                          label: 'Communicable',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.communicable,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.communicable,
                                            () => const CommunicablePage(),
                                            routeName:
                                                WebRoutes.bhwCommunicable,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon:
                                              Icons.health_and_safety_outlined,
                                          label: 'Non-Communicable',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.nonCommunicable,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.nonCommunicable,
                                            () => const NonCommunicablePage(),
                                            routeName:
                                                WebRoutes.bhwNonCommunicable,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.monitor_heart_outlined,
                                          label: 'Morbidity',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.morbidity,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.morbidity,
                                            () => const MorbidityPage(),
                                            routeName: WebRoutes.bhwMorbidity,
                                          ),
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.heart_broken_outlined,
                                          label: 'Mortality',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.mortality,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.mortality,
                                            () => const MortalityPage(),
                                            routeName: WebRoutes.bhwMortality,
                                          ),
                                        ),
                                        _buildSectionHeader(
                                          'COORDINATION',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.outbound_outlined,
                                          label: 'Referrals',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.referrals,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.referrals,
                                            () => const BhwReferralPage(),
                                            routeName: WebRoutes.bhwReferrals,
                                          ),
                                        ),
                                        _buildSectionHeader(
                                          'ACCOUNT',
                                          effectiveCollapsed,
                                        ),
                                        _buildSidebarUtilityItem(
                                          icon:
                                              Icons.notifications_none_rounded,
                                          label: 'Notifications',
                                          isCollapsed: effectiveCollapsed,
                                          onTap: () => showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                const BhwNotificationsDialog(),
                                          ),
                                        ),
                                        BhwApkDownloadAction(
                                          isCollapsed: effectiveCollapsed,
                                        ),
                                        _buildSidebarItem(
                                          icon: Icons.manage_accounts_outlined,
                                          label: 'Profile and Settings',
                                          isActive:
                                              widget.activeItem ==
                                              WebSidebarItem.profile,
                                          isCollapsed: effectiveCollapsed,
                                          onTap: _navigateTo(
                                            context,
                                            WebSidebarItem.profile,
                                            () => const BHWProfilePage(),
                                            routeName: WebRoutes.bhwProfile,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildLogoutButton(
                                    context,
                                    effectiveCollapsed,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  VoidCallback _navigateTo(
    BuildContext context,
    WebSidebarItem targetItem,
    Widget Function() pageBuilder, {
    String? routeName,
  }) {
    return () async {
      if (widget.activeItem == targetItem) return;
      await WebNavigationCoordinator.run(context, () async {
        if (routeName != null) {
          final navigation = Get.offNamed<void>(routeName);
          if (navigation != null) await navigation;
          return;
        }

        await Navigator.of(context).pushReplacement(
          buildSidebarPageRoute(
            page: pageBuilder(),
            begin: Offset.zero,
            routeName: routeName,
          ),
        );
      });
    };
  }

  Widget _buildBrandHeader(bool isCollapsed) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _BhwDrawerColors.aqua.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                'assets/newlogo_white.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Text(
                    'AI',
                    style: TextStyle(
                      color: _BhwDrawerColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            IconButton(
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 22,
              ),
              tooltip: 'Expand Menu',
              onPressed: _toggleCollapse,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _BhwDrawerColors.aqua.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              'assets/newlogo_white.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text(
                  'AI',
                  style: TextStyle(
                    color: _BhwDrawerColors.text,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AI-DSUHIS',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: _BhwDrawerColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Barangay Health Portal',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: _BhwDrawerColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white70,
              size: 22,
            ),
            tooltip: 'Minimize Menu',
            onPressed: _toggleCollapse,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSection(
    String userName,
    String assignedBarangay,
    bool isCollapsed,
  ) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Tooltip(
          message: '$userName\nBHW • $assignedBarangay',
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _BhwDrawerColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: CircleAvatar(
                radius: 16,
                backgroundColor: _BhwDrawerColors.surfaceAlt,
                child: Icon(
                  Icons.person,
                  color: _BhwDrawerColors.aqua,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _BhwDrawerColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: _BhwDrawerColors.surfaceAlt,
              child: Icon(Icons.person, color: _BhwDrawerColors.aqua, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      userName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: _BhwDrawerColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'BHW • $assignedBarangay',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: _BhwDrawerColors.muted,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isCollapsed) {
    if (isCollapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Divider(color: _BhwDrawerColors.border, height: 1, thickness: 1),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: ClipRect(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: _BhwDrawerColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isCollapsed,
    bool isActive = false,
  }) {
    return WebNavigationItem(
      icon: icon,
      label: label,
      onTap: onTap,
      isCollapsed: isCollapsed,
      isActive: isActive,
    );
  }

  Widget _buildSidebarUtilityItem({
    required IconData icon,
    required String label,
    required bool isCollapsed,
    required VoidCallback onTap,
  }) {
    return WebNavigationItem(
      icon: icon,
      label: label,
      onTap: onTap,
      isCollapsed: isCollapsed,
      tooltip: label,
    );
  }

  Widget _buildLogoutButton(BuildContext drawerContext, bool isCollapsed) {
    return _AnimatedLogoutButton(
      isCollapsed: isCollapsed,
      onTap: () => _confirmAndLogout(drawerContext),
    );
  }

  Future<void> _confirmAndLogout(BuildContext drawerContext) async {
    if (WebAppSidebar._logoutInProgress) return;
    final confirmed = await showDialog<bool>(
      context: drawerContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        icon: const Icon(
          Icons.logout_rounded,
          color: Colors.redAccent,
          size: 34,
        ),
        title: const Text(
          'Logout from BHW Portal?',
          style: TextStyle(fontFamily: 'Manrope', color: AppColors.textPrimary),
        ),
        content: const Text(
          'You will need to sign in again to access patient records.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Manrope',
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !drawerContext.mounted) return;

    WebAppSidebar._logoutInProgress = true;
    final rootNavigator = Navigator.of(drawerContext, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(drawerContext);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    try {
      UserAccessScopeService.instance.clearCachedScope(userId: userId);
      await FirebaseAuth.instance.signOut();
      if (!rootNavigator.mounted) return;
      rootNavigator.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: WebRoutes.login),
          builder: (_) => const Login(),
        ),
        (_) => false,
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Logout failed. Please check your connection and try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      WebAppSidebar._logoutInProgress = false;
    }
  }
}

class _SidebarAnimatedItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isCollapsed;
  final bool isActive;
  final Color activeColor;
  final Color inactiveTextColor;
  final Color hoverColor;

  const _SidebarAnimatedItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isCollapsed,
  }) : isActive = false,
       activeColor = _BhwDrawerColors.aqua,
       inactiveTextColor = _BhwDrawerColors.text,
       hoverColor = const Color(0x2600C0A3);

  @override
  State<_SidebarAnimatedItem> createState() => _SidebarAnimatedItemState();
}

class _SidebarAnimatedItemState extends State<_SidebarAnimatedItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isActive
        ? Colors.white
        : (_isHovered
              ? Colors.white
              : widget.inactiveTextColor.withValues(alpha: 0.92));

    final backgroundColor = widget.isActive
        ? widget.activeColor
        : (_isHovered ? widget.hoverColor : Colors.transparent);

    final scale = _isPressed ? 0.95 : (_isHovered ? 1.01 : 1.0);
    final translationX = (!widget.isCollapsed && _isHovered && !widget.isActive)
        ? 3.0
        : 0.0;

    if (widget.isCollapsed) {
      return Semantics(
        button: true,
        selected: widget.isActive,
        label: '${widget.label} navigation item',
        child: Tooltip(
          message: widget.label,
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 80),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) async {
                setState(() => _isPressed = false);
                await Future<void>.delayed(const Duration(milliseconds: 60));
                widget.onTap();
              },
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  height: 44,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: widget.isActive
                        ? [
                            BoxShadow(
                              color: widget.activeColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: widget.isActive || _isHovered ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(widget.icon, size: 22, color: foreground),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      selected: widget.isActive,
      label: '${widget.label} navigation item',
      child: Tooltip(
        message: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) async {
              setState(() => _isPressed = false);
              await Future<void>.delayed(const Duration(milliseconds: 60));
              widget.onTap();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: Offset(translationX / 300.0, 0),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  constraints: const BoxConstraints(minHeight: 46),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: widget.isActive
                        ? [
                            BoxShadow(
                              color: widget.activeColor.withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : (_isHovered
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: widget.isActive ? 4 : 0,
                          height: widget.isActive ? 22 : 0,
                          margin: EdgeInsets.only(
                            right: widget.isActive ? 8 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        AnimatedScale(
                          scale: widget.isActive || _isHovered ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          child: Icon(widget.icon, size: 20, color: foreground),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRect(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                color: foreground,
                                fontSize: 13,
                                height: 1.15,
                                fontWeight: widget.isActive
                                    ? FontWeight.w800
                                    : (_isHovered
                                          ? FontWeight.w700
                                          : FontWeight.w600),
                              ),
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: widget.isActive ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 160),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
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
        ),
      ),
    );
  }
}

class _AnimatedLogoutButton extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback onTap;

  const _AnimatedLogoutButton({required this.isCollapsed, required this.onTap});

  @override
  State<_AnimatedLogoutButton> createState() => _AnimatedLogoutButtonState();
}

class _AnimatedLogoutButtonState extends State<_AnimatedLogoutButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.01 : 1.0);

    if (widget.isCollapsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _BhwDrawerColors.border)),
        ),
        child: Tooltip(
          message: 'Logout',
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) async {
                setState(() => _isPressed = false);
                await Future<void>.delayed(const Duration(milliseconds: 60));
                widget.onTap();
              },
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: _isHovered ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(
                        alpha: _isHovered ? 0.6 : 0.2,
                      ),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _BhwDrawerColors.border)),
      ),
      child: Semantics(
        button: true,
        label: 'Log out of the BHW portal',
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) async {
              setState(() => _isPressed = false);
              await Future<void>.delayed(const Duration(milliseconds: 60));
              widget.onTap();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: _isHovered ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.red.withValues(
                      alpha: _isHovered ? 0.55 : 0.35,
                    ),
                  ),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 19,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
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
}
