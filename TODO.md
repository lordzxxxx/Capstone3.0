# TODO: Redesign Add Check-Up Modal (Web-Oriented)

## Steps

- [ ] 1. Change `showModalBottomSheet` → `showDialog` in `_buildTopBar()` in `lib/web/roles/bhw/checkups/checkup.dart`
- [ ] 2. Replace `_NewCheckUpFullScreenModal.build()` — swap `DraggableScrollableSheet` with a web-oriented `Dialog`
  - [ ] 2a. Add gradient header bar (teal gradient, icon + title + subtitle + close button)
  - [ ] 2b. Use dark theme (`_sidebarDark` background, `_darkDeepTeal` form fields)
  - [ ] 2c. 2-column grid layout for form fields (web-oriented)
  - [ ] 2d. Section cards with colored top-bar headers (icon + title)
  - [ ] 2e. Sticky footer with Cancel / Save Record buttons
- [ ] 3. Update `_buildInputDecoration()` to use dark theme colors
- [ ] 4. Verify the modal renders correctly on Flutter web
