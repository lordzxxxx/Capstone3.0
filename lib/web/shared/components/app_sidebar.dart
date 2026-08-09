import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_profile.dart';
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
import 'package:mycapstone_project/web/shared/widgets/sidebar_page_transition.dart';

abstract final class _BhwDrawerColors {
  static const background = Color(0xFF071A33);
  static const surface = Color(0xFF0D274D);
  static const surfaceAlt = Color(0xFF163B66);
  static const border = Color(0xFF1C3D66);
  static const aqua = Color(0xFF4EA1FF);
  static const text = Color(0xFFF8FBFF);
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

class WebAppSidebar extends StatelessWidget {
  final String userName;
  final WebSidebarItem activeItem;

  const WebAppSidebar({
    super.key,
    required this.userName,
    required this.activeItem,
  });

  static bool _logoutInProgress = false;

  @override
  Widget build(BuildContext context) {
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
        return Drawer(
          width: 310,
          backgroundColor: _BhwDrawerColors.background,
          child: SafeArea(
            child: Column(
              children: [
                _buildBrandHeader(),
                _buildUserCard(userName, assignedBarangay),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                    children: [
                      _buildSectionHeader('OVERVIEW'),
                      _buildSidebarItem(
                        icon: Icons.dashboard_outlined,
                        label: 'Dashboard',
                        isActive: activeItem == WebSidebarItem.dashboard,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.dashboard,
                          () => const HomePage(),
                        ),
                      ),
                      _buildSectionHeader('PATIENT SERVICES'),
                      _buildSidebarItem(
                        icon: Icons.people_alt_outlined,
                        label: 'Patient Records',
                        isActive: activeItem == WebSidebarItem.patientRecords,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.patientRecords,
                          () => const PatientRecordPage(),
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.medical_services_outlined,
                        label: 'Check-ups',
                        isActive: activeItem == WebSidebarItem.checkups,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.checkups,
                          () => const checkup_page.CheckUpPage(),
                          routeName: '/checkups',
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.pregnant_woman_rounded,
                        label: 'Prenatal',
                        isActive: activeItem == WebSidebarItem.prenatalCare,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.prenatalCare,
                          () => const PrenatalPage(),
                          routeName: '/prenatal',
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.vaccines_outlined,
                        label: 'Immunization',
                        isActive: activeItem == WebSidebarItem.immunization,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.immunization,
                          () => const ImmunizationPage(),
                        ),
                      ),
                      _buildSectionHeader('CASE MONITORING'),
                      _buildSidebarItem(
                        icon: Icons.coronavirus_outlined,
                        label: 'Communicable',
                        isActive: activeItem == WebSidebarItem.communicable,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.communicable,
                          () => const CommunicablePage(),
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.health_and_safety_outlined,
                        label: 'Non-Communicable',
                        isActive: activeItem == WebSidebarItem.nonCommunicable,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.nonCommunicable,
                          () => const NonCommunicablePage(),
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.monitor_heart_outlined,
                        label: 'Morbidity',
                        isActive: activeItem == WebSidebarItem.morbidity,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.morbidity,
                          () => const MorbidityPage(),
                          routeName: '/morbidity',
                        ),
                      ),
                      _buildSidebarItem(
                        icon: Icons.heart_broken_outlined,
                        label: 'Mortality',
                        isActive: activeItem == WebSidebarItem.mortality,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.mortality,
                          () => const MortalityPage(),
                          routeName: '/mortality',
                        ),
                      ),
                      _buildSectionHeader('COORDINATION'),
                      _buildSidebarItem(
                        icon: Icons.outbound_outlined,
                        label: 'Referrals',
                        isActive: activeItem == WebSidebarItem.referrals,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.referrals,
                          () => const BhwReferralPage(),
                        ),
                      ),
                      _buildSectionHeader('ACCOUNT'),
                      _buildSidebarItem(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Profile and Settings',
                        isActive: activeItem == WebSidebarItem.profile,
                        onTap: _navigateTo(
                          context,
                          WebSidebarItem.profile,
                          () => const BHWProfilePage(),
                          routeName: '/bhw-profile',
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(builder: _buildLogoutButton),
              ],
            ),
          ),
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

      if (navigator.canPop()) {
        navigator.pop();
      }
      if (activeItem == targetItem) return;

      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!navigator.mounted) return;

      await navigator.push(
        buildSidebarPageRoute(
          page: pageBuilder(),
          begin: _pageOffsetFor(targetItem),
          routeName: routeName,
        ),
      );
    };
  }

  Offset _pageOffsetFor(WebSidebarItem targetItem) {
    final activeIndex = WebSidebarItem.values.indexOf(activeItem);
    final targetIndex = WebSidebarItem.values.indexOf(targetItem);

    if (targetIndex == activeIndex) {
      return Offset.zero;
    }

    return Offset(targetIndex > activeIndex ? 0.08 : -0.08, 0);
  }

  Widget _buildBrandHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _BhwDrawerColors.aqua.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.all(7),
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
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI-DSUHIS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: _BhwDrawerColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(
                'Barangay Health Worker Portal',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: _BhwDrawerColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildUserCard(String userName, String assignedBarangay) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _BhwDrawerColors.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: _BhwDrawerColors.surfaceAlt,
            child: Icon(Icons.person, color: _BhwDrawerColors.aqua),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: _BhwDrawerColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'BHW • $assignedBarangay',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: _BhwDrawerColors.muted,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 7),
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
    bool isActive = false,
  }) {
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label navigation item',
      child: ListTile(
        selected: isActive,
        selectedColor: _BhwDrawerColors.text,
        textColor: _BhwDrawerColors.text,
        iconColor: isActive ? _BhwDrawerColors.aqua : _BhwDrawerColors.text,
        leading: Icon(icon, size: 20),
        title: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        tileColor: isActive
            ? _BhwDrawerColors.aqua.withValues(alpha: 0.24)
            : null,
        hoverColor: _BhwDrawerColors.aqua.withValues(alpha: 0.12),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext drawerContext) {
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
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndLogout(BuildContext drawerContext) async {
    if (_logoutInProgress) return;
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
          style: TextStyle(fontFamily: 'Inter', color: _BhwDrawerColors.text),
        ),
        content: const Text(
          'You will need to sign in again to access your assigned barangay records.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
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

    _logoutInProgress = true;
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
          settings: const RouteSettings(name: '/login'),
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
      _logoutInProgress = false;
    }
  }
}
