import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Centralized, uniform top navigation bar for web role pages.
///
/// Ensures a single source of truth for header color (`#071A33`), height (`70px`),
/// typography, drawer menu toggle, report generation button, refresh action,
/// and selection badge across all web modules.
class WebAppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const WebAppTopBar({
    super.key,
    required this.title,
    this.scaffoldKey,
    this.onMenuPressed,
    this.showMenuButton = false,
    this.onGenerateReport,
    this.generateReportLabel = 'Generate',
    this.generateReportIcon = Icons.picture_as_pdf_rounded,
    this.onRefresh,
    this.refreshTooltip = 'Refresh Data',
    this.isLoading = false,
    this.actions = const [],
    this.selectionCount,
    this.selectionLabel = 'selected',
    this.trailing,
    this.height = 70.0,
    this.backgroundColor = AppColors.backgroundDark,
    this.titleColor = Colors.white,
    this.titleStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 32),
  });

  /// The main headline title displayed in the top bar (e.g. 'Check-up Dashboard').
  final String title;

  /// Optional Scaffold key used to open the drawer when the menu icon is pressed.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Optional callback invoked when the menu icon is pressed. If null, uses [scaffoldKey].
  final VoidCallback? onMenuPressed;

  /// Whether to display the menu button on the leading side (deprecated, defaults to false).
  final bool showMenuButton;

  /// If provided, renders the standard PDF report generation button.
  final VoidCallback? onGenerateReport;

  /// The label for the report generation button (default: 'Generate').
  final String generateReportLabel;

  /// The icon for the report generation button.
  final IconData generateReportIcon;

  /// If provided, renders the standard refresh data icon button.
  final VoidCallback? onRefresh;

  /// Tooltip for the refresh button.
  final String refreshTooltip;

  /// Whether data is loading (disables actions when true).
  final bool isLoading;

  /// Additional custom actions to display on the trailing side.
  final List<Widget> actions;

  /// If provided and > 0, displays a selection badge (e.g. '3 selected').
  final int? selectionCount;

  /// The label displayed after the selection count.
  final String selectionLabel;

  /// Optional custom trailing widget.
  final Widget? trailing;

  /// The height of the top bar. Default is 70px.
  final double height;

  /// The background color of the top bar. Default is Midnight Navy [AppColors.backgroundDark].
  final Color backgroundColor;

  /// Color of the title text. Default is white.
  final Color titleColor;

  /// Optional override for the title text style.
  final TextStyle? titleStyle;

  /// Horizontal padding for the top bar container.
  final EdgeInsetsGeometry padding;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final horizontalLimit = width < 560
        ? 12.0
        : width < 1000
        ? 20.0
        : 32.0;
    final effectivePadding = EdgeInsets.only(
      left: resolvedPadding.left.clamp(12.0, horizontalLimit),
      right: resolvedPadding.right.clamp(12.0, horizontalLimit),
      top: resolvedPadding.top,
      bottom: resolvedPadding.bottom,
    );

    return Semantics(
      container: true,
      header: true,
      label: '$title header',
      child: Container(
        height: height,
        padding: effectivePadding,
        decoration: BoxDecoration(
          color: backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (showMenuButton)
              IconButton(
                tooltip: 'Open navigation menu',
                onPressed: () {
                  if (onMenuPressed != null) {
                    onMenuPressed!();
                  } else {
                    scaffoldKey?.currentState?.openDrawer();
                  }
                },
                icon: const Icon(Icons.menu_rounded),
                color: titleColor,
              ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    titleStyle ??
                    Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            // Keep the header usable at tablet widths. Actions remain keyboard
            // reachable and scroll horizontally instead of overflowing the
            // whole page or pushing the title off-screen.
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectionCount != null && selectionCount! > 0) ...[
                      Semantics(
                        liveRegion: true,
                        label: '$selectionCount $selectionLabel',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            '$selectionCount $selectionLabel',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (onGenerateReport != null) ...[
                      FilledButton.icon(
                        onPressed: isLoading ? null : onGenerateReport,
                        style: AppButtonStyles.report(),
                        icon: Icon(generateReportIcon, size: 18),
                        label: Text(
                          generateReportLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (onRefresh != null)
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: refreshTooltip,
                        onPressed: isLoading ? null : onRefresh,
                        color: Colors.white70,
                      ),
                    ...actions,
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
