import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Responsive page frame shared by the web role pages.
///
/// Desktop keeps the existing persistent navigation rail. Phone-sized web
/// views use a real drawer instead, so the content receives the full viewport
/// width and can scroll without being squeezed by a desktop rail.
class WebResponsiveBody extends StatelessWidget {
  const WebResponsiveBody({
    super.key,
    required this.sidebar,
    required this.title,
    required this.child,
    this.backgroundColor = AppColors.backgroundLight,
    this.breakpoint = 760,
    this.mobileBrandAsset,
  });

  final Widget sidebar;
  final String title;
  final Widget child;
  final Color backgroundColor;
  final double breakpoint;
  final String? mobileBrandAsset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < breakpoint;
        if (!isMobile) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebar,
              Expanded(child: child),
            ],
          );
        }

        return Scaffold(
          backgroundColor: backgroundColor,
          drawerEdgeDragWidth: math.min(32, constraints.maxWidth * 0.12),
          drawer: Drawer(
            width: math.min(320, math.max(280, constraints.maxWidth * 0.86)),
            elevation: 16,
            child: MediaQuery(
              // The navigation widgets use the ambient width to choose their
              // collapsed rail mode. A drawer is intentionally a full-label
              // navigation surface even when the browser viewport is narrow.
              data: MediaQuery.of(context).copyWith(
                // Keep the drawer in expanded-label mode even when the
                // phone viewport itself is short. The desktop rail may
                // auto-collapse for short windows, but a mobile drawer must
                // remain discoverable without requiring icon-only tooltips.
                size: Size(1200, math.max(1200, constraints.maxHeight)),
              ),
              child: sidebar,
            ),
          ),
          body: SafeArea(
            top: true,
            bottom: true,
            child: Column(
              children: [
                WebMobileHeader(title: title, brandAsset: mobileBrandAsset),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }
}

class WebMobileHeader extends StatelessWidget {
  const WebMobileHeader({super.key, required this.title, this.brandAsset});

  final String title;
  final String? brandAsset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.backgroundDark,
      elevation: 4,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: 'Open navigation menu',
                icon: const Icon(Icons.menu_rounded),
                color: AppColors.textOnDark,
                iconSize: 26,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontFamily: AppTheme.displayFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: brandAsset == null
                    ? const Icon(
                        Icons.health_and_safety_outlined,
                        color: AppColors.primary,
                        size: 24,
                      )
                    : Image.asset(
                        brandAsset!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.health_and_safety_outlined,
                              color: AppColors.primary,
                              size: 24,
                            ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
