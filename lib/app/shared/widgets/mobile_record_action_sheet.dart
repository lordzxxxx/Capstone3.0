import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

enum MobileRecordActionTone { primary, neutral, success, danger }

class MobileRecordAction {
  const MobileRecordAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = MobileRecordActionTone.neutral,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final MobileRecordActionTone tone;
}

/// A consistent action sheet for mobile record cards across BHW and CHO flows.
/// The sheet owns presentation only; each feature keeps its existing actions
/// and permissions through [MobileRecordAction.onPressed].
class MobileRecordActionSheet extends StatelessWidget {
  const MobileRecordActionSheet({
    super.key,
    required this.title,
    required this.actions,
    this.subtitle = 'Choose an action for this record',
    this.headerIcon = Icons.more_horiz_rounded,
  });

  final String title;
  final String subtitle;
  final IconData headerIcon;
  final List<MobileRecordAction> actions;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<MobileRecordAction> actions,
    String subtitle = 'Choose an action for this record',
    IconData headerIcon = Icons.more_horiz_rounded,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppDesign.navy.withValues(alpha: 0.42),
      builder: (_) => MobileRecordActionSheet(
        title: title,
        subtitle: subtitle,
        headerIcon: headerIcon,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final horizontalPadding = compact ? 14.0 : 18.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      child: Material(
        color: AppDesign.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20,
              12,
              compact ? 16 : 20,
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppDesign.borderStrong,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppDesign.blueSoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(headerIcon, color: AppDesign.navy, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppDesign.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: AppDesign.muted,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppDesign.muted,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...List<Widget>.generate(actions.length, (index) {
                  final action = actions[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == actions.length - 1 ? 0 : 10,
                    ),
                    child: _ActionTile(action: action),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final MobileRecordAction action;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(action.tone);
    final primary = action.tone == MobileRecordActionTone.primary;

    return Semantics(
      button: true,
      label: action.label,
      child: SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
            Future.microtask(action.onPressed);
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: primary ? AppDesign.blue : colors.background,
            foregroundColor: primary ? Colors.white : colors.foreground,
            side: BorderSide(
              color: primary ? AppDesign.blue : colors.border,
              width: primary ? 0 : 1.2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.16)
                      : colors.iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  action.icon,
                  size: 18,
                  color: primary ? Colors.white : colors.foreground,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary ? Colors.white : colors.foreground,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: primary
                    ? Colors.white.withValues(alpha: 0.85)
                    : colors.foreground.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ActionColors _colors(MobileRecordActionTone tone) {
    switch (tone) {
      case MobileRecordActionTone.primary:
        return const _ActionColors(
          foreground: AppDesign.blue,
          background: AppDesign.blueSoft,
          border: AppDesign.blue,
          iconBackground: AppDesign.blueSoft,
        );
      case MobileRecordActionTone.success:
        return const _ActionColors(
          foreground: AppDesign.success,
          background: AppDesign.successBackground,
          border: AppDesign.success,
          iconBackground: AppDesign.successBackground,
        );
      case MobileRecordActionTone.danger:
        return const _ActionColors(
          foreground: AppDesign.danger,
          background: AppDesign.dangerBackground,
          border: AppDesign.danger,
          iconBackground: AppDesign.dangerBackground,
        );
      case MobileRecordActionTone.neutral:
        return const _ActionColors(
          foreground: AppDesign.navy,
          background: AppDesign.surface,
          border: AppDesign.borderStrong,
          iconBackground: AppDesign.blueSoft,
        );
    }
  }
}

class _ActionColors {
  const _ActionColors({
    required this.foreground,
    required this.background,
    required this.border,
    required this.iconBackground,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final Color iconBackground;
}
