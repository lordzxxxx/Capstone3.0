import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_clinical_ui.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Standalone Hub Tab View presenting all healthcare categories and modules
/// with 100% consistent card styling, icon colors, and container backgrounds
/// matching the Analytics Tab Hub.
class ModulesHubView extends StatelessWidget {
  final VoidCallback? onSelectAnalytics;

  const ModulesHubView({super.key, this.onSelectAnalytics});

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
      padding: const EdgeInsets.only(top: 20, bottom: 28),
      child: MobilePageInsets(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClinicalSectionHeader(
              title: 'Care workspace',
              subtitle: 'Open a workflow with one focused tap.',
              icon: Icons.grid_view_rounded,
            ),
            const SizedBox(height: 20),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: hubCategories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final category = hubCategories[index];
                final buttons =
                    category['buttons'] as List<Map<String, dynamic>>;
                return ClinicalGlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppDesign.blueSoft,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              category['icon'] as IconData,
                              color: AppDesign.navy,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category['title'] as String,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  category['subtitle'] as String,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: buttons.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, buttonIndex) {
                          final button = buttons[buttonIndex];
                          return ClinicalDestinationTile(
                            icon: button['icon'] as IconData,
                            label: button['label'] as String,
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
      ),
    );
  }
}

class _HubWorkflowTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HubWorkflowTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppDesign.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesign.canvas,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Semantics(
          button: true,
          label: 'Open $label',
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppDesign.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppDesign.subtle,
                    size: 22,
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
