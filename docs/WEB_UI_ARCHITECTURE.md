# Flutter web UI architecture

The web platform lives under `lib/web` and is intentionally separate from the
mobile app under `lib/app`. The shared web layer is the safest place to make a
visual or interaction change that should reach both BHW and CHO users.

## Change the shared layer first

- Use `AppColors`, `AppSpacing`, and `AppTheme` for palette, rhythm, focus, hover,
  progress, scrollbar, input, and button behavior.
- Use `WebNavigationItem` for shell navigation. It exposes focus, tap, selected,
  and button semantics and works with keyboard navigation.
- Use `WebPageContent` for responsive gutters and a readable desktop max-width.
- Use `WebTableSurface`, `WebFilterSurface`, `WebSearchField`, and
  `WebStatusCallout` for consistent data-heavy states.
- Use `HealthModuleViewHeader` and `ModuleEmptyState` for BHW module headers and
  empty states.

## Why the old UI was difficult to change

Several older feature files are large route-level widgets that mix data loading,
Firestore listeners, dialogs, navigation, and layout. They also redeclare
colors and interaction widgets locally. That meant a change to spacing or a
focus state had to be repeated across many files and could behave differently at
tablet widths.

New work should keep route pages responsible for domain behavior while moving
reusable presentation into `lib/web/shared`. A gradual migration is safer than
rewriting the modules: migrate one header/table/form at a time, add a focused
widget test, then verify at 375, 768, 1024, and desktop widths.

## Responsive shell behavior

Both role navigation rails automatically compact below 1180 CSS pixels. This
preserves the main working area on tablets and narrow browser windows while
retaining the expanded navigation preference on wide screens. Data tables keep
their readable minimum width and scroll inside their own surface instead of
creating page-level horizontal overflow.
