import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    this.sidebarCollapsedListenable,
  });

  final Widget sidebar;
  final String title;
  final Widget child;
  final Color backgroundColor;
  final double breakpoint;
  final String? mobileBrandAsset;
  final ValueListenable<bool>? sidebarCollapsedListenable;

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

        final double defaultDrawerWidth = math.min(
          320.0,
          math.max(280.0, constraints.maxWidth * 0.86),
        );
        final mobileBody = SafeArea(
          top: true,
          bottom: true,
          child: Column(
            children: [
              WebMobileHeader(title: title, brandAsset: mobileBrandAsset),
              Expanded(child: child),
            ],
          ),
        );

        Widget drawerFor(bool isCollapsed) {
          return Drawer(
            width: isCollapsed ? 72 : defaultDrawerWidth,
            elevation: 16,
            child: MediaQuery(
              // Keep the drawer's navigation labels discoverable even when
              // the phone viewport itself is narrow or short. The sidebar
              // can still be intentionally collapsed, and the drawer width
              // follows that state so it never leaves an empty panel.
              data: MediaQuery.of(context).copyWith(
                size: Size(1200, math.max(1200, constraints.maxHeight)),
              ),
              child: WebResponsiveDrawerScope(child: sidebar),
            ),
          );
        }

        Widget mobileScaffold(bool isCollapsed) {
          return Scaffold(
            backgroundColor: backgroundColor,
            drawerEdgeDragWidth: math.min(32, constraints.maxWidth * 0.12),
            drawer: drawerFor(isCollapsed),
            body: mobileBody,
          );
        }

        final collapsedListenable = sidebarCollapsedListenable;
        if (collapsedListenable == null) return mobileScaffold(false);
        return ValueListenableBuilder<bool>(
          valueListenable: collapsedListenable,
          builder: (context, isCollapsed, _) => mobileScaffold(isCollapsed),
        );
      },
    );
  }
}

/// Marks a sidebar rendered inside the phone navigation drawer. Role-specific
/// sidebars can use this to distinguish a mobile drawer from a compact desktop
/// rail without changing the shared shell's behavior for other portals.
class WebResponsiveDrawerScope extends InheritedWidget {
  const WebResponsiveDrawerScope({required super.child, super.key});

  static bool isDrawerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebResponsiveDrawerScope>() !=
      null;

  @override
  bool updateShouldNotify(WebResponsiveDrawerScope oldWidget) => false;
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
