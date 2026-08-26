import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Accessible, keyboard-operable navigation item shared by the BHW and CHO
/// web shells. The older role pages used custom GestureDetector trees, which
/// made pointer feedback look polished but left keyboard focus inconsistent.
class WebNavigationItem extends StatelessWidget {
  const WebNavigationItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isCollapsed,
    this.isActive = false,
    this.tooltip,
    this.isDense,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isCollapsed;
  final bool isActive;
  final String? tooltip;
  final bool? isDense;

  @override
  Widget build(BuildContext context) {
    final dense =
        isDense ??
        (MediaQuery.sizeOf(context).width >= 760 &&
            MediaQuery.sizeOf(context).height < 1000);
    final item = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        focusColor: AppColors.primary.withValues(alpha: 0.24),
        hoverColor: AppColors.primary.withValues(alpha: 0.15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(
            minHeight: isCollapsed ? 44 : (dense ? 40 : 46),
          ),
          margin: EdgeInsets.symmetric(
            vertical: isCollapsed ? 3 : (dense ? 1 : 2),
          ),
          padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.24),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: isCollapsed
              ? Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: isActive ? Colors.white : AppColors.textOnDark,
                  ),
                )
              : Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: isActive ? 4 : 0,
                      height: isActive ? (dense ? 20 : 22) : 0,
                      margin: EdgeInsets.only(right: isActive ? 8 : 0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Icon(
                      icon,
                      size: dense ? 19 : 20,
                      color: isActive ? Colors.white : AppColors.textOnDark,
                    ),
                    SizedBox(width: dense ? 8 : 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: isActive ? Colors.white : AppColors.textOnDark,
                          fontSize: dense ? 12.5 : 13,
                          height: 1.15,
                          fontWeight: isActive
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isActive)
                      Padding(
                        padding: EdgeInsets.only(left: dense ? 6 : 8),
                        child: Icon(Icons.circle, size: 6, color: Colors.white),
                      ),
                  ],
                ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: isActive,
      label: '$label navigation item',
      child: Tooltip(
        message: tooltip ?? label,
        preferBelow: false,
        child: item,
      ),
    );
  }
}
