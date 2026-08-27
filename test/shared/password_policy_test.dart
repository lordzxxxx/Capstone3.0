import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/password_policy.dart';

void main() {
  test('accepts a strong password', () {
    expect(PasswordPolicy.isValid('Abcdef1!'), isTrue);
    expect(PasswordPolicy.validationMessage('Abcdef1!'), isEmpty);
  });

  test('rejects passwords missing required character classes', () {
    expect(PasswordPolicy.isValid('abcdefgh'), isFalse);
    final message = PasswordPolicy.validationMessage('abcdefgh');
    expect(message, contains('uppercase'));
    expect(message, contains('number'));
    expect(message, contains('special'));
  });

  test('rejects passwords outside the supported length range', () {
    expect(PasswordPolicy.isValid('Aa1!'), isFalse);
    expect(
      PasswordPolicy.isValid('Aa1!${List.filled(125, 'x').join()}'),
      isFalse,
    );
  });
}
