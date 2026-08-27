import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/reset_password_service.dart';
import 'package:mycapstone_project/app/features/auth/new_password.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.page;

class VerificationCode extends StatefulWidget {
  final String email;

  const VerificationCode({super.key, required this.email});

  @override
  State<VerificationCode> createState() => _VerificationCodeState();
}

class _VerificationCodeState extends State<VerificationCode> {
  final List<TextEditingController> codeControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  void _startResendCountdown() {
    // Can resend after 30 seconds
    _resendCountdown = 30;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCountdown > 0) {
        setState(() => _resendCountdown--);
        _startResendCountdown();
      }
    });
  }

  void _onCodeInputChange(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        focusNodes[index + 1].requestFocus();
      } else {
        focusNodes[index].unfocus();
      }
    }
  }

  void _onCodeBackspace(String value, int index) {
    if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    if (_isLoading) return;
    final String code = codeControllers.map((c) => c.text).join();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please enter all 6 digits';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ResetPasswordService.verifyCode(widget.email, code);

      if (!mounted) return;
      setState(() => _isLoading = false);

      Get.snackbar(
        'Success',
        'Verification code confirmed!',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
      );

      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        Get.offNamed(
          MobileRoutes.newPassword,
          arguments: {'email': widget.email, 'code': code},
        );
      });
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().toLowerCase();
      setState(() {
        _hasError = true;
        _errorMessage = errorText.contains('too many')
            ? 'Too many attempts. Request a new code later.'
            : 'The verification code is invalid or expired. Request a new code.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resendCode() async {
    if (_resendCountdown > 0 || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      await ResetPasswordService.resendVerificationCode(widget.email);
      if (!mounted) return;
      setState(() => _isLoading = false);

      Get.snackbar(
        'Success',
        'New verification code sent to your email',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
      );

      // Clear previous codes
      for (var controller in codeControllers) {
        controller.clear();
      }
      focusNodes[0].requestFocus();
      _startResendCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        final errorText = e.toString().toLowerCase();
        _errorMessage = errorText.contains('too many')
            ? 'Too many requests. Please wait before requesting another code.'
            : 'Unable to resend the code right now. Please try again later.';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    for (var controller in codeControllers) {
      controller.dispose();
    }
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          'Verify Code',
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
                  child: const Icon(
                    Icons.mail_outline,
                    color: _primaryAqua,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Verification Code',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: _darkDeepTeal),
              ),
              const SizedBox(height: 8),
              Text(
                'We\'ve sent a 6-digit verification code to ${widget.email}',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: _mutedCoolGray),
              ),
              const SizedBox(height: 32),
              Text(
                'Enter Code',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: _darkDeepTeal),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) => SizedBox(
                    width: 50,
                    height: 60,
                    child: TextField(
                      controller: codeControllers[index],
                      focusNode: focusNodes[index],
                      onChanged: (value) {
                        if (value.length > 1) {
                          codeControllers[index].text = value[value.length - 1];
                        }
                        _onCodeInputChange(value, index);
                        // Clear error on input
                        if (_hasError) {
                          setState(() => _hasError = false);
                        }
                      },
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 1,
                      style: const TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counter: const SizedBox.shrink(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _hasError ? Colors.red : _mutedCoolGray,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _hasError ? Colors.red : _mutedCoolGray,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _hasError ? Colors.red : _primaryAqua,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
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
                              _darkDeepTeal,
                            ),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Verify Code',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: _darkDeepTeal),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Didn\'t receive the code?',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _resendCountdown == 0 ? _resendCode : null,
                      child: Text(
                        _resendCountdown > 0
                            ? 'Resend in $_resendCountdown seconds'
                            : 'Resend Code',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _resendCountdown > 0
                                  ? _mutedCoolGray
                                  : _primaryAqua,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
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
