import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/features/auth/reset_password_service.dart';
import 'package:mycapstone_project/app/features/auth/verification_code.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.navySoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.subtle;
const Color _lightOffWhite = AppDesign.ink;
const Color _sidebarDark = Colors.white;
const Color _panelSurface = AppDesign.page;

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> resetPassword() async {
    final String email = emailController.text.trim();
    if (email.isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter your email address',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Send verification code to email
      await ResetPasswordService.sendVerificationCode(email);

      setState(() => _isLoading = false);

      Get.snackbar(
        'Success',
        'Verification code sent to your email',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
      );

      // Navigate to verification screen
      Future.delayed(const Duration(milliseconds: 500), () {
        Get.offAllNamed(
          MobileRoutes.verificationCode,
          arguments: {'email': email},
        );
      });
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        'Reset Failed',
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppDesign.navy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            Get.offAllNamed(MobileRoutes.login);
          },
        ),
        title: Text(
          'Forgot Password',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: Colors.white),
        ),
      ),
      body: Container(
        color: AppDesign.page,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.16),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _panelSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Secure Recovery',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _primaryAqua,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: _panelSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.22),
                          width: 1.6,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_reset,
                        color: _primaryAqua,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Reset Password',
                    style: Theme.of(
                      context,
                    ).textTheme.displaySmall?.copyWith(color: _darkDeepTeal),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your email address and we\'ll send you a verification code to reset your password.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppDesign.muted),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Email Address',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: _darkDeepTeal),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: _darkDeepTeal),
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      hintStyle: TextStyle(color: AppDesign.subtle),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: _primaryAqua,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _primaryAqua.withValues(alpha: 0.20),
                          width: 1.2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _primaryAqua.withValues(alpha: 0.20),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _primaryAqua,
                          width: 1.8,
                        ),
                      ),
                      filled: true,
                      fillColor: _panelSurface,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Send Verification Code',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Remember your password? ',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppDesign.muted),
                        ),
                        GestureDetector(
                          onTap: () {
                            Get.offAllNamed(MobileRoutes.login);
                          },
                          child: Text(
                            'Sign In',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _primaryAqua,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
