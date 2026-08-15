import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/features/auth/cho_access_session.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:get/get.dart';

class ChoNavigationDrawer extends StatelessWidget {
  const ChoNavigationDrawer({super.key, required this.current});

  final ChoDestination current;
  static bool _navigationInProgress = false;
  static bool _logoutInProgress = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      width: 310,
      backgroundColor: ChoColors.navBackground,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ChoColors.aqua.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/newlogo_white.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
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
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI-DSUHIS',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: ChoColors.navText,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'City Health Office Portal',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: ChoColors.navMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ChoColors.navSurface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: ChoColors.navBackground,
                      child: Icon(Icons.person, color: ChoColors.aqua),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.email?.split('@').first ?? 'CHO Staff',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              color: ChoColors.navText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'CHO • City-wide operations',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              color: ChoColors.navMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                children: [
                  _section('OVERVIEW'),
                  _item(
                    ChoDestination.dashboard,
                    'Dashboard',
                    Icons.dashboard_outlined,
                  ),
                  _section('HEALTH PROGRAMS'),
                  _item(
                    ChoDestination.patients,
                    'Patients',
                    Icons.people_alt_outlined,
                  ),
                  _item(
                    ChoDestination.checkups,
                    'Check-ups',
                    Icons.medical_services_outlined,
                  ),
                  _item(
                    ChoDestination.prenatal,
                    'Prenatal',
                    Icons.pregnant_woman_rounded,
                  ),
                  _item(
                    ChoDestination.immunization,
                    'Immunization',
                    Icons.vaccines_outlined,
                  ),
                  _item(
                    ChoDestination.morbidity,
                    'Morbidity',
                    Icons.monitor_heart_outlined,
                  ),
                  _item(
                    ChoDestination.mortality,
                    'Mortality',
                    Icons.heart_broken_outlined,
                  ),
                  _item(
                    ChoDestination.referrals,
                    'Referrals',
                    Icons.outbound_outlined,
                  ),
                  _section('COORDINATION'),
                  _item(
                    ChoDestination.bhwManagement,
                    'BHW Management',
                    Icons.groups_2_outlined,
                  ),
                  _item(
                    ChoDestination.reports,
                    'Reports',
                    Icons.summarize_outlined,
                  ),
                  _item(
                    ChoDestination.announcements,
                    'Announcements',
                    Icons.campaign_outlined,
                  ),
                  _section('GOVERNANCE'),
                  _item(
                    ChoDestination.dataQuality,
                    'Data Quality',
                    Icons.rule_folder_outlined,
                  ),
                  _item(
                    ChoDestination.auditLogs,
                    'Audit Logs',
                    Icons.history_rounded,
                  ),
                  _item(
                    ChoDestination.notifications,
                    'Notifications',
                    Icons.notifications_outlined,
                  ),
                  _item(
                    ChoDestination.profile,
                    'Profile and Settings',
                    Icons.manage_accounts_outlined,
                  ),
                ],
              ),
            ),
            Builder(builder: _logoutButton),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 7),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: 'Manrope',
        color: ChoColors.navMuted,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _logoutButton(BuildContext drawerContext) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ChoColors.navBorder)),
    ),
    child: Semantics(
      button: true,
      label: 'Log out of the CHO portal',
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

  Future<void> _confirmAndLogout(BuildContext drawerContext) async {
    if (_logoutInProgress) return;
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

    _logoutInProgress = true;
    final rootNavigator = Navigator.of(drawerContext, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(drawerContext);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    Navigator.of(drawerContext).pop();
    try {
      ChoAccessSession.trustedUid = null;
      UserAccessScopeService.instance.clearCachedScope(userId: userId);
      await FirebaseAuth.instance.signOut();
      _navigationInProgress = false;
      if (!rootNavigator.mounted) return;
      rootNavigator.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: WebRoutes.login),
          builder: (_) => const Login(),
        ),
        (_) => false,
      );
    } catch (_) {
      if (messenger != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Logout failed. Please check your connection and try again.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _logoutInProgress = false;
    }
  }

  Widget _item(ChoDestination destination, String label, IconData icon) {
    final selected = destination == current;
    // Use the same explicit active treatment as the BHW drawer. CHO and BHW
    // have different permissions, but their navigation must communicate
    // selection in the same way.
    final foreground = selected ? Colors.white : ChoColors.navText;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label navigation item',
      child: Tooltip(
        message: label,
        child: Builder(
          builder: (itemContext) => Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: selected ? ChoColors.aqua : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                hoverColor: ChoColors.aqua.withValues(alpha: 0.18),
                onTap: () => _navigateFromDrawer(
                  itemContext,
                  destination,
                  selected: selected,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: foreground),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              color: foreground,
                              fontSize: 13,
                              height: 1.15,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selected)
                          const SizedBox(
                            width: 4,
                            height: 24,
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
      ),
    );
  }

  void _navigateFromDrawer(
    BuildContext context,
    ChoDestination destination, {
    required bool selected,
  }) {
    if (_navigationInProgress) return;
    if (selected) {
      Navigator.of(context).pop();
      return;
    }

    _navigationInProgress = true;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      try {
        if (!rootNavigator.mounted) return;
        Get.offNamed(WebRoutes.choDestination(destination));
      } finally {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          _navigationInProgress = false;
        });
      }
    });
  }
}
