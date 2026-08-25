/// Client-side backoff for repeated password attempts.
///
/// Firebase Authentication remains the authoritative server-side limiter.
/// This layer reduces accidental rapid retries and gives the user a clear
/// cooldown before another request is sent. It is intentionally in-memory;
/// it is not treated as an authorization control and stores no password.
class LoginAttemptLimiter {
  LoginAttemptLimiter._();

  static const int _maxFailures = 5;
  static const Duration _window = Duration(minutes: 1);
  static const int _maxTrackedEmails = 1000;
  static final Map<String, _AttemptState> _attempts = <String, _AttemptState>{};

  static Duration? remaining(String email) {
    final key = _normalize(email);
    final state = _attempts[key];
    if (state == null) return null;
    final elapsed = DateTime.now().difference(state.firstFailure);
    if (elapsed >= _window) {
      _attempts.remove(key);
      return null;
    }
    if (state.failures < _maxFailures) return null;
    return _window - elapsed;
  }

  static void recordFailure(String email) {
    final key = _normalize(email);
    if (key.isEmpty) return;
    final now = DateTime.now();
    final current = _attempts[key];
    if (current == null || now.difference(current.firstFailure) >= _window) {
      _attempts[key] = _AttemptState(firstFailure: now, failures: 1);
    } else {
      _attempts[key] = _AttemptState(
        firstFailure: current.firstFailure,
        failures: current.failures + 1,
      );
    }
    _trimStaleEntries(now);
  }

  static void clear(String email) => _attempts.remove(_normalize(email));

  static String _normalize(String email) => email.trim().toLowerCase();

  static void _trimStaleEntries(DateTime now) {
    _attempts.removeWhere(
      (_, state) => now.difference(state.firstFailure) >= _window,
    );
    if (_attempts.length <= _maxTrackedEmails) return;
    final oldest = _attempts.keys.first;
    _attempts.remove(oldest);
  }
}

class _AttemptState {
  const _AttemptState({required this.firstFailure, required this.failures});

  final DateTime firstFailure;
  final int failures;
}
