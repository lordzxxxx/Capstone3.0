import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';

/// Small entry-point control so the privacy notice is available before sign-in
/// and before any mobile permission request can occur.
class PrivacyNoticeButton extends StatelessWidget {
  const PrivacyNoticeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(PrivacyNoticeContent.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(PrivacyNoticeContent.summary),
                const SizedBox(height: 18),
                ...PrivacyNoticeContent.sections.map(
                  (section) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(section.body),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      icon: const Icon(Icons.privacy_tip_outlined, size: 17),
      label: const Text('Privacy and permissions'),
    );
  }
}
