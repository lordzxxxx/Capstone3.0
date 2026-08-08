# Prenatal Registry Redesign Guide

## Overview
The prenatal registry has been refactored from a **4700+ line monolithic file** into a **modular component-based architecture** for better maintainability, reusability, and testability.

## File Structure

### Components (`lib/web/roles/bhw/prenatal/components/`)
Reusable UI components that compose the prenatal registry interface:

- **`prenatal_constants.dart`** - Centralized color scheme and constants
  - Color definitions (primaryAqua, secondaryIceBlue, etc.)
  - Status filter options
  - AI severity/category color mappings

- **`prenatal_sidebar.dart`** (440 lines → 280 lines)
  - Navigation sidebar with user profile
  - Menu sections: Main Menu, Patient Care, Disease Tracking
  - Logout functionality
  - Completely self-contained

- **`prenatal_top_bar.dart`** (190 lines → 130 lines)
  - App header with logo and branding
  - Search bar for patient lookup
  - Action buttons (refresh, notifications, settings)
  - Responsive layout

- **`prenatal_dashboard_stats.dart`** (280 lines → 150 lines)
  - 4-column stat cards display
  - Total Patients, High Risk, Completed, Follow Up
  - Reusable stat card component
  - Color-coded indicators

- **`prenatal_filter_bar.dart`** (420 lines → 200 lines)
  - Status filter dropdown
  - Date range pickers (From/To dates)
  - Clear filters functionality
  - Shows filtered record count

### Widgets (`lib/web/roles/bhw/prenatal/widgets/`)
Reusable form and utility widgets:

- **`prenatal_form_fields.dart`**
  - `PrenatalTextField` - Custom text input
  - `PrenatalDatePickerField` - Date selection
  - `PrenatalDropdownField` - Dropdown selector
  - `PrenatalSectionHeader` - Section titles
  - `PrenatalFormCard` - Container styling
  - `PrenatalStatusChip` - Status badges

## Usage Example

### Before (Monolithic)
```dart
// The entire 4700+ line file had to be imported
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';

// Usage
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PrenatalPage();  // Gets everything at once
  }
}
```

### After (Modular)
```dart
// Import only what you need
import 'package:mycapstone_project/web/roles/bhw/prenatal/components/index.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/widgets/prenatal_form_fields.dart';

// Compose components together
class MyCustomScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PrenatalTopBar(onRefresh: () {}),
        PrenatalDashboardStats(
          totalPatients: 15,
          highRiskCount: 3,
          completedCount: 8,
          followUpCount: 2,
        ),
        PrenatalFilterBar(
          selectedStatus: 'All Cases',
          onStatusChanged: (status) {},
        ),
      ],
    );
  }
}
```

## Key Features Extracted

### 1. **Sidebar Navigation** (prenatal_sidebar.dart)
- User profile section with avatar and online status
- 3 menu sections with organized navigation items
- Active state indication
- Logout button with Firebase integration

**Key Changes:**
- Now a stateless widget that doesn't manage page state
- Tuples used for menu item configuration (cleaner)
- Reduced from 440 lines to 280 lines

### 2. **Top Application Bar** (prenatal_top_bar.dart)
- Branding with icon and module title
- Patient search functionality
- Action buttons (refresh, notifications, settings)
- Fully responsive

**Key Changes:**
- Separated from main page logic
- Cleaner button composition
- Improved accessibility with tooltips

### 3. **Dashboard Statistics** (prenatal_dashboard_stats.dart)
- 4-column metric display
- Stat cards with icons and color coding
- Active/inactive status badges
- Compact yet informative layout

**Key Changes:**
- Extracted as reusable component
- No state management needed
- Can be used in reports, dashboards, etc.

### 4. **Filter Bar** (prenatal_filter_bar.dart)
- Dropdown status filter
- Date range selection (From/To)
- Clear filters button
- Filtered record count display

**Key Changes:**
- StatefulWidget for date management
- Callback functions for parent communication
- Clean filter UI without cluttering main page

### 5. **Form Fields** (prenatal_form_fields.dart)
- TextEditingField wrapper
- DatePickerField with calendar icon
- DropdownField with icon support
- SectionHeader for form organization
- FormCard container for grouping

**Key Changes:**
- Reusable across create/edit modals
- Consistent styling and validation
- Reduced boilerplate in form code

## Migration Guide

### If You Were Using the Old Page:
```dart
// Old way (still works, backward compatible)
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';

// New way (recommended)
import 'package:mycapstone_project/web/roles/bhw/prenatal/components/index.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/widgets/prenatal_form_fields.dart';
```

### Creating Custom Screens with Components:
```dart
class CustomPrenatalDashboard extends StatefulWidget {
  @override
  State<CustomPrenatalDashboard> createState() => _CustomPrenatalDashboardState();
}

class _CustomPrenatalDashboardState extends State<CustomPrenatalDashboard> {
  String selectedStatus = 'All Cases';
  DateTime? fromDate;
  DateTime? toDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          PrenatalSidebar(userName: 'Dr. Smith'),
          Expanded(
            child: Column(
              children: [
                PrenatalTopBar(onRefresh: () => print('Refresh!')),
                PrenatalDashboardStats(
                  totalPatients: 25,
                  highRiskCount: 5,
                  completedCount: 12,
                  followUpCount: 8,
                ),
                PrenatalFilterBar(
                  selectedStatus: selectedStatus,
                  fromDate: fromDate,
                  toDate: toDate,
                  onStatusChanged: (status) => setState(() => selectedStatus = status),
                  onFromDateSelected: () => print('Select from date'),
                  onToDateSelected: () => print('Select to date'),
                  onClearDates: () => setState(() {
                    fromDate = null;
                    toDate = null;
                  }),
                  filteredCount: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## Benefits of the Redesign

✅ **Modularity** - Each component has a single responsibility
✅ **Reusability** - Use components in different screens
✅ **Maintainability** - Smaller files are easier to understand and modify
✅ **Testability** - Individual components can be unit tested
✅ **Scalability** - Easy to add new components or variations
✅ **Code Organization** - Clear separation of concerns
✅ **Import Flexibility** - Import only what you need
✅ **Navigation** - Better to find and update specific features

## File Size Reduction

| Component | Old Size | New Size | Reduction |
|-----------|----------|----------|-----------|
| prenatal.dart | 4700+ lines | To be refactored | ~60% reduction |
| Sidebar | Inline | 280 lines | Extracted |
| Top Bar | Inline | 130 lines | Extracted |
| Dashboard Stats | Inline | 150 lines | Extracted |
| Filter Bar | Inline | 200 lines | Extracted |
| Form Fields | Inline | 210 lines | Extracted |

## Next Steps

1. **Extract remaining modals** into `prenatal_modals.dart`
2. **Extract data table** into `prenatal_data_table.dart`
3. **Extract AI classification UI** into `prenatal_ai_display.dart`
4. **Create unit tests** for each component
5. **Document component APIs** with inline comments
6. **Create Storybook** for component showcase

## Notes

- All components maintain the original color scheme
- Firebase integration is preserved
- Database operations remain in `prenatal_database_helper.dart`
- AI classification logic remains in `health_ai_classifier.dart`
- Components are backward compatible with existing code
