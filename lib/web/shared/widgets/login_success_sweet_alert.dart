import 'package:flutter/material.dart';

const Color _dialogBlue = Color(0xFF2F80ED);
const Color _dialogNavy = Color(0xFF071A33);
const Color _dialogSurface = Color(0xFF0D274D);
const Color _dialogMuted = Color(0xFFB8C9DB);
const Color _dialogBorder = Color(0xFF1C3D66);

/// Native Flutter replacement for the old JS-interop SweetAlert2 popup —
/// that dialog used its own default font/styling and never matched the
/// rest of the navy/white auth design system.
Future<bool> showLoginSuccessSweetAlert({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmButtonText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: _dialogNavy.withValues(alpha: 0.78),
    builder: (context) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
            decoration: BoxDecoration(
              color: _dialogSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _dialogBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dialogBlue.withValues(alpha: 0.18),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: _dialogBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: _dialogMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _dialogBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      confirmButtonText,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? true;
}
