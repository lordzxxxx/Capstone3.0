import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/navigation/web_role_gate.dart';

void main() {
  group('WebRoleGate role policy', () {
    const bhwRoles = <String>{'bhw'};
    const choRoles = <String>{'cho', 'cho_super_admin', 'super_admin', 'admin'};

    test('normalizes role values before checking access', () {
      expect(WebRoleGate.isAllowed(' BHW ', bhwRoles), isTrue);
      expect(WebRoleGate.isAllowed('Cho', choRoles), isTrue);
    });

    test('does not cross role boundaries', () {
      expect(WebRoleGate.isAllowed('cho', bhwRoles), isFalse);
      expect(WebRoleGate.isAllowed('bhw', choRoles), isFalse);
      expect(WebRoleGate.isAllowed('doctor', choRoles), isFalse);
    });

    test('returns an authenticated user to their permitted portal', () {
      expect(WebRoleGate.fallbackForRole('bhw'), '/bhw/dashboard');
      expect(WebRoleGate.fallbackForRole('CHO'), '/cho/dashboard');
      expect(WebRoleGate.fallbackForRole('doctor'), '/doctor/referrals');
      expect(
        WebRoleGate.fallbackForRole('unknown', defaultRoute: '/aidsuhis'),
        '/aidsuhis',
      );
    });
  });
}
