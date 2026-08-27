import 'package:mycapstone_project/shared/patient_age_categories.dart';

/// Small, dependency-free validators shared by the mobile and web forms.
/// Backend rules/functions remain authoritative; these messages keep the UI
/// aligned with those boundaries and prevent avoidable malformed writes.
abstract final class InputValidation {
  static final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp phonePattern = RegExp(r'^[0-9+()\-\s]{7,24}$');
  static final RegExp patientIdPattern = RegExp(r'^[A-Za-z0-9._\-/ ]{1,64}$');
  static final RegExp dosePattern = RegExp(
    r'^[0-9]{1,2}(?:st|nd|rd|th)?(?:\s+dose)?$',
    caseSensitive: false,
  );

  static String? requiredText(
    String? value, {
    required String label,
    int maxLength = 120,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    return null;
  }

  static String? optionalText(
    String? value, {
    required String label,
    int maxLength = 120,
  }) {
    final text = value?.trim() ?? '';
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    return null;
  }

  static bool isEmail(String value) =>
      value.length <= 320 && emailPattern.hasMatch(value.trim());

  static String? email(String? value, {bool required = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Email is required.' : null;
    return isEmail(text) ? null : 'Enter a valid email address.';
  }

  static String? phone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return phonePattern.hasMatch(text)
        ? null
        : 'Enter a valid phone number using digits, spaces, or + - ( ).';
  }

  static String? patientId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Patient ID is required.';
    return patientIdPattern.hasMatch(text)
        ? null
        : 'Use up to 64 letters, numbers, spaces, dots, dashes, or slashes.';
  }

  static String? age(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Age is required.' : null;
    final age = PatientAgeCategories.parseYears(text);
    return PatientAgeCategories.forYears(age) == null
        ? 'Enter an age from 0 to 130 years.'
        : null;
  }

  static String? dose(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return dosePattern.hasMatch(text)
        ? null
        : 'Enter a dose such as 1, 1st dose, or 2nd dose.';
  }
}
