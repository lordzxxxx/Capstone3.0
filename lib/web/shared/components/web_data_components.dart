import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Consistent responsive page frame for operational web screens.
///
/// Older feature pages each chose their own gutters and maximum width. This
/// wrapper keeps the content readable on large monitors while preserving
/// comfortable space for BHW and CHO users on tablets and narrow browsers.
class WebPageContent extends StatelessWidget {
  const WebPageContent({
    required this.child,
    this.maxWidth = 1600,
    this.padding,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final horizontal = width < 560
            ? 16.0
            : width < 1100
            ? 24.0
            : 32.0;
        final resolvedPadding =
            padding ??
            EdgeInsets.symmetric(horizontal: horizontal, vertical: 24);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: resolvedPadding, child: child),
          ),
        );
      },
    );
  }
}

/// A small, reusable status callout for states that need more context than a
/// snackbar but should not interrupt the user's work with a modal dialog.
class WebStatusCallout extends StatelessWidget {
  const WebStatusCallout({
    required this.title,
    required this.message,
    required this.icon,
    this.color = AppColors.primary,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (action == null || constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    action!,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: content),
                const SizedBox(width: AppSpacing.md),
                action!,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Shared responsive shell for web data tables.
///
/// Tables keep a readable minimum width on narrow viewports and scroll only
/// inside the table surface instead of pushing the whole page horizontally.
class WebTableSurface extends StatefulWidget {
  const WebTableSurface({
    required this.child,
    this.minWidth = 960,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final double minWidth;
  final EdgeInsetsGeometry padding;

  @override
  State<WebTableSurface> createState() => _WebTableSurfaceState();
}

class _WebTableSurfaceState extends State<WebTableSurface> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.minWidth;
        final tableWidth = math.max(widget.minWidth, availableWidth);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Light, wrapping toolbar used for search and filter controls on web pages.
class WebFilterSurface extends StatelessWidget {
  const WebFilterSurface({
    this.children = const <Widget>[],
    this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final List<Widget> children;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child:
          child ??
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
    );
  }
}

/// Standard search control for web data pages.
class WebSearchField extends StatelessWidget {
  const WebSearchField({
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.width,
    this.prefixIcon = Icons.search_rounded,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final double? width;
  final IconData prefixIcon;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final field = TextField(
          controller: controller,
          onChanged: onChanged,
          cursorColor: AppColors.primary,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(prefixIcon, color: AppColors.primary),
            suffixIcon: value.text.isEmpty && onClear == null
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );

        if (width == null) return field;
        return SizedBox(width: width, child: field);
      },
    );
  }
}

/// Standard readable dropdown used inside [WebFilterSurface].
class WebFilterDropdown<T> extends StatelessWidget {
  const WebFilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 190,
    super.key,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        onChanged: onChanged,
        dropdownColor: AppColors.surfaceLight,
        iconEnabledColor: AppColors.textSecondary,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(labelText: label),
        items: items,
      ),
    );
  }
}
