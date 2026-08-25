import 'package:flutter/material.dart';

import '../services/pwa_install.dart';
import '../theme/app_theme.dart';

/// BHW-facing install action that follows the current dark sidebar language.
/// It uses the native browser prompt when available and provides safe manual
/// instructions on browsers that do not expose that prompt.
class BhwPwaInstallAction extends StatelessWidget {
  const BhwPwaInstallAction({required this.isCollapsed, super.key});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final service = PwaInstallService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!service.shouldShowAction) return const SizedBox.shrink();

        final item = Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _handleTap(context, service),
            borderRadius: BorderRadius.circular(10),
            focusColor: AppColors.primary.withValues(alpha: 0.24),
            hoverColor: AppColors.primary.withValues(alpha: 0.15),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.34),
                ),
              ),
              child: isCollapsed
                  ? const Center(
                      child: Icon(
                        Icons.install_mobile_outlined,
                        size: 22,
                        color: AppColors.textOnDark,
                      ),
                    )
                  : const Row(
                      children: [
                        Icon(
                          Icons.install_mobile_outlined,
                          size: 20,
                          color: AppColors.textOnDark,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Install web app (PWA)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: AppColors.textOnDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );

        return Semantics(
          button: true,
          label: 'Install AI-DSUHIS BHW web app (PWA)',
          child: Tooltip(
            message: 'Install web app (PWA)',
            preferBelow: false,
            child: item,
          ),
        );
      },
    );
  }

  Future<void> _handleTap(
    BuildContext context,
    PwaInstallService service,
  ) async {
    if (service.canPrompt && await service.promptInstall()) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.install_mobile_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(child: Text('Install web app (PWA)')),
          ],
        ),
        content: const Text(
          'This installs the browser version as a PWA (Progressive Web App). '
          'Use your browser menu and choose “Install app” or “Add to Home '
          'Screen”. It does not download or install the native Android APK.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
