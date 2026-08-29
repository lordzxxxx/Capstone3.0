import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// A single link in a [LiquidGlassNavbar].
class LiquidGlassNavItem {
  const LiquidGlassNavItem({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
}

/// A floating, translucent Apple/macOS "Liquid Glass" style navigation bar.
///
/// Deliberately kept lighter and more transparent than the reference macOS
/// widget style: a soft blur, a faint white tint, a thin glass border/top
/// highlight, and a minimal shadow, so it reads as a clean floating capsule
/// rather than a heavy opaque panel. It does not introduce any new brand
/// colors — only whites/blacks layered over the caller's existing palette.
class LiquidGlassNavbar extends StatefulWidget {
  const LiquidGlassNavbar({
    super.key,
    required this.items,
    required this.logo,
    required this.brandLabel,
    required this.onBrandTap,
    this.lightSurface = false,
  });

  final List<LiquidGlassNavItem> items;
  final Widget logo;
  final String brandLabel;
  final VoidCallback onBrandTap;
  final bool lightSurface;

  @override
  State<LiquidGlassNavbar> createState() => _LiquidGlassNavbarState();
}

class _LiquidGlassNavbarState extends State<LiquidGlassNavbar> {
  bool _mobileMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Keep the primary labels inline only at genuine desktop widths.
        // Anything narrower (tablet or phone) collapses to the menu toggle so
        // the bar never overflows or grows oversized.
        final collapsed = width < 980;
        final isPhone = width < 640;
        final horizontalMargin = isPhone ? 12.0 : (collapsed ? 20.0 : 28.0);
        final maxBarWidth = collapsed ? double.infinity : 1080.0;

        final bar = _GlassSurface(
          borderRadius: 26,
          lightSurface: widget.lightSurface,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isPhone ? 14 : 20,
              vertical: isPhone ? 8 : 10,
            ),
            child: Row(
              children: [
                _Brand(
                  logo: widget.logo,
                  label: widget.brandLabel,
                  compact: isPhone,
                  lightSurface: widget.lightSurface,
                  onTap: widget.onBrandTap,
                ),
                const Spacer(),
                if (!collapsed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in widget.items)
                        _NavLink(
                          item: item,
                          dense: false,
                          lightSurface: widget.lightSurface,
                        ),
                    ],
                  )
                else
                  _MenuToggleButton(
                    isOpen: _mobileMenuOpen,
                    lightSurface: widget.lightSurface,
                    onTap: () =>
                        setState(() => _mobileMenuOpen = !_mobileMenuOpen),
                  ),
              ],
            ),
          ),
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            if (collapsed)
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_mobileMenuOpen
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _GlassSurface(
                          borderRadius: 20,
                          lightSurface: widget.lightSurface,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final item in widget.items)
                                  _MobileNavLink(
                                    item: item,
                                    lightSurface: widget.lightSurface,
                                    onTap: () {
                                      setState(() => _mobileMenuOpen = false);
                                      item.onTap();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalMargin,
          ).copyWith(top: isPhone ? 10 : 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBarWidth),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

/// Shared blurred-glass container: soft blur, faint white tint, thin
/// highlight border, minimal shadow. Intentionally lighter/more transparent
/// than a typical opaque macOS panel.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    required this.borderRadius,
    required this.lightSurface,
  });

  final Widget child;
  final double borderRadius;
  final bool lightSurface;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final topHighlight = lightSurface
        ? AppColors.primary.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: lightSurface ? 0.14 : 0.10),
            blurRadius: lightSurface ? 22 : 18,
            offset: Offset(0, lightSurface ? 8 : 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: lightSurface
                    ? [
                        Colors.white.withValues(alpha: 0.98),
                        Colors.white.withValues(alpha: 0.92),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.07),
                      ],
              ),
              border: Border.all(
                color: lightSurface
                    ? AppColors.border
                    : Colors.white.withValues(alpha: 0.24),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Thin inner top highlight — the classic glass "catch light".
                Positioned(
                  left: borderRadius,
                  right: borderRadius,
                  top: 1,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          topHighlight,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({
    required this.logo,
    required this.label,
    required this.compact,
    required this.lightSurface,
    required this.onTap,
  });

  final Widget logo;
  final String label;
  final bool compact;
  final bool lightSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '$label, return to top',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                  child: lightSurface
                      ? ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            AppColors.secondary,
                            BlendMode.srcIn,
                          ),
                          child: logo,
                        )
                      : logo,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: lightSurface ? AppColors.textPrimary : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.item,
    required this.dense,
    required this.lightSurface,
  });

  final LiquidGlassNavItem item;
  final bool dense;
  final bool lightSurface;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.item.active || _hovering;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 2 : 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: widget.item.onTap,
            child: Semantics(
              button: true,
              selected: widget.item.active,
              label: widget.item.label,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.dense ? 10 : 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: highlighted
                      ? (widget.lightSurface
                            ? AppColors.primary.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.16))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: highlighted
                        ? (widget.lightSurface
                              ? AppColors.primary.withValues(alpha: 0.34)
                              : Colors.white.withValues(alpha: 0.28))
                        : (widget.lightSurface
                              ? AppColors.border
                              : Colors.transparent),
                  ),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: widget.dense ? 12.5 : 13.5,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
                    color: widget.lightSurface
                        ? (highlighted
                              ? AppColors.textPrimary
                              : AppColors.textSecondary)
                        : Colors.white.withValues(
                            alpha: highlighted ? 1 : 0.82,
                          ),
                  ),
                  child: Text(widget.item.label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavLink extends StatelessWidget {
  const _MobileNavLink({
    required this.item,
    required this.lightSurface,
    required this.onTap,
  });

  final LiquidGlassNavItem item;
  final bool lightSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: item.active,
          label: item.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14.5,
                      fontWeight: item.active
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: lightSurface
                          ? (item.active
                                ? AppColors.textPrimary
                                : AppColors.textSecondary)
                          : Colors.white.withValues(
                              alpha: item.active ? 1 : 0.86,
                            ),
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: lightSurface
                        ? AppColors.textSecondary
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuToggleButton extends StatelessWidget {
  const _MenuToggleButton({
    required this.isOpen,
    required this.lightSurface,
    required this.onTap,
  });

  final bool isOpen;
  final bool lightSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Tooltip(
          message: isOpen ? 'Close navigation menu' : 'Open navigation menu',
          child: Semantics(
            button: true,
            label: isOpen ? 'Close navigation menu' : 'Open navigation menu',
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lightSurface
                    ? AppColors.primary.withValues(alpha: isOpen ? 0.12 : 0.0)
                    : Colors.white.withValues(alpha: isOpen ? 0.18 : 0.0),
                border: Border.all(
                  color: lightSurface
                      ? AppColors.borderStrong
                      : Colors.white.withValues(alpha: 0.24),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: ExcludeSemantics(
                  child: Icon(
                    isOpen ? Icons.close_rounded : Icons.menu_rounded,
                    key: ValueKey(isOpen),
                    size: 19,
                    color: lightSurface ? AppColors.secondary : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
