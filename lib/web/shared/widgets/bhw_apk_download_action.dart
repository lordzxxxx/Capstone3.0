import 'package:flutter/material.dart';

import '../services/bhw_apk_download.dart';
import '../theme/app_theme.dart';

/// BHW-facing action for downloading the native Android app APK.
///
/// This is intentionally separate from the PWA action: a PWA is installed by
/// the browser, while this control downloads an Android package that can be
/// installed on an Android phone without Google Play.
class BhwApkDownloadAction extends StatelessWidget {
  const BhwApkDownloadAction({required this.isCollapsed, super.key});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    if (!hasBhwApkDownload) return const SizedBox.shrink();

    final item = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _confirmDownload(context),
        borderRadius: BorderRadius.circular(10),
        focusColor: AppColors.primary.withValues(alpha: 0.24),
        hoverColor: AppColors.primary.withValues(alpha: 0.15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.22),
            ),
          ),
          child: isCollapsed
              ? const Center(
                  child: Icon(
                    Icons.android_outlined,
                    size: 22,
                    color: AppColors.textOnDark,
                  ),
                )
              : const Row(
                  children: [
                    Icon(
                      Icons.android_outlined,
                      size: 20,
                      color: AppColors.textOnDark,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Download Android app',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppColors.textOnDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
      label: 'Download the AI-DSUHIS BHW Android application APK',
      child: Tooltip(
        message: 'Download Android app (APK)',
        preferBelow: false,
        child: item,
      ),
    );
  }

  Future<void> _confirmDownload(BuildContext context) async {
    final shouldDownload = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.android_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(child: Text('Download BHW Android app')),
          ],
        ),
        content: const Text(
          'This downloads the AI-DSUHIS APK for Android phones. It is the '
          'native BHW app, separate from the browser install, and uses the '
          'same synchronized Firebase account and records. This build is '
          'for most modern 64-bit Android phones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: Icon(Icons.download_rounded),
            label: Text('Download APK'),
          ),
        ],
      ),
    );

    if (shouldDownload != true || !context.mounted) return;
    downloadBhwApk();
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('APK download started.')));
  }
}
