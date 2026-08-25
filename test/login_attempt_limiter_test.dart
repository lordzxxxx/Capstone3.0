import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/login_attempt_limiter.dart';

void main() {
  test('applies a cooldown after repeated credential failures', () {
    const email = 'rate-limit-test@example.com';
    LoginAttemptLimiter.clear(email);

    for (var attempt = 0; attempt < 5; attempt++) {
      LoginAttemptLimiter.recordFailure(email);
    }

    expect(LoginAttemptLimiter.remaining(email), isNotNull);
    LoginAttemptLimiter.clear(email);
    expect(LoginAttemptLimiter.remaining(email), isNull);
  });
}
