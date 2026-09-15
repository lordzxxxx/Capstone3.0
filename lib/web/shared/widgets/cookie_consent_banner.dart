import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small, non-blocking consent notice for the web shell.
///
/// The web client uses essential browser storage for Firebase Auth session
/// persistence and this consent choice. It does not use advertising or
/// cross-site tracking cookies. The choice is scoped to this browser origin.
class CookieConsentBanner extends StatefulWidget {
  const CookieConsentBanner({super.key});

  static const String preferenceKey = 'ai_dsuhis_web_cookie_consent_v1';

  @override
  State<CookieConsentBanner> createState() => _CookieConsentBannerState();
}

class _CookieConsentBannerState extends State<CookieConsentBanner> {
  bool _loading = true;
  bool _consentGiven = false;

  @override
  void initState() {
    super.initState();
    _restoreConsent();
  }

  Future<void> _restoreConsent() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _consentGiven =
            preferences.getBool(CookieConsentBanner.preferenceKey) ?? false;
        _loading = false;
      });
    } catch (_) {
      // A restricted browser storage context should not block the web shell.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _agree() async {
    if (_consentGiven) return;
    setState(() => _consentGiven = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(CookieConsentBanner.preferenceKey, true);
    } catch (_) {
      // Keep the current-session decision even if persistence is unavailable.
    }
  }

  Future<void> _showPrivacyDetails() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Privacy and browser storage'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Text(
              PrivacyNoticeContent.dialogText,
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _consentGiven) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          key: const ValueKey('cookie-consent-details'),
          onPressed: _showPrivacyDetails,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondary,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('Privacy details'),
        ),
        FilledButton(
          key: const ValueKey('cookie-consent-agree'),
          onPressed: _agree,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: const Text('Agree'),
        ),
      ],
    );

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Semantics(
              container: true,
              label: 'Cookie and browser storage notice',
              child: Material(
                color: AppColors.surfaceLight,
                elevation: 12,
                shadowColor: AppColors.secondary.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final message = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: ExcludeSemantics(
                              child: Icon(
                                Icons.shield_outlined,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cookies and browser storage',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'We use essential browser storage to keep you signed in, remember this choice, and keep AI-DSUHIS secure. We do not use advertising or cross-site tracking.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            message,
                            const SizedBox(height: 12),
                            Align(alignment: Alignment.centerRight, child: actions),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: message),
                          const SizedBox(width: 20),
                          actions,
                        ],
                      );
                    },
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
