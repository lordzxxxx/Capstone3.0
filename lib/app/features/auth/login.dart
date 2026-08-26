import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/shell/landing.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/features/auth/widgets/mobile_auth_shell.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/app/core/services/login_attempt_limiter.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.ink;
const Color _panelSurface = AppDesign.page;

class Login extends StatefulWidget {
  final bool syncOfflineAfterLogin;

  const Login({super.key, this.syncOfflineAfterLogin = false});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  static const String _roleCacheKeyPrefix = 'verified_role_';
  String _roleCacheKey(String uid) => '$_roleCacheKeyPrefix$uid';

  Future<void> _cacheMobileBhwRole(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleCacheKey(user.uid), 'bhw');
    } catch (_) {
      // Authentication remains valid even if the optional local cache fails.
    }
  }

  Future<void> _openMobileDashboard() async {
    Get.offAllNamed(MobileRoutes.dashboard);
  }

  Future<void> _completeLoginFlow() async {
    String title = 'Success';
    String message = 'Login successful!';
    Color backgroundColor = const Color(0xFF388E3C);

    if (widget.syncOfflineAfterLogin) {
      try {
        await syncMobileOfflineDataAfterLogin();
        title = 'Connected';
        message =
            'Login successful. Offline records are now syncing to Firestore.';
      } catch (_) {
        title = 'Connected';
        message =
            'Login successful. Some offline records may continue syncing in the background.';
        backgroundColor = const Color(0xFFF57C00);
      }
    }

    Get.snackbar(
      title,
      message,
      backgroundColor: backgroundColor,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
    );

    await _openMobileDashboard();
  }

  Future<void> _finalizeAuthenticatedLogin(User user) async {
    // The mobile application is the BHW workspace. Firebase authentication is
    // sufficient here; CHO and Doctor routing remains exclusive to the web
    // application. Keep this role local so mobile login never overwrites the
    // account's canonical backend role or custom claims.
    await _cacheMobileBhwRole(user);
    await _completeLoginFlow();
  }

  /// Sign in with a Firebase-configured OAuth provider.  The provider is
  /// deliberately created through FirebaseAuth rather than a platform
  /// package so the same callback works on web (popup) and native (native
  /// provider flow).  Firebase remains the source of truth for provider
  /// enablement and account linking.
  Future<void> _signInWithOAuthProvider({
    required String providerId,
    required String providerName,
    List<String> scopes = const [],
  }) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final provider = OAuthProvider(providerId)..addScope('email');
      for (final scope in scopes) {
        provider.addScope(scope);
      }

      final credential = kIsWeb
          ? await FirebaseAuth.instance.signInWithPopup(provider)
          : await FirebaseAuth.instance.signInWithProvider(provider);
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Sign in succeeded but no user session found.',
        );
      }
      await _finalizeAuthenticatedLogin(user);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'popup-closed-by-user' ||
        'canceled' => 'The $providerName sign-in window was closed.',
        'operation-not-allowed' || 'provider-already-linked' =>
          '$providerName sign-in is not enabled for this Firebase project.',
        'account-exists-with-different-credential' =>
          'This email already uses another sign-in method. Sign in with that method first.',
        'network-request-failed' => 'Network error. Check your connection.',
        _ => error.message ?? '$providerName sign-in could not be completed.',
      };
      Get.snackbar(
        '$providerName Sign-In Failed',
        kDebugMode ? '$message (${error.code})' : message,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        '$providerName Sign-In Failed',
        kDebugMode ? '$error' : 'The sign-in could not be completed.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
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
    if (_isLoading) return;
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      Get.snackbar(
        'Error',
        'Please fill in all fields',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    final email = emailController.text.trim();
    final cooldown = LoginAttemptLimiter.remaining(email);
    if (cooldown != null) {
      Get.snackbar(
        'Please wait',
        'Too many failed attempts. Try again in ${(cooldown.inMilliseconds / 1000).ceil()} seconds.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );
      LoginAttemptLimiter.clear(email);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Sign in succeeded but no user session found.',
        );
      }

      await _finalizeAuthenticatedLogin(currentUser);
    } on FirebaseAuthException catch (e) {
      if ({
        'invalid-credential',
        'wrong-password',
        'user-not-found',
      }.contains(e.code)) {
        LoginAttemptLimiter.recordFailure(email);
      }
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'Incorrect email or password. Please try again.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Incorrect email or password. Please try again.';
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

      final displayMessage = kDebugMode ? '$message (${e.code})' : message;
      Get.snackbar(
        'Login Failed',
        displayMessage,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
    } catch (e) {
      final message = kDebugMode
          ? 'Unexpected error: $e'
          : 'Unexpected error. Please try again.';
      Get.snackbar(
        'Login Failed',
        message,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
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
    return MobileAuthShell(
      pageTitle: 'Sign in',
      heading: 'Welcome back',
      description: 'Sign in to securely access the AI-DSUHIS mobile workspace.',
      onBack: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const LandingPage()),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('Email address'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: emailController,
            hintText: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const AuthFieldLabel('Password'),
              TextButton(
                onPressed: () => Get.toNamed(MobileRoutes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
          _buildPasswordField(),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : signIn,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppDesign.surface,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Sign in'),
            ),
          ),
          const SizedBox(height: 20),
          const AuthDivider(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _signInWithOAuthProvider(
                            providerId: 'facebook.com',
                            providerName: 'Facebook',
                            scopes: const ['public_profile'],
                          ),
                    icon: const Icon(
                      Icons.facebook_rounded,
                      color: Color(0xFF1877F3),
                    ),
                    label: const Text('Facebook'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _signInWithOAuthProvider(
                            providerId: 'apple.com',
                            providerName: 'Apple',
                          ),
                    icon: const Icon(Icons.apple_rounded),
                    label: const Text('Apple'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: "Don't have an account? "),
                  TextSpan(
                    text: 'Create one',
                    style: const TextStyle(
                      color: AppDesign.blue,
                      fontWeight: FontWeight.w800,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Get.toNamed(MobileRoutes.signup),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email, AutofillHints.username],
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      style: const TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppDesign.subtle),
        prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _primaryAqua.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _primaryAqua.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primaryAqua, width: 1.8),
        ),
        filled: true,
        fillColor: _panelSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  // Helper method for password field
  Widget _buildPasswordField() {
    return TextField(
      controller: passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) {
        if (!_isLoading) signIn();
      },
      style: const TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Enter your password',
        hintStyle: const TextStyle(color: AppDesign.subtle),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: _primaryAqua,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: AppDesign.subtle,
            size: 20,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _primaryAqua.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _primaryAqua.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primaryAqua, width: 1.8),
        ),
        filled: true,
        fillColor: _panelSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
