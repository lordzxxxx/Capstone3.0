import 'package:mycapstone_project/app/core/services/cloud_functions_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResetPasswordService {
  static String? _resetSessionToken;

  static Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required String action,
  }) {
    final body = response.body.trim();
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';

    if (body.isEmpty ||
        (!contentType.contains('application/json') &&
            !body.startsWith('{'))) {
      throw Exception(
        'Password reset service is unavailable while trying to $action. '
        'Please try again later.',
      );
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Converted below into a stable, user-friendly service error.
    }

    throw Exception(
      'Password reset service returned an invalid response while trying to '
      '$action. Please try again later.',
    );
  }

  /// Generates a random 6-digit code (kept for reference)
  static String generateVerificationCode() {
    final random = DateTime.now().microsecond % 1000000;
    return (100000 + (random % 900000)).toString();
  }

  /// Sends verification code to email via Cloud Function
  static Future<bool> sendVerificationCode(String email) async {
    try {
      _resetSessionToken = null;
      // Call Cloud Function to send password reset email
      final response = await http.post(
        Uri.parse(CloudFunctionsConfig.sendPasswordResetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));

      final responseData = _decodeResponse(
        response,
        action: 'send the verification code',
      );

      if (response.statusCode == 200 && responseData['success'] == true) {
        // ignore: avoid_print
        print('Verification code sent to $email');
        return true;
      } else {
        throw Exception(responseData['error'] ?? 'Failed to send verification code');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error sending verification code: $e');
      rethrow;
    }
  }

  /// Verifies the code via Cloud Function
  static Future<bool> verifyCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse(CloudFunctionsConfig.verifyResetCodeUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      ).timeout(const Duration(seconds: 15));

      final responseData = _decodeResponse(
        response,
        action: 'verify the code',
      );

      if (response.statusCode == 200 && responseData['success'] == true) {
        final sessionToken = responseData['sessionToken']?.toString();
        if (sessionToken == null || sessionToken.isEmpty) {
          throw Exception('The verification session could not be created.');
        }
        _resetSessionToken = sessionToken;
        // ignore: avoid_print
        print('Code verified successfully');
        return true;
      } else {
        throw Exception(responseData['error'] ?? 'Invalid verification code');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error verifying code: $e');
      rethrow;
    }
  }

  /// Completes the password reset using Cloud Function
  static Future<bool> completePasswordReset(
    String email,
    String newPassword,
  ) async {
    try {
      final sessionToken = _resetSessionToken;
      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception(
          'Your verification session has expired. Please request a new code.',
        );
      }

      final response = await http.post(
        Uri.parse(CloudFunctionsConfig.completePasswordResetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'sessionToken': sessionToken,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = _decodeResponse(
        response,
        action: 'reset the password',
      );

      if (response.statusCode == 200 && responseData['success'] == true) {
        _resetSessionToken = null;
        // ignore: avoid_print
        print('Password reset completed successfully');
        return true;
      } else {
        throw Exception(responseData['error'] ?? 'Failed to reset password');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error completing password reset: $e');
      rethrow;
    }
  }

/// Resends verification code via Cloud Function
  static Future<bool> resendVerificationCode(String email) async {
    try {
      // Just call sendVerificationCode again - the Cloud Function handles rate limiting
      return await sendVerificationCode(email);
    } catch (e) {
      // ignore: avoid_print
      print('Error resending code: $e');
      rethrow;
    }
  }
}
