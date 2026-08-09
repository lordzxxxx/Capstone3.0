import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFFF8FBFF);
const Color _sidebarDark = Color(0xFF0D274D);
const Color _panelSurface = Color(0xFF0D274D);

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
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
      // Use Firebase's built-in password reset email (sends a link)
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      Get.snackbar(
        'Reset Email Sent',
        'A password reset link has been sent to $email. Check your inbox and spam folder.',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is badly formatted.';
          break;
        case 'too-many-requests':
          message = 'Too many requests. Try again later.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check your connection.';
          break;
        default:
          message = e.message ?? 'Failed to send password reset email.';
      }

      final displayMessage = kDebugMode ? '$message (${e.code})' : message;
      Get.snackbar(
        'Reset Failed',
        displayMessage,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('Password reset error: code=${e.code} message=${e.message}');
      }
    } catch (e) {
      Get.snackbar(
        'Reset Failed',
        'Unexpected error. Please try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('Unexpected reset error: $e');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Widget _buildBackdropOrb({required double size, required Color color}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: _primaryAqua, size: 24),
        ),
        const SizedBox(width: 16),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            color: _lightOffWhite,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 900;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Inter'),
      ),
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        body: Stack(
          children: [
            // Same bg2.2.png hero photo as login/signup/BHW registration, with
            // a deep navy/teal scrim, so this page reads as part of the same
            // auth flow rather than a separate utility screen.
            Positioned.fill(
              child: Image.asset(
                'assets/bg2.2.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(color: _darkDeepTeal);
                },
              ),
            ),
            Positioned.fill(
              child: const ColoredBox(color: Color(0xD9071A33)),
            ),

            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWideScreen ? 0 : 24,
                      vertical: 40,
                    ),
                    child: isWideScreen
                        ? _buildWideScreenLayout(context)
                        : _buildMobileLayout(context),
                  ),
                ),
              ),
            ),

            // Back button
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _sidebarDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: _lightOffWhite,
                      size: 24,
                    ),
                  ),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                      return;
                    }
                    replaceWithAuthPage(
                      context,
                      const Login(),
                      begin: const Offset(-0.06, 0),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Wide screen layout
  Widget _buildWideScreenLayout(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Row(
        children: [
          // Left side - Info
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.all(60),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primaryAqua.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/bg3.png',
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [_primaryAqua, _secondaryIceBlue],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Logo',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  Text(
                    'DSUHIS',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _lightOffWhite,
                      height: 1.2,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Smart Health Integration System',
                    style: TextStyle(
                      fontSize: 18,
                      color: _lightOffWhite.withValues(alpha: 0.82),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildFeatureItem(
                    Icons.mark_email_read_outlined,
                    'Secure Email Recovery',
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    Icons.verified_user_outlined,
                    'Protected Account Access',
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    Icons.lock_clock_outlined,
                    'Fast Reset Workflow',
                  ),
                ],
              ),
            ),
          ),

          // Right side - Reset form
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              child: _buildResetCard(context, isCompact: false),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile layout
  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryAqua.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/bg3.png',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_primaryAqua, _secondaryIceBlue],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Logo',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 30),

        _buildResetCard(context, isCompact: true),
      ],
    );
  }

  // Reset password card
  Widget _buildResetCard(BuildContext context, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 24 : 40),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _panelSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
            ),
            child: Icon(
              Icons.lock_reset_rounded,
              color: _primaryAqua,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),

          // Header
          Text(
            'Reset Password',
            style: TextStyle(
              fontSize: isCompact ? 28 : 36,
              fontWeight: FontWeight.bold,
              color: _lightOffWhite,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Enter your email address and we\'ll send you a link to reset your password.',
            style: TextStyle(
              fontSize: isCompact ? 15 : 16,
              color: _lightOffWhite.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
          SizedBox(height: isCompact ? 32 : 40),

          // Email Field
          Text(
            'Email Address',
            style: TextStyle(
              fontSize: 14,
              color: _lightOffWhite,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                color: _lightOffWhite,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'you@example.com',
                hintStyle: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.42),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: _primaryAqua,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _primaryAqua.withValues(alpha: 0.2),
                    width: 1.2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _primaryAqua, width: 1.6),
                ),
                filled: true,
                fillColor: const Color(0xFF061920),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Reset Button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryAqua,
                foregroundColor: _darkDeepTeal,
                disabledBackgroundColor: _mutedCoolGray.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Send Reset Link',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign In Link
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Remember your password? ',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.78),
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    replaceWithAuthPage(
                      context,
                      const Login(),
                      begin: const Offset(-0.06, 0),
                    );
                  },
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      color: _primaryAqua,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
