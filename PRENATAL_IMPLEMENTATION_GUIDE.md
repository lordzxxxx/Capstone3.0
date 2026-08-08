# Implementation Guide: Updated Prenatal.dart

## Quick Start - Converting Your prenatal.dart

Here's how to update your existing `prenatal.dart` to use the new components:

### Step 1: Update Imports

**BEFORE:**
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ... 10+ other imports
```

**AFTER:**
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/components/index.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/widgets/prenatal_form_fields.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'dart:convert';
```

### Step 2: Remove Color Constants

**DELETE this section (now in prenatal_constants.dart):**
```dart
// ❌ REMOVE THIS - moved to components/prenatal_constants.dart
const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
// ... etc
```

### Step 3: Remove Build Methods (Now Components)

**DELETE these methods - they're now components:**
```dart
// ❌ REMOVE - use PrenatalSidebar component
Widget _buildSidebar(BuildContext context, String userName) { ... }

// ❌ REMOVE - use PrenatalTopBar component  
Widget _buildTopBar(BuildContext context) { ... }

// ❌ REMOVE - use PrenatalDashboardStats component
Widget _buildWebDashboardCard(...) { ... }

// ❌ REMOVE - use PrenatalFilterBar component
Widget _buildWebFilterBar() { ... }
```

### Step 4: Update the Main Build Method

**BEFORE (400+ lines of nested widgets):**
```dart
@override
Widget build(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  final userName = user?.email?.split('@')[0] ?? 'User';

  return Scaffold(
    backgroundColor: _darkDeepTeal,
    body: Row(
      children: [
        // Sidebar - 440+ lines of code inline
        _buildSidebar(context, userName),
        
        // Main Content
        Expanded(
          child: Column(
            children: [
              // Top Bar - 190+ lines of code inline
              _buildTopBar(context),
              
              // Content Area
              Expanded(
                child: _isLoading
                    ? const Center(...)
                    : Stack(
                      children: [
                        // Dashboard
                        // Filter Bar
                        // Data Table
                        // ... more 500+ lines
                      ],
                    ),
              ),
            ],
          ),
        ),
      ],
    ),
    floatingActionButton: ...,
  );
}
```

**AFTER (Clean & organized):**
```dart
@override
Widget build(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  final userName = user?.email?.split('@')[0] ?? 'User';

  return Scaffold(
    backgroundColor: darkDeepTeal,
    body: Row(
      children: [
        // 1. Sidebar Component
        PrenatalSidebar(userName: userName),
        
        // 2. Main Content Area
        Expanded(
          child: Column(
            children: [
              // 3. Top Bar Component
              PrenatalTopBar(onRefresh: _loadRecords),
              
              // 4. Content with Stats, Filters, Table
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: primaryAqua),
                      )
                    : Stack(
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(40.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Page Header
                                _buildPageHeader(),
                                const SizedBox(height: 32),
                                
                                // 5. Dashboard Stats Component
                                PrenatalDashboardStats(
                                  totalPatients: _prenatalRecords.length,
                                  highRiskCount: _prenatalRecords.where((r) => r['status'] == 'High Risk').length,
                                  completedCount: _prenatalRecords.where((r) => r['status'] == 'Completed').length,
                                  followUpCount: _prenatalRecords.where((r) => r['status'] == 'Follow Up').length,
                                ),
                                const SizedBox(height: 40),
                                
                                // 6. Filter Bar Component
                                PrenatalFilterBar(
                                  selectedStatus: _selectedStatusFilter,
                                  fromDate: _fromDate,
                                  toDate: _toDate,
                                  onStatusChanged: (status) {
                                    setState(() => _selectedStatusFilter = status);
                                  },
                                  onFromDateSelected: () => _selectDate(context, true),
                                  onToDateSelected: () => _selectDate(context, false),
                                  onClearDates: _clearDateFilters,
                                  filteredCount: _getFilteredRecords().length,
                                ),
                                const SizedBox(height: 24),
                                
                                // 7. Data Table Component
                                _buildPatientsDataTable(),
                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                          // Selection Action Card
                          _buildSelectionActionCard(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    ),
    floatingActionButton: _buildFloatingActionButton(),
  );
}

// New simple page header method (replaces inline code)
Widget _buildPageHeader() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'Dashboard',
            style: TextStyle(
              color: mutedCoolGray,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.chevron_right, size: 16, color: mutedCoolGray),
          ),
          Text(
            'Prenatal Care',
            style: TextStyle(
              color: primaryAqua,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'Maternal Health Management',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 28,
            ),
      ),
    ],
  );
}

// Floating action button helper
Widget? _buildFloatingActionButton() {
  return (_isDeleteDialogShowing ||
          (_isSelectionMode && _selectedIndices.isNotEmpty))
      ? null
      : FloatingActionButton.extended(
          onPressed: () => _showNewPrenatalModal(context),
          backgroundColor: primaryAqua,
          elevation: 4,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'New Prenatal',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        );
}
```

### Step 5: Update Form Methods (Use Form Field Components)

**BEFORE (160+ lines for a single form field):**
```dart
Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  String? hintText,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(...),
      const SizedBox(...),
      TextField(...),
    ],
  );
}
```

**AFTER (Use PrenatalTextField):**
```dart
// In your modals, replace field code with:
PrenatalTextField(
  controller: firstNameController,
  label: 'First Name',
  icon: Icons.person_outline,
  hintText: 'Enter first name',
)

// Section headers:
PrenatalSectionHeader(
  title: 'Patient Information',
  icon: Icons.person,
)

// Form containers:
PrenatalFormCard(
  children: [
    // Form fields here
  ],
)

// Status chips:
PrenatalStatusChip(status: record['status'])
```

### Step 6: Update State Variables

**KEEP these (core page state):**
```dart
class _PrenatalPageState extends State<PrenatalPage> {
  String _selectedStatusFilter = 'All Cases';
  DateTime? _fromDate;
  DateTime? _toDate;
  
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _prenatalRecords = [];
  final PrenatalDatabaseHelper _dbHelper = PrenatalDatabaseHelper.instance;
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  
  // ... keep all methods for:
  // - _loadRecords()
  // - _showNewPrenatalModal()
  // - _showEditPrenatalModal()
  // - _showPrenatalAIModal()
  // - _getFilteredRecords()
  // - etc.
}
```

### Step 7: File Size Comparison

| Section | Before | After | Saved |
|---------|--------|-------|-------|
| Imports | 16 lines | 10 lines | 6 lines |
| Constants | 26 lines | 0 lines* | 26 lines |
| Sidebar | 440 lines | Component | 440 lines |
| Top Bar | 190 lines | Component | 190 lines |
| Dashboard Cards | 280 lines | Component | 280 lines |
| Filter Bar | 420 lines | Component | 420 lines |
| Form Fields | 160 lines | Component | 160 lines** |
| Main build() | 400+ lines | ~250 lines | 150+ lines |
| **TOTAL** | **4700+ lines** | **~2000 lines** | **~2700 lines** |

*Moved to prenatal_constants.dart
**Can use PrenatalTextField instead of _buildTextField

---

## Using Form Components in Modals

**Old way (verbose):**
```dart
_buildSectionHeader('Patient Information', Icons.person),
_buildFormCard([
  Row(
    children: [
      Expanded(
        child: _buildTextField(
          controller: firstNameController,
          label: 'First Name',
          icon: Icons.person_outline,
          hintText: 'Enter first name',
        ),
      ),
      // ...
    ],
  ),
]),
```

**New way (clean):**
```dart
PrenatalSectionHeader(title: 'Patient Information', icon: Icons.person),
PrenatalFormCard(children: [
  Row(children: [
    Expanded(
      child: PrenatalTextField(
        controller: firstNameController,
        label: 'First Name',
        icon: Icons.person_outline,
        hintText: 'Enter first name',
      ),
    ),
    // ...
  ]),
]),
```

---

## Full Refactoring Checklist

- [ ] Add imports for components
- [ ] Delete color constants (use imported ones)
- [ ] Delete `_buildSidebar()` method
- [ ] Delete `_buildTopBar()` method
- [ ] Delete `_buildWebDashboardCard()` method
- [ ] Delete `_buildWebFilterBar()` method
- [ ] Update `build()` method to use components
- [ ] Replace `_buildTextField()` with `PrenatalTextField` in modals
- [ ] Replace `_buildDatePickerField()` with `PrenatalDatePickerField`
- [ ] Replace `_buildDropdownField()` with `PrenatalDropdownField`
- [ ] Replace `_buildSectionHeader()` with `PrenatalSectionHeader`
- [ ] Replace `_buildFormCard()` with `PrenatalFormCard`
- [ ] Test all functionality
- [ ] Run lint checks
- [ ] Update imports in related files

---

## Benefits After Refactoring

✅ File size reduced by ~60%
✅ Easier to maintain and debug
✅ Reusable components across app
✅ Better code organization
✅ Improved readability
✅ Faster development
✅ Better testability
✅ Consistent styling across app
