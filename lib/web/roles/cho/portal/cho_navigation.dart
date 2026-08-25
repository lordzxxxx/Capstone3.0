import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/features/auth/cho_access_session.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/components/web_navigation_item.dart';

class ChoNavigationDrawer extends StatefulWidget {
  final ChoDestination current;

  const ChoNavigationDrawer({super.key, required this.current});

  static final ValueNotifier<bool> isCollapsedNotifier = ValueNotifier<bool>(
    false,
  );
  static bool _logoutInProgress = false;

  @override
  State<ChoNavigationDrawer> createState() => _ChoNavigationDrawerState();
}

class _ChoNavigationDrawerState extends State<ChoNavigationDrawer> {
  void _toggleCollapse() {
    ChoNavigationDrawer.isCollapsedNotifier.value =
        !ChoNavigationDrawer.isCollapsedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : user?.email?.split('@').first ?? 'CHO Staff';

    return ValueListenableBuilder<bool>(
      valueListenable: ChoNavigationDrawer.isCollapsedNotifier,
      builder: (context, isCollapsed, _) {
        final compactViewport = MediaQuery.sizeOf(context).width < 1180;
        final effectiveCollapsed = isCollapsed || compactViewport;
        return Hero(
          tag: 'cho_navigation_sidebar',
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
              duration: compactViewport
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeInOutCubic,
              width: effectiveCollapsed ? 76.0 : 300.0,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: ChoColors.navBackground,
                border: Border(
                  right: BorderSide(color: ChoColors.navBorder, width: 1),
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
                            _buildUserSection(userName, effectiveCollapsed),
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
                                    destination: ChoDestination.dashboard,
                                    label: 'Dashboard',
                                    icon: Icons.dashboard_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSectionHeader(
                                    'HEALTH PROGRAMS',
                                    effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.patients,
                                    label: 'Patients',
                                    icon: Icons.people_alt_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.checkups,
                                    label: 'Check-ups',
                                    icon: Icons.medical_services_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.prenatal,
                                    label: 'Prenatal',
                                    icon: Icons.pregnant_woman_rounded,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.immunization,
                                    label: 'Immunization',
                                    icon: Icons.vaccines_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.morbidity,
                                    label: 'Morbidity',
                                    icon: Icons.monitor_heart_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.mortality,
                                    label: 'Mortality',
                                    icon: Icons.heart_broken_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.referrals,
                                    label: 'Referrals',
                                    icon: Icons.outbound_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSectionHeader(
                                    'COORDINATION',
                                    effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.bhwManagement,
                                    label: 'BHW Management',
                                    icon: Icons.groups_2_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.reports,
                                    label: 'Reports',
                                    icon: Icons.summarize_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.announcements,
                                    label: 'Announcements',
                                    icon: Icons.campaign_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSectionHeader(
                                    'GOVERNANCE',
                                    effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.dataQuality,
                                    label: 'Data Quality',
                                    icon: Icons.rule_folder_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.auditLogs,
                                    label: 'Audit Logs',
                                    icon: Icons.history_rounded,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.notifications,
                                    label: 'Notifications',
                                    icon: Icons.notifications_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                  _buildSidebarItem(
                                    destination: ChoDestination.profile,
                                    label: 'Profile and Settings',
                                    icon: Icons.manage_accounts_outlined,
                                    isCollapsed: effectiveCollapsed,
                                  ),
                                ],
                              ),
                            ),
                            _buildLogoutButton(context, effectiveCollapsed),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
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
                color: ChoColors.aqua.withValues(alpha: 0.18),
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
                      color: ChoColors.navText,
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
              color: ChoColors.aqua.withValues(alpha: 0.18),
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
                    color: ChoColors.navText,
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
                      color: ChoColors.navText,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'City Health Office Portal',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: ChoColors.navMuted,
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

  Widget _buildUserSection(String userName, bool isCollapsed) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Tooltip(
          message: '$userName\nCHO • City-wide operations',
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ChoColors.navSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: CircleAvatar(
                radius: 16,
                backgroundColor: ChoColors.navBackground,
                child: Icon(Icons.person, color: ChoColors.aqua, size: 18),
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
          color: ChoColors.navSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: ChoColors.navBackground,
              child: Icon(Icons.person, color: ChoColors.aqua, size: 20),
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
                        color: ChoColors.navText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      'CHO • City-wide operations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: ChoColors.navMuted,
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
        child: Divider(color: ChoColors.navBorder, height: 1, thickness: 1),
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
            color: ChoColors.navMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required ChoDestination destination,
    required String label,
    required IconData icon,
    required bool isCollapsed,
  }) {
    final isSelected = destination == widget.current;
    return WebNavigationItem(
      icon: icon,
      label: label,
      isActive: isSelected,
      isCollapsed: isCollapsed,
      onTap: () => _navigateToDestination(destination),
    );
  }

  void _navigateToDestination(ChoDestination destination) {
    if (destination == widget.current) return;
    Get.offNamed(WebRoutes.choDestination(destination));
  }

  Widget _buildLogoutButton(BuildContext drawerContext, bool isCollapsed) {
    return _ChoAnimatedLogoutButton(
      isCollapsed: isCollapsed,
      onTap: () => _confirmAndLogout(drawerContext),
    );
  }

  Future<void> _confirmAndLogout(BuildContext drawerContext) async {
    if (ChoNavigationDrawer._logoutInProgress) return;
    final confirmed = await showDialog<bool>(
      context: drawerContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ChoColors.surface,
        icon: const Icon(
          Icons.logout_rounded,
          color: Colors.redAccent,
          size: 34,
        ),
        title: const Text(
          'Logout from CHO Portal?',
          style: TextStyle(fontFamily: 'Manrope', color: ChoColors.text),
        ),
        content: const Text(
          'You will need to sign in again to access city-wide health records.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Manrope',
            color: ChoColors.muted,
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

    ChoNavigationDrawer._logoutInProgress = true;
    final rootNavigator = Navigator.of(drawerContext, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(drawerContext);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    try {
      ChoAccessSession.trustedUid = null;
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
      ChoNavigationDrawer._logoutInProgress = false;
    }
  }
}

class _ChoSidebarAnimatedItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _ChoSidebarAnimatedItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  State<_ChoSidebarAnimatedItem> createState() =>
      _ChoSidebarAnimatedItemState();
}

class _ChoSidebarAnimatedItemState extends State<_ChoSidebarAnimatedItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isActive
        ? Colors.white
        : (_isHovered
              ? Colors.white
              : ChoColors.navText.withValues(alpha: 0.92));

    final backgroundColor = widget.isActive
        ? ChoColors.aqua
        : (_isHovered
              ? ChoColors.aqua.withValues(alpha: 0.15)
              : Colors.transparent);

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
                              color: ChoColors.aqua.withValues(alpha: 0.3),
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
                              color: ChoColors.aqua.withValues(alpha: 0.28),
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

class _ChoAnimatedLogoutButton extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback onTap;

  const _ChoAnimatedLogoutButton({
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  State<_ChoAnimatedLogoutButton> createState() =>
      _ChoAnimatedLogoutButtonState();
}

class _ChoAnimatedLogoutButtonState extends State<_ChoAnimatedLogoutButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.01 : 1.0);

    if (widget.isCollapsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ChoColors.navBorder)),
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
        border: Border(top: BorderSide(color: ChoColors.navBorder)),
      ),
      child: Semantics(
        button: true,
        label: 'Log out of the CHO portal',
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
