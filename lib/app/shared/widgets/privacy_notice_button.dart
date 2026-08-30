import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';

// Unified Transparent Liquid Glass Palette
abstract final class _PrivacyGlassTheme {
  static const deepNavy = Color(0xFF0F2642);
  static const surfaceNavy = Color(0xFF132F52);
  static const glassBorder = Color(0x38FFFFFF); // ~22% white
  static const glassHighlight = Color(0x52FFFFFF); // ~32% white
  static const iconBadgeBg = Color(0x24FFFFFF); // ~14% white
  static const textPrimary = Colors.white;
  static const textMuted = Color(0xFFE3EDF8);
  static const secondaryMuted = Color(0xFFA5C4E5);
}

/// Small entry-point control so the privacy notice is available before sign-in
/// and before any mobile permission request can occur.
class PrivacyNoticeButton extends StatelessWidget {
  const PrivacyNoticeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.30),
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          expand: false,
          builder: (context, scrollController) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _PrivacyGlassTheme.deepNavy.withValues(alpha: 0.48),
                      _PrivacyGlassTheme.surfaceNavy.withValues(alpha: 0.38),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: const Border(
                    top: BorderSide(color: _PrivacyGlassTheme.glassHighlight, width: 1.5),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Grabber & Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                width: 44,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _PrivacyGlassTheme.iconBadgeBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _PrivacyGlassTheme.glassBorder),
                                  ),
                                  child: const Icon(
                                    Icons.privacy_tip_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'DATA PRIVACY & PERMISSIONS',
                                        style: TextStyle(
                                          fontFamily: 'Manrope',
                                          color: _PrivacyGlassTheme.secondaryMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        PrivacyNoticeContent.title,
                                        style: TextStyle(
                                          fontFamily: 'Manrope',
                                          color: _PrivacyGlassTheme.textPrimary,
                                          fontSize: 17.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _PrivacyGlassTheme.secondaryMuted,
                                  ),
                                  onPressed: () => Navigator.of(sheetContext).pop(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: _PrivacyGlassTheme.glassBorder),
                      // Scrollable Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Summary Container
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _PrivacyGlassTheme.glassBorder),
                                ),
                                child: const Text(
                                  PrivacyNoticeContent.summary,
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    color: _PrivacyGlassTheme.textMuted,
                                    fontSize: 13.5,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Glass Sections
                              ...PrivacyNoticeContent.sections.map((section) {
                                final icon = _getSectionIcon(section.title);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _PrivacyGlassTheme.glassBorder),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _PrivacyGlassTheme.iconBadgeBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: _PrivacyGlassTheme.glassBorder),
                                        ),
                                        child: Icon(icon, color: Colors.white, size: 20),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              section.title,
                                              style: const TextStyle(
                                                fontFamily: 'Manrope',
                                                color: _PrivacyGlassTheme.textPrimary,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              section.body,
                                              style: const TextStyle(
                                                fontFamily: 'Manrope',
                                                color: _PrivacyGlassTheme.textMuted,
                                                fontSize: 12.8,
                                                height: 1.42,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.privacy_tip_outlined, size: 17),
      label: const Text('Privacy and permissions'),
    );
  }

  static IconData _getSectionIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('collect')) {
      return Icons.inventory_2_outlined;
    } else if (lower.contains('access')) {
      return Icons.admin_panel_settings_outlined;
    } else if (lower.contains('permission')) {
      return Icons.camera_alt_outlined;
    } else if (lower.contains('ai') || lower.contains('ocr')) {
      return Icons.psychology_outlined;
    } else if (lower.contains('choice')) {
      return Icons.tune_rounded;
    }
    return Icons.security_rounded;
  }
}
