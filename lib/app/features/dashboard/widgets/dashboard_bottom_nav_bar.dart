import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Reusable Bottom Navigation Bar for the Mobile Healthcare Dashboard.
///
/// Controls the primary tabs:
/// - Index 0: Dashboard (Home Overview)
/// - Index 1: Analytics (Charts & Population Metrics)
/// - Index 2: Hub (Healthcare Modules & Clinical Workflows)
class DashboardBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const DashboardBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(color: AppDesign.border),
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: AppDesign.surface,
          selectedItemColor: AppDesign.blue,
          unselectedItemColor: AppDesign.subtle,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          onTap: onTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.analytics_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.hub_rounded),
              label: 'Hub',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveNavigationIcon extends StatelessWidget {
  final IconData icon;
  const _ActiveNavigationIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppDesign.blueSoft,
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: Icon(icon, color: AppDesign.blue, size: 24),
    );
  }
}
