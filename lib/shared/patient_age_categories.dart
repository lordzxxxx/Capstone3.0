/// Shared age categories for patient demographics and operational reports.
///
/// Immunization dose schedules may use their own month-based clinical
/// groupings; this definition is for patient-level age classification only.
enum PatientAgeCategory { child, adolescent, adult, olderAdult }

extension PatientAgeCategoryLabel on PatientAgeCategory {
  String get label => switch (this) {
    PatientAgeCategory.child => '0–5',
    PatientAgeCategory.adolescent => '6–17',
    PatientAgeCategory.adult => '18–59',
    PatientAgeCategory.olderAdult => '60+',
  };
}

abstract final class PatientAgeCategories {
  static const List<PatientAgeCategory> ordered = <PatientAgeCategory>[
    PatientAgeCategory.child,
    PatientAgeCategory.adolescent,
    PatientAgeCategory.adult,
    PatientAgeCategory.olderAdult,
  ];

  static PatientAgeCategory? forYears(int? age) {
    if (age == null || age < 0 || age > 130) return null;
    if (age <= 5) return PatientAgeCategory.child;
    if (age <= 17) return PatientAgeCategory.adolescent;
    if (age <= 59) return PatientAgeCategory.adult;
    return PatientAgeCategory.olderAdult;
  }

  static int? parseYears(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) {
      return value.toInt();
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final match = RegExp(r'^(\d{1,3})(?:\s*(?:years?|y))?$').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static PatientAgeCategory? forValue(Object? value) =>
      forYears(parseYears(value));

  static int? fromBirthDate(DateTime? birthDate, {DateTime? today}) {
    if (birthDate == null) return null;
    final current = today ?? DateTime.now();
    if (birthDate.isAfter(current)) return null;
    var age = current.year - birthDate.year;
    final birthdayHasPassed =
        current.month > birthDate.month ||
        (current.month == birthDate.month && current.day >= birthDate.day);
    if (!birthdayHasPassed) age--;
    return age;
  }
}
