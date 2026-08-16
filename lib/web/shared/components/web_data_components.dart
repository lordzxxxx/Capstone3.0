import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared responsive shell for web data tables.
///
/// Tables keep a readable minimum width on narrow viewports and scroll only
/// inside the table surface instead of pushing the whole page horizontally.
class WebTableSurface extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minWidth;
        final tableWidth = math.max(minWidth, availableWidth);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Padding(padding: padding, child: child),
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
        suffixIcon: controller.text.isEmpty && onClear == null
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
