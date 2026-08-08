import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mycapstone_project/app/core/services/cloud_functions_config.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _lightOffWhite = Color(0xFFF5F5F5);

class ResetWithCode extends StatefulWidget {
  final String email;
  const ResetWithCode({super.key, required this.email});

  @override
  State<ResetWithCode> createState() => _ResetWithCodeState();
}

class _ResetWithCodeState extends State<ResetWithCode> {
  final TextEditingController codeController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    final code = codeController.text.trim();
    final pwd = passwordController.text;
    final confirm = confirmController.text;

    if (code.isEmpty || pwd.isEmpty || confirm.isEmpty) {
      Get.snackbar('Error', 'Please fill all fields', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
      return;
    }
    if (code.length != 4) {
      Get.snackbar('Error', 'Code must be 4 digits', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
      return;
    }
    if (pwd != confirm) {
      Get.snackbar('Error', 'Passwords do not match', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
      return;
    }
    if (pwd.length < 6) {
      Get.snackbar('Error', 'Password must be at least 6 characters', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Call Cloud Function to complete password reset
      final response = await http.post(
        Uri.parse(CloudFunctionsConfig.completePasswordResetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
          'code': code,
          'newPassword': pwd,
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        Get.snackbar('Success', 'Password reset successfully. Please sign in.', backgroundColor: const Color(0xFF388E3C), colorText: Colors.white);
        Future.delayed(const Duration(seconds: 2), () => Get.offAll(() => const SizedBox()));
      } else {
        Get.snackbar('Failed', body['error'] ?? 'Failed to reset password', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar('Failed', 'Network or server error: $e', backgroundColor: const Color(0xFFD32F2F), colorText: Colors.white);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightOffWhite,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter the 4-digit code sent to ${widget.email}'),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(hintText: '1234'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'New password'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Confirm password'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryAqua),
                  child: _isLoading ? const CircularProgressIndicator() : const Text('Reset Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
