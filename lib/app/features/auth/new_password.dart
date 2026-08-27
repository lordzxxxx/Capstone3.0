import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/reset_password_service.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/shared/password_policy.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.page;

class NewPassword extends StatefulWidget {
  final String email;
  final String code;

  const NewPassword({super.key, required this.email, required this.code});

  @override
  State<NewPassword> createState() => _NewPasswordState();
}

class _NewPasswordState extends State<NewPassword> {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _passwordStrength = '';
  Color _strengthColor = Colors.grey;

  List<String> _getPasswordRequirements() {
    return PasswordPolicy.unmetRequirements(passwordController.text);
  }

  void _updatePasswordStrength() {
    if (!mounted) return;
    final List<String> unmet = _getPasswordRequirements();
    setState(() {
      if (unmet.isEmpty) {
        _passwordStrength = 'Strong';
        _strengthColor = const Color(0xFF388E3C);
      } else if (unmet.length <= 2) {
        _passwordStrength = 'Medium';
        _strengthColor = Colors.orange;
      } else {
        _passwordStrength = 'Weak';
        _strengthColor = Colors.red;
      }
    });
  }

  Future<void> _resetPassword() async {
    if (_isLoading) return;
    final String password = passwordController.text;
    final String confirmPassword = confirmPasswordController.text;

    // Validate inputs
    if (password.isEmpty || confirmPassword.isEmpty) {
      Get.snackbar(
        'Error',
        'Please fill in all fields',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (password != confirmPassword) {
      Get.snackbar(
        'Error',
        'Passwords do not match',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    final List<String> unmet = _getPasswordRequirements();
    if (unmet.isNotEmpty) {
      Get.snackbar(
        'Weak Password',
        'Password does not meet requirements',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Complete the password reset via Cloud Function
      await ResetPasswordService.completePasswordReset(widget.email, password);

      if (!mounted) return;
      setState(() => _isLoading = false);

      Get.snackbar(
        'Success',
        'Password reset successfully!',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Get.offAllNamed(MobileRoutes.login);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Get.snackbar(
        'Reset Failed',
        'Unable to reset the password right now. Please request a new code and try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    passwordController.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> unmet = _getPasswordRequirements();

    return Scaffold(
      backgroundColor: _lightOffWhite,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _darkDeepTeal,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _lightOffWhite),
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
          'Reset Password',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: _lightOffWhite),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryAqua, width: 2),
                  ),
                  child: const Icon(Icons.lock, color: _primaryAqua, size: 50),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Create New Password',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: _darkDeepTeal),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a strong password for your account',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: _mutedCoolGray),
              ),
              const SizedBox(height: 32),
              // New Password Field
              Text(
                'New Password',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: _darkDeepTeal),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: _darkDeepTeal),
                decoration: InputDecoration(
                  hintText: 'Enter new password',
                  hintStyle: const TextStyle(color: _mutedCoolGray),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: _primaryAqua,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: _mutedCoolGray,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _mutedCoolGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _mutedCoolGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _primaryAqua, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // Password Strength Indicator
              if (passwordController.text.isNotEmpty)
                Row(
                  children: [
                    Text(
                      'Strength: ',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
                    ),
                    Text(
                      _passwordStrength,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _strengthColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              // Requirements List
              if (unmet.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Password needs:',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...unmet.map(
                        (requirement) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Icon(Icons.close, size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(
                                requirement,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (passwordController.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF388E3C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF388E3C).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: Color(0xFF388E3C),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Password requirements met',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF388E3C),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // Confirm Password Field
              Text(
                'Confirm Password',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: _darkDeepTeal),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: const TextStyle(color: _darkDeepTeal),
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  hintStyle: const TextStyle(color: _mutedCoolGray),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: _primaryAqua,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: _mutedCoolGray,
                    ),
                    onPressed: () {
                      setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _mutedCoolGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _mutedCoolGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _primaryAqua, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // Password Match Indicator
              if (confirmPasswordController.text.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      passwordController.text == confirmPasswordController.text
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          passwordController.text ==
                              confirmPasswordController.text
                          ? const Color(0xFF388E3C)
                          : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      passwordController.text == confirmPasswordController.text
                          ? 'Passwords match'
                          : 'Passwords do not match',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            passwordController.text ==
                                confirmPasswordController.text
                            ? const Color(0xFF388E3C)
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      unmet.isEmpty &&
                          passwordController.text.isNotEmpty &&
                          confirmPasswordController.text.isNotEmpty &&
                          passwordController.text ==
                              confirmPasswordController.text &&
                          !_isLoading
                      ? _resetPassword
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _primaryAqua.withValues(
                      alpha: 0.5,
                    ),
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
                              _darkDeepTeal,
                            ),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Reset Password',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: _darkDeepTeal),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () {
                    Get.offAllNamed(MobileRoutes.login);
                  },
                  child: Text(
                    'Back to Login',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _primaryAqua,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
