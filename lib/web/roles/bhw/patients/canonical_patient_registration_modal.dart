import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class CanonicalPatientRegistrationModal extends StatefulWidget {
  const CanonicalPatientRegistrationModal({
    super.key,
    this.patientId,
    this.initialBarangay,
    this.existingPatient,
  });

  final String? patientId;
  final String? initialBarangay;
  final Map<String, dynamic>? existingPatient;

  @override
  State<CanonicalPatientRegistrationModal> createState() =>
      _CanonicalPatientRegistrationModalState();
}

class _CanonicalPatientRegistrationModalState
    extends State<CanonicalPatientRegistrationModal> {
  static const _accent = Color(0xFF2F80ED);
  static const _background = Color(0xFFF5F7FA);
  static const _surface = Colors.white;
  static const _field = Color(0xFFEDF3FA);
  static const _text = Color(0xFF0B1F3A);
  static const _muted = Color(0xFF4B6075);

  final _formKey = GlobalKey<FormState>();
  final _patientService = PatientCenteredHistoryService();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _barangayController = TextEditingController();
  final _householdIdController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _emergencyContactNumberController = TextEditingController();
  final _guardianController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _allergiesController = TextEditingController();

  late final String _patientId;
  DateTime? _dateOfBirth;
  String _sex = 'Female';
  bool _isSaving = false;

  bool get _isEditing => widget.existingPatient != null;

  @override
  void initState() {
    super.initState();
    final patient = widget.existingPatient ?? const <String, dynamic>{};
    _patientId =
        widget.patientId ??
        _textValue(patient['patientId'], fallback: _textValue(patient['id'])) ??
        PatientDatabaseHelper.generatePatientId();
    final legacyName = _splitFullName(_textValue(patient['fullName']) ?? '');
    _firstNameController.text =
        _textValue(patient['firstName'], fallback: legacyName.firstName) ?? '';
    _middleNameController.text =
        _textValue(patient['middleName'], fallback: legacyName.middleName) ??
        '';
    _surnameController.text =
        _textValue(patient['surname'], fallback: legacyName.surname) ?? '';
    _dateOfBirthController.text = _textValue(patient['dateOfBirth']) ?? '';
    _dateOfBirth = DateTime.tryParse(_dateOfBirthController.text);
    _ageController.text = _textValue(patient['age']) ?? '';
    _sex =
        _textValue(
          patient['sex'],
          fallback: _textValue(patient['gender'], fallback: 'Female'),
        ) ??
        'Female';
    if (!const ['Female', 'Male', 'Other'].contains(_sex)) {
      _sex = 'Other';
    }
    _addressController.text =
        _textValue(
          patient['address'],
          fallback: _textValue(patient['street']),
        ) ??
        '';
    _householdIdController.text = _textValue(patient['householdId']) ?? '';
    _contactNumberController.text =
        _textValue(
          patient['contactNumber'],
          fallback: _textValue(patient['phoneNumber']),
        ) ??
        '';
    _emergencyContactController.text =
        _textValue(
          patient['emergencyContact'],
          fallback: _textValue(patient['emergencyContactName']),
        ) ??
        '';
    _emergencyRelationshipController.text =
        _textValue(patient['emergencyRelationship']) ?? '';
    _emergencyContactNumberController.text =
        _textValue(
          patient['emergencyContactNumber'],
          fallback: _textValue(patient['emergencyContactPhone']),
        ) ??
        '';
    _guardianController.text =
        _textValue(
          patient['guardian'],
          fallback: _textValue(patient['parentGuardianName']),
        ) ??
        '';
    _medicalHistoryController.text =
        _textValue(
          patient['medicalHistory'],
          fallback: _textValue(patient['pastMedicalHistory']),
        ) ??
        '';
    _allergiesController.text = _textValue(patient['allergies']) ?? '';

    final initialBarangay = widget.initialBarangay?.trim().isNotEmpty == true
        ? widget.initialBarangay!.trim()
        : (_textValue(patient['barangay']) ?? '');
    if (initialBarangay.isNotEmpty) {
      _barangayController.text = initialBarangay;
    } else {
      _loadAssignedBarangay();
    }
  }

  String? _textValue(dynamic value, {String? fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<void> _loadAssignedBarangay() async {
    final scope = await UserAccessScopeService.instance.loadCurrentScope();
    if (!mounted || scope.barangay.isEmpty) return;
    setState(() => _barangayController.text = scope.barangay);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _surnameController.dispose();
    _dateOfBirthController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _barangayController.dispose();
    _householdIdController.dispose();
    _contactNumberController.dispose();
    _emergencyContactController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyContactNumberController.dispose();
    _guardianController.dispose();
    _medicalHistoryController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: _background,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: _text,
          leading: IconButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Edit Patient' : 'Register Patient',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _isEditing
                    ? 'Update the canonical patient registration record'
                    : 'One-time canonical patient registration',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isEditing
                            ? Icons.save_rounded
                            : Icons.person_add_alt_1_rounded,
                      ),
                label: Text(
                  _isSaving
                      ? (_isEditing ? 'Saving...' : 'Registering...')
                      : (_isEditing ? 'Save Changes' : 'Register Patient'),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _identityBanner(),
                  const SizedBox(height: 20),
                  _section(
                    title: 'Patient Identity',
                    subtitle:
                        'This information becomes the shared identity used by every health service.',
                    children: [
                      _fieldWidget(
                        'First Name',
                        _firstNameController,
                        hint: 'Given name',
                      ),
                      _fieldWidget(
                        'Middle Name',
                        _middleNameController,
                        required: false,
                        hint: 'Optional middle name',
                      ),
                      _fieldWidget(
                        'Surname',
                        _surnameController,
                        hint: 'Family name',
                      ),
                      _dateOfBirthField(),
                      _fieldWidget(
                        'Age',
                        _ageController,
                        readOnly: true,
                        hint: 'Calculated from date of birth',
                      ),
                      _sexField(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _section(
                    title: 'Address and Contact',
                    subtitle:
                        'Used for barangay assignment, household monitoring, and care coordination.',
                    children: [
                      _fieldWidget(
                        'Address',
                        _addressController,
                        maxLines: 2,
                        hint: 'House number, street or purok',
                      ),
                      _fieldWidget(
                        'Barangay',
                        _barangayController,
                        hint: 'Assigned barangay',
                      ),
                      _fieldWidget(
                        'Household ID',
                        _householdIdController,
                        hint: 'Household or family record number',
                      ),
                      _fieldWidget(
                        'Contact Number',
                        _contactNumberController,
                        keyboardType: TextInputType.phone,
                        hint: '09XXXXXXXXX',
                      ),
                      _fieldWidget(
                        'Parent/Guardian Name (Optional)',
                        _guardianController,
                        required: false,
                        hint: 'For children or dependent patients',
                      ),
                      _fieldWidget(
                        'Emergency Contact Name',
                        _emergencyContactController,
                        hint: 'Full name',
                      ),
                      _fieldWidget(
                        'Emergency Contact Relationship',
                        _emergencyRelationshipController,
                        hint: 'e.g., Parent, spouse, sibling',
                      ),
                      _fieldWidget(
                        'Emergency Contact Number',
                        _emergencyContactNumberController,
                        keyboardType: TextInputType.phone,
                        hint: '09XXXXXXXXX',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _section(
                    title: 'Baseline Health Information',
                    subtitle:
                        'Keep this concise; service-specific findings belong in the appropriate health module.',
                    children: [
                      _fieldWidget(
                        'Medical History',
                        _medicalHistoryController,
                        maxLines: 4,
                        hint:
                            'Existing conditions, previous diagnoses, or “None”',
                      ),
                      _fieldWidget(
                        'Allergies (Optional)',
                        _allergiesController,
                        maxLines: 3,
                        required: false,
                        hint:
                            'Food, medicine, environmental allergies, or leave blank',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: _accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isEditing
                                ? 'Saved changes update the patient record used throughout every health-service module.'
                                : 'After registration, this patient becomes searchable in Check-up, Prenatal, Immunization, Morbidity, Mortality, and Referrals.',
                            style: const TextStyle(color: _text, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Patient ID (Auto-generated)',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _patientId,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E5F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.4)),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1200
                  ? 3
                  : constraints.maxWidth >= 760
                  ? 2
                  : 1;
              const gap = 16.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 4,
                children: children
                    .map((child) => SizedBox(width: width, child: child))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldWidget(
    String label,
    TextEditingController controller, {
    bool required = true,
    bool readOnly = false,
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: _text),
        validator: required
            ? (value) =>
                  value?.trim().isEmpty == true ? '$label is required' : null
            : null,
        decoration: _decoration(label, hint: hint),
      ),
    );
  }

  Widget _dateOfBirthField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _dateOfBirthController,
        readOnly: true,
        style: const TextStyle(color: _text),
        validator: (value) =>
            value?.trim().isEmpty == true ? 'Date of Birth is required' : null,
        onTap: _pickDateOfBirth,
        decoration: _decoration(
          'Date of Birth',
          hint: 'Select date',
          suffixIcon: const Icon(Icons.calendar_today_rounded, color: _accent),
        ),
      ),
    );
  }

  Widget _sexField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: _sex,
        dropdownColor: _surface,
        style: const TextStyle(color: _text),
        decoration: _decoration('Sex'),
        items: const ['Female', 'Male', 'Other']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(growable: false),
        onChanged: (value) => setState(() => _sex = value ?? _sex),
      ),
    );
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _muted),
      hintStyle: const TextStyle(color: Color(0xFF7890A6)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E5F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null) return;
    final age = _calculateAge(selected, now);
    setState(() {
      _dateOfBirth = selected;
      _dateOfBirthController.text = selected.toIso8601String().split('T').first;
      _ageController.text = age.toString();
    });
  }

  int _calculateAge(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  ({String firstName, String middleName, String surname}) _splitFullName(
    String fullName,
  ) {
    final normalized = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return (firstName: '', middleName: '', surname: '');
    }
    if (normalized.contains(',')) {
      final parts = normalized.split(',');
      return (
        firstName: parts.skip(1).join(' ').trim(),
        middleName: '',
        surname: parts.first.trim(),
      );
    }
    final parts = normalized.split(' ');
    if (parts.length == 1) {
      return (firstName: parts.first, middleName: '', surname: '');
    }
    return (
      firstName: parts.sublist(0, parts.length - 1).join(' '),
      middleName: '',
      surname: parts.last,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final surname = _surnameController.text.trim();
    if (!_isEditing) {
      final duplicates = await _patientService.findDuplicateCandidates(
        firstName: firstName,
        middleName: middleName,
        surname: surname,
        dateOfBirth: _dateOfBirthController.text,
        phoneNumber: _contactNumberController.text,
      );
      if (!mounted) return;
      if (duplicates.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: const Text(
              'Patient may already be registered',
              style: TextStyle(color: _text),
            ),
            content: const Text(
              'A matching patient record already exists. Search and use the existing patient instead of creating a duplicate.',
              style: TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Review Existing Patient'),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final fullName = [
        firstName,
        middleName,
        surname,
      ].where((value) => value.isNotEmpty).join(' ');
      final address = _addressController.text.trim();
      final contact = _contactNumberController.text.trim();
      final emergencyContact = _emergencyContactController.text.trim();
      final emergencyContactNumber = _emergencyContactNumberController.text
          .trim();
      final medicalHistory = _medicalHistoryController.text.trim();
      final existing = widget.existingPatient ?? const <String, dynamic>{};
      final record = <String, dynamic>{
        ...existing,
        'id': _patientId,
        'patientId': _patientId,
        'fullName': fullName,
        'firstName': firstName,
        'middleName': middleName,
        'surname': surname,
        'dateOfBirth': _dateOfBirthController.text,
        'age': _ageController.text,
        'gender': _sex,
        'sex': _sex,
        'address': address,
        'street': address,
        'barangay': _barangayController.text.trim(),
        'householdId': _householdIdController.text.trim(),
        'contactNumber': contact,
        'phoneNumber': contact,
        'emergencyContact': emergencyContact,
        'emergencyContactName': emergencyContact,
        'emergencyRelationship': _emergencyRelationshipController.text.trim(),
        'emergencyContactNumber': emergencyContactNumber,
        'emergencyContactPhone': emergencyContactNumber,
        'guardian': _guardianController.text.trim(),
        'medicalHistory': medicalHistory,
        'pastMedicalHistory': medicalHistory,
        'allergies': _allergiesController.text.trim(),
        'registrationDate': _isEditing
            ? (existing['registrationDate'] ?? DateTime.now().toIso8601String())
            : DateTime.now().toIso8601String(),
        'registeredBy': _isEditing
            ? (existing['registeredBy'] ??
                  user?.displayName ??
                  user?.email ??
                  'BHW')
            : (user?.displayName ?? user?.email ?? 'BHW'),
        'consentGiven': 'true',
        'status': existing['status'] ?? 'Active',
      };
      if (_isEditing) {
        final recordId = _textValue(existing['id'], fallback: _patientId)!;
        final updated = await PatientDatabaseHelper.instance.updateRecord(
          recordId,
          record,
        );
        if (updated == 0) {
          throw StateError('The patient record could not be updated.');
        }
      } else {
        await PatientDatabaseHelper.instance.insertRecord(record);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Patient update failed: $error'
                : 'Patient registration failed: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _isSaving = false);
    }
  }
}
