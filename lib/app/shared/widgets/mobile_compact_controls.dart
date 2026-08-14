import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Compact, shared controls for mobile record lists.
///
/// The visual control is intentionally the same for BHW and CHO. The caller
/// still owns filtering and access-scope behavior; this widget only keeps the
/// interaction readable and usable on narrow screens.
class MobileSearchField extends StatelessWidget {
  const MobileSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: AppDesign.ink,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: AppDesign.subtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppDesign.muted,
            size: 20,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppDesign.muted,
                    size: 18,
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: AppDesign.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: _border(AppDesign.borderStrong),
          enabledBorder: _border(AppDesign.borderStrong),
          focusedBorder: _border(AppDesign.blue, width: 2),
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class MobileMenuButton extends StatelessWidget {
  const MobileMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
  });

  final PopupMenuItemBuilder<String> itemBuilder;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Open menu',
        icon: const Icon(Icons.menu_rounded, color: AppDesign.navy, size: 21),
        onSelected: onSelected,
        itemBuilder: itemBuilder,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
