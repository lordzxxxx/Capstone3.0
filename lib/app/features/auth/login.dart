import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/shell/landing.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_bootstrap.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mycapstone_project/app/features/auth/signup.dart';
import 'package:mycapstone_project/app/features/auth/forgot.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.navySoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.subtle;
const Color _lightOffWhite = AppDesign.ink;
const Color _sidebarDark = Colors.white;
const Color _panelSurface = AppDesign.page;

class Login extends StatefulWidget {
  final bool syncOfflineAfterLogin;

  const Login({super.key, this.syncOfflineAfterLogin = false});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  // Replace this with the OAuth 2.0 Client ID (Web application) from
  // Google Cloud / Firebase console (looks like "...apps.googleusercontent.com").
  // Required on Android for server-side auth flows.
  static const String _googleServerClientId =
      '628319595773-o2goeoicefu66u0kdpe1mcvf1q7jmn4l.apps.googleusercontent.com';
  static bool _googleInitialized = false;
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
    Get.offAll(() => const HomePage());
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

  Future<void> signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      User? user;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider()
          ..addScope('email')
          ..setCustomParameters({'login_hint': 'user@example.com'});

        final userCredential = await FirebaseAuth.instance.signInWithPopup(
          googleProvider,
        );
        user = userCredential.user;
      } else {
        if (!_googleInitialized) {
          await GoogleSignIn.instance.initialize(
            serverClientId: _googleServerClientId,
          );
          _googleInitialized = true;
        }

        final GoogleSignInAccount account = await GoogleSignIn.instance
            .authenticate();

        final GoogleSignInAuthentication auth = account.authentication;

        if (auth.idToken == null || auth.idToken!.isEmpty) {
          throw FirebaseAuthException(
            code: 'google-id-token-missing',
            message:
                'Google did not return an ID token. Check the Android OAuth client configuration.',
          );
        }

        final AuthCredential credential = GoogleAuthProvider.credential(
          idToken: auth.idToken,
        );

        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        user = userCredential.user;
      }

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Sign in succeeded but no user session found.',
        );
      }

      await _finalizeAuthenticatedLogin(user);
    } on GoogleSignInException catch (gse) {
      if (gse.code == GoogleSignInExceptionCode.canceled) {
        Get.snackbar(
          'Google Sign-In Canceled',
          'The Google account window was closed. If this appears after you select an account, update the Android SHA-1 and google-services.json in Firebase.',
          backgroundColor: const Color(0xFFF57C00),
          colorText: Colors.white,
          duration: const Duration(seconds: 7),
        );
        return;
      }

      final configurationError =
          gse.code == GoogleSignInExceptionCode.clientConfigurationError ||
          gse.code == GoogleSignInExceptionCode.providerConfigurationError;
      Get.snackbar(
        'Google Sign-In Failed',
        configurationError
            ? 'Google authentication is not configured for this Android build. Add its SHA-1 in Firebase and download the updated google-services.json.'
            : (gse.description ??
                  'Google authentication could not be completed.'),
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        'Google Sign-In Failed',
        e.toString(),
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Sign in succeeded but no user session found.',
        );
      }

      await _finalizeAuthenticatedLogin(currentUser);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for that email.';
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
    return Scaffold(
      backgroundColor: AppDesign.page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppDesign.navy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            navigator.pushReplacement(
              MaterialPageRoute(builder: (context) => const LandingPage()),
            );
          },
        ),
        title: Text(
          'Sign In',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        color: AppDesign.page,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
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
                        'Smart Health Access',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _primaryAqua,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Logo/Icon Section with gradient
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppDesign.navy,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _primaryAqua.withValues(alpha: 0.28),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/newlogo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.medical_services_rounded,
                              size: 100,
                              color: _primaryAqua,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Heading Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: _darkDeepTeal,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to access your health monitoring dashboard',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppDesign.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Email Field
                  _buildFieldLabel(context, 'Email Address'),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: emailController,
                    hintText: 'you@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),

                  // Password Field
                  _buildFieldLabel(context, 'Password'),
                  const SizedBox(height: 10),
                  _buildPasswordField(),
                  const SizedBox(height: 12),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Get.to(() => const ForgotPassword());
                      },
                      child: Text(
                        'Forgot Password?',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _darkDeepTeal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 6,
                        shadowColor: _primaryAqua.withValues(alpha: 0.4),
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.login, size: 20),
                      label: Text(
                        _isLoading ? 'Signing In...' : 'Sign In',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Divider with text
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: AppDesign.border, thickness: 1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: _darkDeepTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: AppDesign.border, thickness: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Social Login Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialButton(
                        icon: Icons.facebook,
                        color: const Color(0xFF1877F3),
                        onTap: _isLoading
                            ? null
                            : () => _signInWithOAuthProvider(
                                providerId: 'facebook.com',
                                providerName: 'Facebook',
                                scopes: const ['public_profile'],
                              ),
                      ),
                      const SizedBox(width: 16),
                      _buildSocialButton(
                        icon: Icons.g_mobiledata,
                        color: _darkDeepTeal,
                        onTap: _isLoading ? null : signInWithGoogle,
                      ),
                      const SizedBox(width: 16),
                      _buildSocialButton(
                        icon: Icons.apple,
                        color: _darkDeepTeal,
                        onTap: _isLoading
                            ? null
                            : () => _signInWithOAuthProvider(
                                providerId: 'apple.com',
                                providerName: 'Apple',
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  const SizedBox(height: 24),

                  // Sign Up Link
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppDesign.muted,
                        ),
                        children: [
                          const TextSpan(text: "Don't have an account? "),
                          TextSpan(
                            text: 'Sign Up',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _primaryAqua,
                                  fontWeight: FontWeight.bold,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Get.to(() => const Signup());
                              },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method for field labels
  Widget _buildFieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: _darkDeepTeal,
        fontWeight: FontWeight.bold,
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

  // Helper method for social buttons
  Widget _buildSocialButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppDesign.page,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    );
  }
}
