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

  const WebAppSidebar({
    super.key,
    required this.userName,
    required this.activeItem,
  });

  /// Globally persisted collapsed preference during session.
  static final ValueNotifier<bool> isCollapsedNotifier =
      ValueNotifier<bool>(false);

  static bool _logoutInProgress = false;

  @override
  State<WebAppSidebar> createState() => _WebAppSidebarState();
}

class _WebAppSidebarState extends State<WebAppSidebar> {
  void _toggleCollapse() {
    WebAppSidebar.isCollapsedNotifier.value =
        !WebAppSidebar.isCollapsedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WebAppSidebar.isCollapsedNotifier,
      builder: (context, isCollapsed, _) {
        return FutureBuilder(
          future: UserAccessScopeService.instance.loadCurrentScope(),
          builder: (context, scopeSnapshot) {
            final scope = scopeSnapshot.data;
            final assignedBarangay = [scope?.barangay, scope?.barangayCode]
                .whereType<String>()
                .firstWhere(
                  (value) => value.trim().isNotEmpty,
                  orElse: () => 'Barangay assignment unavailable',
                );

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              width: isCollapsed ? 76.0 : 300.0,
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
                child: SizedBox(
                  width: isCollapsed ? 76.0 : 300.0,
                  height: double.infinity,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBrandHeader(isCollapsed),
                        _buildUserSection(
                          widget.userName,
                          assignedBarangay,
                          isCollapsed,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCollapsed ? 8 : 10,
                              vertical: 4,
                            ),
                            children: [
                            _buildSectionHeader('OVERVIEW', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.dashboard_outlined,
                              label: 'Dashboard',
                              isActive:
                                  widget.activeItem == WebSidebarItem.dashboard,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.dashboard,
                                () => const HomePage(),
                                routeName: WebRoutes.bhwDashboard,
                              ),
                            ),
                            _buildSectionHeader('PATIENT SERVICES', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.people_alt_outlined,
                              label: 'Patient Records',
                              isActive:
                                  widget.activeItem ==
                                  WebSidebarItem.patientRecords,
                              isCollapsed: isCollapsed,
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
                                  widget.activeItem == WebSidebarItem.checkups,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.checkups,
                                () => const checkup_page.CheckUpPage(),
                                routeName: WebRoutes.bhwCheckups,
                              ),
                            ),
                            _buildSectionHeader('INSIGHTS', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.auto_graph_rounded,
                              label: 'Summary Generation',
                              isActive:
                                  widget.activeItem ==
                                  WebSidebarItem.summaryGeneration,
                              isCollapsed: isCollapsed,
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
                                  widget.activeItem == WebSidebarItem.analytics,
                              isCollapsed: isCollapsed,
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
                              isCollapsed: isCollapsed,
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
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.immunization,
                                () => const ImmunizationPage(),
                                routeName: WebRoutes.bhwImmunization,
                              ),
                            ),
                            _buildSectionHeader('CASE MONITORING', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.coronavirus_outlined,
                              label: 'Communicable',
                              isActive:
                                  widget.activeItem ==
                                  WebSidebarItem.communicable,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.communicable,
                                () => const CommunicablePage(),
                                routeName: WebRoutes.bhwCommunicable,
                              ),
                            ),
                            _buildSidebarItem(
                              icon: Icons.health_and_safety_outlined,
                              label: 'Non-Communicable',
                              isActive:
                                  widget.activeItem ==
                                  WebSidebarItem.nonCommunicable,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.nonCommunicable,
                                () => const NonCommunicablePage(),
                                routeName: WebRoutes.bhwNonCommunicable,
                              ),
                            ),
                            _buildSidebarItem(
                              icon: Icons.monitor_heart_outlined,
                              label: 'Morbidity',
                              isActive:
                                  widget.activeItem == WebSidebarItem.morbidity,
                              isCollapsed: isCollapsed,
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
                                  widget.activeItem == WebSidebarItem.mortality,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.mortality,
                                () => const MortalityPage(),
                                routeName: WebRoutes.bhwMortality,
                              ),
                            ),
                            _buildSectionHeader('COORDINATION', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.outbound_outlined,
                              label: 'Referrals',
                              isActive:
                                  widget.activeItem == WebSidebarItem.referrals,
                              isCollapsed: isCollapsed,
                              onTap: _navigateTo(
                                context,
                                WebSidebarItem.referrals,
                                () => const BhwReferralPage(),
                                routeName: WebRoutes.bhwReferrals,
                              ),
                            ),
                            _buildSectionHeader('ACCOUNT', isCollapsed),
                            _buildSidebarItem(
                              icon: Icons.manage_accounts_outlined,
                              label: 'Profile and Settings',
                              isActive:
                                  widget.activeItem == WebSidebarItem.profile,
                              isCollapsed: isCollapsed,
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
                      _buildLogoutButton(context, isCollapsed),
                    ],
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
      final navigator = Navigator.of(context);

      if (widget.activeItem == targetItem) return;

      if (routeName != null) {
        await Get.toNamed(routeName);
        return;
      }

      await navigator.pushReplacement(
        buildSidebarPageRoute(
          page: pageBuilder(),
          begin: _pageOffsetFor(targetItem),
          routeName: routeName,
        ),
      );
    };
  }

  Offset _pageOffsetFor(WebSidebarItem targetItem) {
    final activeIndex = WebSidebarItem.values.indexOf(widget.activeItem);
    final targetIndex = WebSidebarItem.values.indexOf(targetItem);

    if (targetIndex == activeIndex) {
      return Offset.zero;
    }

    return Offset(targetIndex > activeIndex ? 0.08 : -0.08, 0);
  }

  Widget _buildBrandHeader(bool isCollapsed) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
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
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
      child: Row(
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
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white70,
              size: 22,
            ),
            tooltip: 'Minimize Menu',
            onPressed: _toggleCollapse,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            child: const CircleAvatar(
              radius: 16,
              backgroundColor: _BhwDrawerColors.surfaceAlt,
              child: Icon(Icons.person, color: _BhwDrawerColors.aqua, size: 18),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isCollapsed) {
    if (isCollapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Divider(
          color: _BhwDrawerColors.border,
          height: 1,
          thickness: 1,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Manrope',
          color: _BhwDrawerColors.muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
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
    final foreground = isActive
        ? Colors.white
        : _BhwDrawerColors.text.withValues(alpha: 0.92);

    if (isCollapsed) {
      return Semantics(
        button: true,
        selected: isActive,
        label: '$label navigation item',
        child: Tooltip(
          message: label,
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 100),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: isActive ? _BhwDrawerColors.aqua : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                hoverColor: _BhwDrawerColors.aqua.withValues(alpha: 0.18),
                onTap: onTap,
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Icon(icon, size: 22, color: foreground),
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
      selected: isActive,
      label: '$label navigation item',
      child: Tooltip(
        message: label,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? _BhwDrawerColors.aqua : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                color: isActive ? Colors.white : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              hoverColor: _BhwDrawerColors.aqua.withValues(alpha: 0.18),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 46),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: foreground),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: foreground,
                            fontSize: 13,
                            height: 1.15,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isActive)
                        const SizedBox(
                          width: 4,
                          height: 20,
                          child: ColoredBox(color: Colors.white),
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

  Widget _buildLogoutButton(BuildContext drawerContext, bool isCollapsed) {
    if (isCollapsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _BhwDrawerColors.border)),
        ),
        child: Tooltip(
          message: 'Logout',
          child: IconButton(
            onPressed: () => _confirmAndLogout(drawerContext),
            icon: const Icon(Icons.logout_rounded, size: 22),
            color: Colors.redAccent,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _confirmAndLogout(drawerContext),
            icon: const Icon(Icons.logout_rounded, size: 19),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
              backgroundColor: Colors.red.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndLogout(BuildContext drawerContext) async {
    if (WebAppSidebar._logoutInProgress) return;
    final confirmed = await showDialog<bool>(
      context: drawerContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _BhwDrawerColors.surface,
        icon: const Icon(
          Icons.logout_rounded,
          color: Colors.redAccent,
          size: 34,
        ),
        title: const Text(
          'Logout from BHW Portal?',
          style: TextStyle(fontFamily: 'Manrope', color: _BhwDrawerColors.text),
        ),
        content: const Text(
          'You will need to sign in again to access your assigned barangay records.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Manrope',
            color: _BhwDrawerColors.muted,
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
    Navigator.of(drawerContext).pop();
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
