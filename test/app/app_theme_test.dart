import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  test('mobile theme stays light and uses the shared surface palette', () {
    final theme = AppDesign.theme();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppDesign.page);
    expect(theme.colorScheme.surface, AppDesign.surface);
    expect(theme.colorScheme.onSurface, AppDesign.ink);
    expect(theme.dialogTheme.backgroundColor, AppDesign.surface);
    expect(theme.bottomSheetTheme.backgroundColor, AppDesign.surface);
    expect(theme.navigationBarTheme.backgroundColor, AppDesign.surface);
    expect(theme.appBarTheme.backgroundColor, AppDesign.surface);
    expect(theme.appBarTheme.foregroundColor, AppDesign.ink);
    expect(AppDesign.blue, const Color(0xFF2F80ED));
    expect(AppDesign.page, const Color(0xFFF5F7FA));
  });

  test('compound clinical statuses use stable risk-first semantics', () {
    expect(
      AppDesign.statusColors('Completed with adverse event').foreground,
      AppDesign.danger,
    );
    expect(
      AppDesign.statusColors('Fully Immunized').foreground,
      AppDesign.success,
    );
    expect(
      AppDesign.statusColors('Under Treatment').foreground,
      AppDesign.warning,
    );
    expect(
      AppDesign.statusColors('Referred').foreground,
      AppDesign.information,
    );
    expect(AppDesign.statusColors('Due soon').foreground, AppDesign.warning);
    expect(AppDesign.statusColors('Overdue').foreground, AppDesign.danger);
    expect(AppDesign.statusColors('Certified').foreground, AppDesign.success);
    expect(
      AppDesign.statusColors('Returned for correction').foreground,
      AppDesign.danger,
    );
  });
}
