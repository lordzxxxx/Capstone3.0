import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/checkups/checkup.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_list.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Standalone Navigation Drawer for the Mobile Dashboard.
class DashboardNavigationDrawer extends StatelessWidget {
  final User? user;
  final bool isLoggedIn;
  final bool isOfflineMode;
  final Widget Function(
    BuildContext context, {
    required User? user,
    required bool isLoggedIn,
  })
  buildProfileCard;
  final VoidCallback onSignOut;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onSelectAnalytics;

  const DashboardNavigationDrawer({
    super.key,
    required this.user,
    required this.isLoggedIn,
    required this.isOfflineMode,
    required this.buildProfileCard,
    required this.onSignOut,
    required this.onSignIn,
    required this.onSignUp,
    required this.onSelectAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 336,
      child: Drawer(
        backgroundColor: AppDesign.canvas,
        elevation: 0,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              buildProfileCard(context, user: user, isLoggedIn: isLoggedIn),
              const SizedBox(height: 12),
              _buildDrawerSection(
                icon: Icons.local_hospital_rounded,
                title: 'Patient Management',
                subtitle: 'Daily clinical workflows and care tracking',
                child: GridView.count(
                  crossAxisCount: 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  childAspectRatio: 6.1,
                  children: [
                    _buildSquareButton(
                      icon: Icons.medical_services_rounded,
                      label: 'Check Up',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const CheckUpPage(),
                          ),
                        );
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.healing_rounded,
                      label: 'Morbidity',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const MorbidityListPage(),
                          ),
                        );
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.pregnant_woman_rounded,
                      label: 'Prenatal Care',
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.toNamed(MobileRoutes.prenatal);
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.vaccines_rounded,
                      label: 'Immunization',
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.toNamed(MobileRoutes.immunization);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildDrawerSection(
                icon: Icons.folder_copy_rounded,
                title: 'Records Hub',
                subtitle: 'Community registries and patient files',
                child: GridView.count(
                  crossAxisCount: 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  childAspectRatio: 6.1,
                  children: [
                    _buildSquareButton(
                      icon: Icons.folder_special_rounded,
                      label: 'Patient Records',
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.toNamed(MobileRoutes.patients);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildDrawerSection(
                icon: Icons.monitor_heart_rounded,
                title: 'Disease Monitoring',
                subtitle: 'Population health surveillance and outcomes',
                child: GridView.count(
                  crossAxisCount: 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  childAspectRatio: 6.1,
                  children: [
                    _buildSquareButton(
                      icon: Icons.coronavirus_rounded,
                      label: 'Communicable Disease',
                      onTap: () {
                        Navigator.pop(context);
                        Get.toNamed(MobileRoutes.communicable);
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.sick_rounded,
                      label: 'Non Communicable Disease',
                      onTap: () {
                        Navigator.pop(context);
                        Get.toNamed(MobileRoutes.nonCommunicable);
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.airline_seat_flat_rounded,
                      label: 'Mortality',
                      onTap: () {
                        Navigator.pop(context);
                        Get.toNamed(MobileRoutes.mortality);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildDrawerSection(
                icon: Icons.hub_rounded,
                title: 'Insights & Coordination',
                subtitle: 'Open mobile analytics and referral workflows',
                child: GridView.count(
                  crossAxisCount: 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  childAspectRatio: 6.1,
                  children: [
                    _buildSquareButton(
                      icon: Icons.analytics_rounded,
                      label: 'Analytics',
                      onTap: () {
                        Navigator.pop(context);
                        onSelectAnalytics();
                      },
                    ),
                    _buildSquareButton(
                      icon: Icons.forward_to_inbox_rounded,
                      label: 'Referrals',
                      onTap: () {
                        Navigator.pop(context);
                        Get.toNamed(MobileRoutes.referrals);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildDrawerSection(
                icon: isLoggedIn
                    ? Icons.verified_user_rounded
                    : Icons.login_rounded,
                title: isLoggedIn ? 'Account Access' : 'Ready To Sync',
                subtitle: isLoggedIn
                    ? 'Manage your authenticated mobile session'
                    : isOfflineMode
                    ? 'Sign in or create an account to upload offline records'
                    : 'Sign in or create an account to unlock synced cloud access',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isLoggedIn ? onSignOut : onSignIn,
                        icon: Icon(
                          isLoggedIn ? Icons.logout : Icons.login,
                          size: 20,
                        ),
                        label: Text(isLoggedIn ? 'Sign Out' : 'Sign In'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLoggedIn
                              ? Colors.red.shade700
                              : AppDesign.blue,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor:
                              (isLoggedIn
                                      ? Colors.red.shade700
                                      : AppDesign.blue)
                                  .withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    if (!isLoggedIn) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: onSignUp,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Create Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppDesign.navy,
                            side: BorderSide(
                              color: AppDesign.blue.withValues(alpha: 0.55),
                              width: 1.4,
                            ),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesign.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppDesign.blueSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppDesign.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppDesign.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppDesign.muted,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppDesign.blue,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppDesign.blueSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesign.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppDesign.subtle),
            ],
          ),
        ),
      ),
    );
  }
}
