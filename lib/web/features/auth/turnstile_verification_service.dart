import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TurnstileVerificationException implements Exception {
  const TurnstileVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TurnstileVerificationService {
  TurnstileVerificationService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = String.fromEnvironment('AI_API_BASE_URL');
  final http.Client _client;

  Future<void> verify({required String? token, required String action}) async {
    if (!kIsWeb) return;
    if (token == null || token.trim().isEmpty) {
      throw const TurnstileVerificationException(
        'Complete the security check before continuing.',
      );
    }
    if (_baseUrl.trim().isEmpty) {
      throw const TurnstileVerificationException(
        'Security verification is not connected to the API yet.',
      );
    }

    final response = await _client
        .post(
          Uri.parse(
            '${_baseUrl.replaceFirst(RegExp(r'/$'), '')}/security/turnstile/verify',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token, 'action': action}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Security verification failed. Please try again.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {}
      throw TurnstileVerificationException(message);
    }
  }

  void close() => _client.close();
}
