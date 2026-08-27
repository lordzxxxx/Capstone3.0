/// The password policy shared by every password-creation surface.
///
/// Existing passwords are intentionally not evaluated with this policy during
/// sign-in. The policy applies when a password is created, changed, or reset.
abstract final class PasswordPolicy {
  static const int minimumLength = 8;
  static const int maximumLength = 128;

  static const List<String> requirementLabels = <String>[
    'At least 8 characters',
    'One uppercase letter',
    'One lowercase letter',
    'One number',
    'One special character',
  ];

  static List<String> unmetRequirements(String password) {
    final unmet = <String>[];
    if (password.length < minimumLength) {
      unmet.add(requirementLabels[0]);
    }
    if (password.length > maximumLength) {
      unmet.add('No more than 128 characters');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      unmet.add(requirementLabels[1]);
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      unmet.add(requirementLabels[2]);
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      unmet.add(requirementLabels[3]);
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      unmet.add(requirementLabels[4]);
    }
    return unmet;
  }

  static bool isValid(String password) => unmetRequirements(password).isEmpty;

  static String validationMessage(String password) {
    final unmet = unmetRequirements(password);
    if (unmet.isEmpty) return '';
    return 'Password must include ${unmet.join(', ')}.';
  }
}
