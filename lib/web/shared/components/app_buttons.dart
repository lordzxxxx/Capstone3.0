import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Shared button styles for the web portals.
///
/// Keeping action colors here prevents page-local report/export controls from
/// falling back to white-on-white or gradient styles.
abstract final class AppButtonStyles {
  static ButtonStyle primary({Color background = AppColors.primary}) {
    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.surfaceSubtle,
      disabledForegroundColor: AppColors.textSecondary,
      elevation: 0,
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle outline() {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: Colors.white,
      disabledForegroundColor: AppColors.textSecondary,
      side: const BorderSide(color: AppColors.primary, width: 1.2),
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle report() => primary();
}
