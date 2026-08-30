import 'package:mycapstone_project/shared/patient_age_categories.dart';

/// Generic dose labels shared by the web and mobile immunization forms.
///
/// Vaccine-specific schedules are not inferred here. The existing patient
/// history remains the source of truth, while this list provides safe,
/// structured labels for records that do not have a configured schedule.
const List<String> kImmunizationDoseOptions = <String>[
  'Initial',
  'Dose 1',
  'Dose 2',
  'Dose 3',
  'Booster',
];

const List<String> kImmunizationRouteOptions = <String>[
  'Intramuscular (IM)',
  'Subcutaneous (SC)',
  'Intradermal (ID)',
  'Oral (PO)',
  'Oral',
  'Intranasal',
];

const List<String> kImmunizationSiteOptions = <String>[
  'Left Upper Arm',
  'Right Upper Arm',
  'Left Thigh',
  'Right Thigh',
  'Left Buttock',
  'Right Buttock',
  'Abdomen',
  'Buttocks',
];

String immunizationRecordText(
  Map<String, dynamic> record,
  Iterable<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = record[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

/// Returns a stable patient key for grouping immunizations into one history.
/// Patient IDs are preferred over display names so two patients with the same
/// name cannot share a vaccination history.
String immunizationPatientKey(Map<String, dynamic> record) {
  final patientId = immunizationRecordText(record, const [
    'patientId',
    'linkedPatientId',
    'patientRecordId',
  ]);
  if (patientId.isNotEmpty) return 'id:${patientId.toLowerCase()}';

  final patientName = immunizationRecordText(record, const [
    'patientName',
    'fullName',
    'patient',
    'name',
  ]);
  return 'name:${patientName.toLowerCase()}';
}

PatientAgeCategory? immunizationPatientAgeCategory(
  Map<String, dynamic> patient, {
  DateTime? today,
}) {
  final byAge = PatientAgeCategories.forValue(patient['age']);
  if (byAge != null) return byAge;

  final rawBirthDate = patient['dateOfBirth'] ?? patient['dob'];
  final birthDate = rawBirthDate is DateTime
      ? rawBirthDate
      : DateTime.tryParse(rawBirthDate?.toString().trim() ?? '');
  final age = PatientAgeCategories.fromBirthDate(birthDate, today: today);
  return PatientAgeCategories.forYears(age);
}

bool immunizationPatientIsPediatric(Map<String, dynamic> patient) {
  final category = immunizationPatientAgeCategory(patient);
  return category == PatientAgeCategory.child ||
      category == PatientAgeCategory.adolescent;
}

/// Keeps an existing legacy/custom dose selectable while offering structured
/// options for new records. This avoids silently changing historical data.
List<String> immunizationDoseOptions({String? existing}) {
  final value = existing?.trim() ?? '';
  if (value.isEmpty || kImmunizationDoseOptions.contains(value)) {
    return kImmunizationDoseOptions;
  }
  return <String>[value, ...kImmunizationDoseOptions];
}

bool immunizationLooksLikeDuplicate(
  Map<String, dynamic> existing,
  Map<String, dynamic> candidate, {
  String? excludeId,
}) {
  final existingId = existing['id']?.toString().trim() ?? '';
  if (excludeId != null && existingId == excludeId.trim()) return false;

  final existingVaccine = immunizationRecordText(existing, const [
    'vaccine',
    'vaccineType',
    'vaccineName',
  ]);
  final candidateVaccine = immunizationRecordText(candidate, const [
    'vaccine',
    'vaccineType',
    'vaccineName',
  ]);
  final existingDose = immunizationRecordText(existing, const [
    'doseNumber',
    'dose',
  ]);
  final candidateDose = immunizationRecordText(candidate, const [
    'doseNumber',
    'dose',
  ]);
  final existingDate = immunizationRecordText(existing, const [
    'administrationDate',
    'date',
  ]);
  final candidateDate = immunizationRecordText(candidate, const [
    'administrationDate',
    'date',
  ]);
  if (existingVaccine.isEmpty ||
      candidateVaccine.isEmpty ||
      existingDose.isEmpty ||
      candidateDose.isEmpty ||
      existingDate.isEmpty ||
      candidateDate.isEmpty) {
    return false;
  }
  String dateToken(String value) =>
      value.length <= 10 ? value : value.substring(0, 10);
  return immunizationPatientKey(existing) ==
          immunizationPatientKey(candidate) &&
      existingVaccine.toLowerCase() == candidateVaccine.toLowerCase() &&
      existingDose.toLowerCase() == candidateDose.toLowerCase() &&
      dateToken(existingDate) == dateToken(candidateDate);
}

/// Builds the backwards-compatible identity snapshot stored on an
/// immunization event. The patient record remains authoritative; these fields
/// only preserve legacy list/search compatibility.
Map<String, dynamic> immunizationIdentitySnapshot({
  required Map<String, dynamic> patient,
  Map<String, dynamic> fallback = const <String, dynamic>{},
}) {
  String firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  final patientId = firstNonEmpty([
    patient['patientId'],
    patient['id'],
    fallback['patientId'],
    fallback['linkedPatientId'],
  ]);
  final linkedPatientId = firstNonEmpty([
    patient['patientId'],
    patient['id'],
    fallback['linkedPatientId'],
    fallback['patientId'],
  ]);
  final firstName = firstNonEmpty([
    patient['firstName'],
    fallback['firstName'],
  ]);
  final middleName = firstNonEmpty([
    patient['middleName'],
    fallback['middleName'],
  ]);
  final surname = firstNonEmpty([
    patient['surname'],
    patient['lastName'],
    fallback['surname'],
  ]);
  final patientName = firstNonEmpty([
    patient['fullName'],
    patient['patientName'],
    fallback['patientName'],
    [
      firstName,
      middleName,
      surname,
    ].where((value) => value.isNotEmpty).join(' '),
  ]);
  final contactNumber = firstNonEmpty([
    patient['contactNumber'],
    patient['phoneNumber'],
    patient['phone'],
    fallback['contactNumber'],
  ]);
  final guardian = firstNonEmpty([
    patient['guardian'],
    patient['parentGuardianName'],
    fallback['parentGuardianName'],
  ]);

  return <String, dynamic>{
    if (patientId.isNotEmpty) 'patientId': patientId,
    if (linkedPatientId.isNotEmpty) 'linkedPatientId': linkedPatientId,
    if (patientName.isNotEmpty) 'patientName': patientName,
    'firstName': firstName,
    'middleName': middleName,
    'surname': surname,
    'age': firstNonEmpty([patient['age'], fallback['age']]),
    'contactNumber': contactNumber,
    if (immunizationPatientIsPediatric(patient) && guardian.isNotEmpty)
      'parentGuardianName': guardian,
  };
}
