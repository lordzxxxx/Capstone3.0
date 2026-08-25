import 'package:flutter/material.dart';

import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Uses the same light Material `AlertDialog` styling as the portal's
/// logout confirmation dialogs (see `_confirmAndLogout` in
/// `app_sidebar.dart` / `cho_navigation.dart`) so the login-success popup
/// reads as the same card instead of a separate dark/light design.
Future<bool> showLoginSuccessSweetAlert({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmButtonText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        icon: const Icon(
          Icons.check_circle_rounded,
          color: AppColors.primary,
          size: 34,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Manrope', color: AppColors.textPrimary),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(confirmButtonText),
            ),
          ),
        ],
      ),
    ),
  );
  return result ?? true;
}
