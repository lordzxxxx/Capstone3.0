import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Standalone Hub Tab View presenting all healthcare categories and modules
/// with 100% consistent card styling, icon colors, and container backgrounds
/// matching the Analytics Tab Hub.
class ModulesHubView extends StatelessWidget {
  final VoidCallback? onSelectAnalytics;

  const ModulesHubView({
    super.key,
    this.onSelectAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final hubCategories = <Map<String, dynamic>>[
      {
        'title': 'Patient Management',
        'subtitle': 'Check Up, Morbidity, Prenatal Care, Immunization',
        'icon': Icons.local_hospital_rounded,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Check Up',
            'icon': Icons.medical_services,
            'onTap': () => Get.toNamed(MobileRoutes.checkups),
          },
          {
            'label': 'Morbidity',
            'icon': Icons.healing,
            'onTap': () => Get.toNamed(MobileRoutes.morbidity),
          },
          {
            'label': 'Prenatal Care',
            'icon': Icons.pregnant_woman,
            'onTap': () => Get.toNamed(MobileRoutes.prenatal),
          },
          {
            'label': 'Immunization',
            'icon': Icons.vaccines,
            'onTap': () => Get.toNamed(MobileRoutes.immunization),
          },
        ],
      },
      {
        'title': 'Records',
        'subtitle': 'Patient Records',
        'icon': Icons.folder_copy_rounded,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Patient Records',
            'icon': Icons.folder_special,
            'onTap': () => Get.toNamed(MobileRoutes.patients),
          },
        ],
      },
      {
        'title': 'Disease Monitoring',
        'subtitle': 'Communicable Disease, Non Communicable Disease, Mortality',
        'icon': Icons.monitor_heart_rounded,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Communicable Disease',
            'icon': Icons.coronavirus,
            'onTap': () => Get.toNamed(MobileRoutes.communicable),
          },
          {
            'label': 'Non Communicable Disease',
            'icon': Icons.sick,
            'onTap': () => Get.toNamed(MobileRoutes.nonCommunicable),
          },
          {
            'label': 'Mortality',
            'icon': Icons.airline_seat_flat,
            'onTap': () => Get.toNamed(MobileRoutes.mortality),
          },
        ],
      },
      {
        'title': 'Coordination',
        'subtitle': 'Referrals',
        'icon': Icons.forward_to_inbox_rounded,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Referrals',
            'icon': Icons.forward_to_inbox_rounded,
            'onTap': () => Get.toNamed(MobileRoutes.referrals),
          },
        ],
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUB',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppDesign.ink,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a category to open the related modules.',
            style: TextStyle(color: AppDesign.muted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: hubCategories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final category = hubCategories[index];
              final buttons = category['buttons'] as List<Map<String, dynamic>>;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppDesign.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppDesign.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppDesign.navy.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category['title'] as String,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 18,
                            mainAxisSpacing: 18,
                            childAspectRatio: 1.15,
                          ),
                      itemCount: buttons.length,
                      itemBuilder: (context, buttonIndex) {
                        final button = buttons[buttonIndex];
                        return _HubIconButton(
                          icon: button['icon'] as IconData,
                          label: button['label'] as String,
                          color: AppDesign.blue,
                          onTap: button['onTap'] as VoidCallback,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HubIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppDesign.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: color.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppDesign.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
