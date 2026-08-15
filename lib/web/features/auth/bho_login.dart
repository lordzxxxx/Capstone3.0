import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/features/auth/landing.dart';
import 'package:mycapstone_project/web/features/auth/forgot.dart';
import 'package:mycapstone_project/web/shared/widgets/login_success_sweet_alert.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFFF8FBFF);
const Color _sidebarDark = Color(0xFF0D274D);
const Color _panelSurface = Color(0xFF0D274D);

class BHOLogin extends StatefulWidget {
  const BHOLogin({super.key});

  @override
  State<BHOLogin> createState() => _BHOLoginState();
}

class _BHOLoginState extends State<BHOLogin> {
  Future<void> _navigateToDashboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    Get.offAllNamed(WebRoutes.bhwDashboard);
  }

  Future<void> _showSuccessDialogAndNavigate() async {
    final proceedToDashboard = await showLoginSuccessSweetAlert(
      context: context,
      title: 'Login successful',
      message: 'Your account is verified. Continue to the dashboard.',
      confirmButtonText: 'Open Dashboard',
    );

    if (!proceedToDashboard || !mounted) return;
    await _navigateToDashboard();
  }

  Future<void> signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Use Firebase's built-in Google sign-in popup (works better for web)
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.setCustomParameters({'login_hint': 'user@example.com'});

      // Sign in with popup for web
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithPopup(googleProvider);

      if (userCredential.user != null) {
        await _showSuccessDialogAndNavigate();
      }
    } catch (e) {
      Get.snackbar(
        'Google Sign-In Failed',
        'Failed to sign in with Google. Please try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      print('Google Sign-In Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> signIn() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      Get.snackbar(
        'Error',
        'Please fill in all fields',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);
    if (kDebugMode) {
      // Do not print the password itself; print length for debugging only
      final email = emailController.text.trim();
      final pwdLen = passwordController.text.length;
      // ignore: avoid_print
      print('Attempting BHO signIn email=$email passwordLength=$pwdLen');
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      await _showSuccessDialogAndNavigate();
    } on FirebaseAuthException catch (e) {
      // Map common FirebaseAuth web error codes to friendly messages
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for that email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'The email address is badly formatted.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Try again later.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check your connection.';
          break;
        default:
          message = e.message ?? 'Login failed. Please try again.';
      }

      // Build a helpful message; for credential/password errors suggest Google
      String displayMessage = kDebugMode ? '$message (${e.code})' : message;

      // If the error indicates a credential/password issue, offer Google sign-in
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        displayMessage +=
            '\nIf you originally signed up with Google, please use the Google sign-in button or reset your password.';

        Get.snackbar(
          'Login Failed',
          displayMessage,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
          mainButton: TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    // Start Google sign-in flow
                    signInWithGoogle();
                  },
            child: const Text(
              'Sign in with Google',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else {
        Get.snackbar(
          'Login Failed',
          displayMessage,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
        );
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print(
          'FirebaseAuthException during BHO signIn: code=${e.code} message=${e.message}',
        );
      }
    } catch (e) {
      Get.snackbar(
        'Login Failed',
        'Unexpected error. Please try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      // ignore: avoid_print
      print('Unexpected BHO signIn error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 900;

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: _darkDeepTeal)),

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
                    color: _lightOffWhite,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: _darkDeepTeal,
                    size: 24,
                  ),
                ),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                    return;
                  }
                  navigator.pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const LandingPage(),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Wide screen layout (desktop/tablet landscape)
  Widget _buildWideScreenLayout(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Row(
        children: [
          // Left side - Branding/Info
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(60),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
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
                    'Block Health Officer Portal',
                    style: TextStyle(
                      fontSize: 18,
                      color: _mutedCoolGray,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Feature highlights
                  _buildFeatureItem(Icons.shield_outlined, 'Secure & Private'),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    Icons.analytics_outlined,
                    'Block-Level Analytics',
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(Icons.groups_outlined, 'Team Management'),
                ],
              ),
            ),
          ),

          // Right side - Login form
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              child: _buildLoginCard(context, isCompact: false),
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
        // Logo and title
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

        _buildLoginCard(context, isCompact: true),
      ],
    );
  }

  // Feature item widget
  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _primaryAqua.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryAqua, size: 24),
        ),
        const SizedBox(width: 16),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: _lightOffWhite,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Login card widget
  Widget _buildLoginCard(BuildContext context, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 24 : 40),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BHO Portal Login',
                style: TextStyle(
                  fontSize: isCompact ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: _lightOffWhite,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Access Block Health Officer dashboard',
                style: TextStyle(
                  fontSize: isCompact ? 15 : 16,
                  color: _lightOffWhite,
                  height: 1.4,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 32 : 40),

          // Email Field
          _buildFieldLabel(context, 'Email Address'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: emailController,
            hintText: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),

          // Password Field
          _buildFieldLabel(context, 'Password'),
          const SizedBox(height: 10),
          _buildPasswordField(),
          const SizedBox(height: 8),

          // Forgot Password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Get.toNamed(WebRoutes.forgotPassword);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: _primaryAqua,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign In Button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryAqua,
                foregroundColor: Colors.white,
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Sign In',
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

          // Divider
          Row(
            children: [
              Expanded(
                child: Divider(color: _lightOffWhite.withValues(alpha: 0.2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR CONTINUE WITH',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: _lightOffWhite.withValues(alpha: 0.2)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Social Login Buttons
          Row(
            children: [
              Expanded(
                child: _buildSocialButtonLarge(
                  label: 'Google',
                  icon: Icons.g_mobiledata,
                  color: const Color(0xFF4285F4),
                  onTap: _isLoading ? null : signInWithGoogle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSocialButtonLarge(
                  label: 'Facebook',
                  icon: Icons.facebook,
                  color: const Color(0xFF1877F3),
                  onTap: () {
                    // TODO: Implement Facebook sign-in
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Back to landing
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to Selection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _lightOffWhite,
              side: BorderSide(color: _primaryAqua.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop();
                return;
              }
              Get.offAllNamed(WebRoutes.landing);
            },
          ),
        ],
      ),
    );
  }

  // Helper method for field labels
  Widget _buildFieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: _lightOffWhite,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  // Helper method for text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(
          color: _lightOffWhite,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.6),
            fontSize: 15,
          ),
          prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: _panelSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  // Helper method for password field
  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: passwordController,
        obscureText: _obscurePassword,
        style: TextStyle(
          color: _lightOffWhite,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'Enter your password',
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.6),
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            color: _primaryAqua,
            size: 20,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _mutedCoolGray,
              size: 20,
            ),
            onPressed: () {
              setState(() => _obscurePassword = !_obscurePassword);
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: _panelSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  // Helper method for social login buttons (large with labels)
  Widget _buildSocialButtonLarge({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _panelSurface,
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: _lightOffWhite,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
