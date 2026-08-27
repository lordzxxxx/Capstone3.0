import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:flutter/gestures.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';
import 'package:mycapstone_project/web/shared/widgets/barangay_logo_image.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/features/auth/widgets/mobile_auth_shell.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';
import 'package:mycapstone_project/shared/password_policy.dart';
import 'package:mycapstone_project/shared/input_validation.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.subtle;
const Color _lightOffWhite = AppDesign.ink;
const Color _panelSurface = AppDesign.page;

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  static const int _realtimeDbWriteAttempts = 3;

  TextEditingController usernameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _selectedRole;
  BarangayReference? _selectedBarangay;
  bool _showBarangayValidationError = false;
  bool _selectedBarangayUnavailable = false;
  bool _isCheckingBarangayAvailability = false;
  String? _barangayRestrictionMessage;
  final Map<String, BarangayBrandingProfile> _brandingCache =
      <String, BarangayBrandingProfile>{};
  final Map<String, BarangayAvailabilityStatus> _barangayAvailabilityByCode =
      <String, BarangayAvailabilityStatus>{};
  StreamSubscription<List<BarangayBrandingProfile>>? _brandingSubscription;

  @override
  void initState() {
    super.initState();
    _selectedRole = 'BHW';
    _brandingSubscription = BarangayBrandingService.instance
        .watchAllBranding()
        .listen(
          (profiles) {
            if (!mounted) return;
            setState(() {
              _brandingCache
                ..clear()
                ..addEntries(
                  profiles.map(
                    (profile) => MapEntry(profile.barangay.code, profile),
                  ),
                );
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              print('Signup branding stream unavailable: $error');
            }
          },
        );
    unawaited(_refreshBarangayAvailability(silent: true));
  }

  bool get _requiresBarangayAssignment => _selectedRole == 'BHW';

  Future<void> _refreshBarangayAvailability({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isCheckingBarangayAvailability = true);
    }

    try {
      final availability = await _accountPolicyService
          .getBarangayAvailability();
      if (!mounted) return;
      setState(() {
        _barangayAvailabilityByCode
          ..clear()
          ..addAll(availability);
        _isCheckingBarangayAvailability = false;
      });
      _syncSelectedBarangayRestriction();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingBarangayAvailability = false);
    }
  }

  void _syncSelectedBarangayRestriction() {
    final barangay = _selectedBarangay;
    if (!_requiresBarangayAssignment || barangay == null) {
      if (!mounted) return;
      setState(() {
        _selectedBarangayUnavailable = false;
        _barangayRestrictionMessage = null;
      });
      return;
    }

    final status = _barangayAvailabilityByCode[barangay.code];
    final unavailable = status != null && !status.isAvailable;
    if (!mounted) return;
    setState(() {
      _selectedBarangayUnavailable = unavailable;
      _showBarangayValidationError = unavailable;
      _barangayRestrictionMessage = unavailable
          ? 'This barangay is already registered under another account.'
          : null;
    });
  }

  Future<void> _writeUserRoleToRealtimeDb({
    required String uid,
    required String username,
    required String email,
    required String role,
    BarangayReference? barangay,
  }) async {
    final roleRef = getRealtimeDatabaseInstance()
        .ref()
        .child('users')
        .child(uid);
    final normalizedRole = role.trim().toUpperCase();
    final isPendingApproval = normalizedRole == 'BHW';

    final payload = {
      'uid': uid,
      'username': username,
      'email': email,
      'role': role,
      'accessScope': role == 'BHW' ? 'barangay' : 'citywide',
      'dataVisibilityStartAt': ServerValue.timestamp,
      'barangay': barangay?.name,
      'barangayCode': barangay?.code,
      'barangayDistrict': barangay?.district,
      'approvalStatus': isPendingApproval ? 'pending' : 'approved',
      'accountStatus': isPendingApproval ? 'pending_approval' : 'active',
      'isApproved': !isPendingApproval,
      'updatedAt': ServerValue.timestamp,
    };

    for (int attempt = 1; attempt <= _realtimeDbWriteAttempts; attempt++) {
      try {
        await roleRef.update(payload).timeout(const Duration(seconds: 20));
        return;
      } on TimeoutException {
        if (attempt == _realtimeDbWriteAttempts) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      } on FirebaseException catch (e) {
        const retryableCodes = <String>{
          'disconnected',
          'network-error',
          'operation-failed',
          'overridden-by-set',
          'unavailable',
          'unknown',
        };
        final shouldRetry =
            retryableCodes.contains(e.code) &&
            attempt < _realtimeDbWriteAttempts;
        if (!shouldRetry) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  bool _requiresStrictBarangayPolicy(String? role) {
    return (role ?? '').trim().toUpperCase() == 'BHW';
  }

  Future<void> signup() async {
    if (_isLoading) return;
    final username = usernameController.text.trim();
    final email = emailController.text.trim();

    if (username.isEmpty ||
        email.isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      Get.snackbar(
        'Error',
        'Please fill in all fields',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (username.length < 3) {
      Get.snackbar(
        'Error',
        'Username must be at least 3 characters',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (!InputValidation.isEmail(email)) {
      Get.snackbar(
        'Error',
        'Please enter a valid email address.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      Get.snackbar(
        'Error',
        'Passwords do not match',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    final passwordValidationMessage = PasswordPolicy.validationMessage(
      passwordController.text,
    );
    if (passwordValidationMessage.isNotEmpty) {
      Get.snackbar(
        'Error',
        passwordValidationMessage,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (_selectedRole != 'CHO' && _selectedRole != 'BHW') {
      Get.snackbar(
        'Error',
        'Please select account type (CHO or BHW)',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (_requiresBarangayAssignment && _selectedBarangay == null) {
      setState(() => _showBarangayValidationError = true);
      Get.snackbar(
        'Error',
        'Please select your barangay from the official Malaybalay list.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (_requiresBarangayAssignment && _selectedBarangayUnavailable) {
      setState(() => _showBarangayValidationError = true);
      Get.snackbar(
        'Barangay unavailable',
        _barangayRestrictionMessage ??
            'This barangay is already registered under another account.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      return;
    }

    if (_isCheckingBarangayAvailability) {
      Get.snackbar(
        'Validation in progress',
        'Please wait while the system verifies barangay availability.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final precheck = await _accountPolicyService.validateRegistrationPolicy(
        email: email,
        username: username,
        role: _selectedRole,
        barangayCode: _selectedBarangay?.code,
      );

      if (precheck.emailExists || precheck.usernameExists) {
        Get.snackbar(
          'Account already registered',
          precheck.duplicateAccountMessage,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
        );
        return;
      }

      if (precheck.barangayUnavailable) {
        if (mounted) {
          setState(() {
            _selectedBarangayUnavailable = true;
            _showBarangayValidationError = true;
            _barangayRestrictionMessage = precheck.barangayMessage;
          });
        }
        await _refreshBarangayAvailability(silent: true);
        Get.snackbar(
          'Barangay unavailable',
          precheck.barangayMessage,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
        );
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          'Signup policy precheck unavailable, continuing with fallback: $e',
        );
      }

      if (_requiresStrictBarangayPolicy(_selectedRole) &&
          _selectedBarangay != null) {
        try {
          final fallbackStatus = await _accountPolicyService
              .getBarangayAvailabilityStatus(_selectedBarangay!.code);

          if (mounted) {
            setState(() {
              if (fallbackStatus == null) {
                _barangayAvailabilityByCode.remove(_selectedBarangay!.code);
              } else {
                _barangayAvailabilityByCode[_selectedBarangay!.code] =
                    fallbackStatus;
              }

              final unavailable =
                  fallbackStatus != null && !fallbackStatus.isAvailable;
              _selectedBarangayUnavailable = unavailable;
              _showBarangayValidationError = unavailable;
              _barangayRestrictionMessage = unavailable
                  ? 'This barangay is already registered under another account.'
                  : 'Live barangay availability could not be checked. We will verify it during account creation.';
            });
          }

          if (fallbackStatus != null && !fallbackStatus.isAvailable) {
            Get.snackbar(
              'Barangay unavailable',
              'This barangay is already registered under another account.',
              backgroundColor: const Color(0xFFD32F2F),
              colorText: Colors.white,
            );
            return;
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _barangayRestrictionMessage =
                  'Live barangay availability could not be checked. We will verify it during account creation.';
            });
          }
        }
      }
    }

    if (_showBarangayValidationError) {
      setState(() => _showBarangayValidationError = false);
    }

    setState(() => _isLoading = true);
    UserCredential? userCredential;
    try {
      final registration = await _accountPolicyService
          .createRegistrationAccount(
            email: email,
            username: username,
            password: passwordController.text,
            role: _selectedRole!,
            barangayCode: _selectedBarangay?.code,
          )
          .timeout(const Duration(seconds: 45));
      if (registration.uid.isEmpty || registration.customToken.isEmpty) {
        throw StateError('Registration did not return a valid account token.');
      }

      userCredential = await FirebaseAuth.instance
          .signInWithCustomToken(registration.customToken)
          .timeout(const Duration(seconds: 45));
      if (userCredential.user?.uid != registration.uid) {
        throw StateError('Registration account verification failed.');
      }

      await userCredential.user!
          .updateDisplayName(username)
          .timeout(const Duration(seconds: 20));

      await _accountPolicyService.completeRegistration(
        uid: userCredential.user!.uid,
        username: username,
        email: email,
        role: _selectedRole!,
        barangay: _selectedBarangay?.name,
        barangayCode: _selectedBarangay?.code,
        barangayDistrict: _selectedBarangay?.district,
        registrationNonce: registration.registrationNonce,
      );

      unawaited(
        _writeUserRoleToRealtimeDb(
          uid: userCredential.user!.uid,
          username: username,
          email: email,
          role: _selectedRole!,
          barangay: _selectedBarangay,
        ).catchError((Object e) {
          if (kDebugMode) {
            print('RTDB role mirror write failed during signup: $e');
          }
        }),
      );

      final isPendingApproval = _selectedRole == 'BHW';
      Get.snackbar(
        isPendingApproval ? 'Registration submitted' : 'Registration complete',
        isPendingApproval
            ? 'Your BHW registration is pending CHO approval.'
            : 'CHO accounts must use the CHO web portal to sign in.',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );

      await FirebaseAuth.instance.signOut();
      Get.offAllNamed(MobileRoutes.login);
    } on TimeoutException {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }

      Get.snackbar(
        'Signup Failed',
        'Request timed out. Please check your internet and try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {}
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }

      final rawError = e.toString();
      var errorMessage =
          'Unable to create your account right now. Please try again.';

      // Provide user-friendly error messages
      if (rawError.contains('email-already-in-use')) {
        errorMessage =
            'This account is already registered. Please log in instead.';
      } else if (rawError.contains('already-exists')) {
        errorMessage = rawError.contains('barangay')
            ? 'This barangay is already registered under another account.'
            : 'This account is already registered. Please log in instead.';
      } else if (rawError.contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      } else if (rawError.contains('weak-password')) {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      } else if (rawError.contains('network-request-failed')) {
        errorMessage = 'Network error. Please check your internet connection.';
      }

      Get.snackbar(
        'Signup Failed',
        errorMessage,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _brandingSubscription?.cancel();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileAuthShell(
      pageTitle: 'Register',
      heading: 'Create your account',
      description:
          'Register your BHW access details and assigned barangay for the mobile health workspace.',
      onBack: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          Get.offAllNamed(MobileRoutes.login);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppDesign.informationBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppDesign.blue.withValues(alpha: 0.20)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.badge_outlined, color: AppDesign.blue, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mobile registration creates a Barangay Health Worker account. Barangay availability and approval rules still apply.',
                    style: TextStyle(
                      color: AppDesign.navy,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const AuthFieldLabel('Username'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: usernameController,
            hintText: 'Enter your username',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 16),
          const AuthFieldLabel('Email address'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: emailController,
            hintText: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          const AuthFieldLabel('Assigned barangay'),
          const SizedBox(height: 8),
          _buildBarangaySelector(),
          const SizedBox(height: 16),
          const AuthFieldLabel('Password'),
          const SizedBox(height: 8),
          _buildPasswordField(),
          const SizedBox(height: 16),
          const AuthFieldLabel('Confirm password'),
          const SizedBox(height: 8),
          _buildConfirmPasswordField(),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : signup,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: AppDesign.surface,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(_isLoading ? 'Creating account…' : 'Create account'),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Already have an account? '),
                  TextSpan(
                    text: 'Sign in',
                    style: const TextStyle(
                      color: AppDesign.blue,
                      fontWeight: FontWeight.w800,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        final navigator = Navigator.of(context);
                        if (navigator.canPop()) {
                          navigator.pop();
                        } else {
                          Get.offAllNamed(MobileRoutes.login);
                        }
                      },
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
      autofillHints: keyboardType == TextInputType.emailAddress
          ? const [AutofillHints.email]
          : const [AutofillHints.newUsername],
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

  Widget _buildBarangaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<BarangayReference>(
          initialValue: _selectedBarangay,
          isExpanded: true,
          dropdownColor: _panelSurface,
          iconEnabledColor: _primaryAqua,
          hint: Text(
            'Select Barangay',
            style: TextStyle(
              color: AppDesign.subtle,
              fontWeight: FontWeight.w500,
            ),
          ),
          selectedItemBuilder: (context) {
            return MalaybalayBarangays.all
                .map(
                  (barangay) => _buildBarangayDropdownLabel(
                    barangay: barangay,
                    profile:
                        _brandingCache[barangay.code] ??
                        BarangayBrandingProfile.fallback(barangay),
                    showDistrict: false,
                  ),
                )
                .toList();
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color:
                    (_showBarangayValidationError ||
                        _selectedBarangayUnavailable)
                    ? const Color(0xFFD32F2F)
                    : _primaryAqua.withValues(alpha: 0.20),
                width: 1.2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color:
                    (_showBarangayValidationError ||
                        _selectedBarangayUnavailable)
                    ? const Color(0xFFD32F2F)
                    : _primaryAqua.withValues(alpha: 0.20),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color:
                    (_showBarangayValidationError ||
                        _selectedBarangayUnavailable)
                    ? const Color(0xFFD32F2F)
                    : _primaryAqua,
                width: 1.8,
              ),
            ),
            filled: true,
            fillColor: _panelSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          items: MalaybalayBarangays.all.map((barangay) {
            final profile =
                _brandingCache[barangay.code] ??
                BarangayBrandingProfile.fallback(barangay);
            final availability = _barangayAvailabilityByCode[barangay.code];
            final unavailable =
                availability != null && !availability.isAvailable;

            return DropdownMenuItem<BarangayReference>(
              value: barangay,
              enabled: !unavailable,
              child: Opacity(
                opacity: unavailable ? 0.55 : 1,
                child: _buildBarangayDropdownLabel(
                  barangay: barangay,
                  profile: profile,
                  showDistrict: true,
                ),
              ),
            );
          }).toList(),
          onChanged: _isLoading
              ? null
              : (value) {
                  setState(() {
                    _selectedBarangay = value;
                    _showBarangayValidationError = false;
                  });
                  _syncSelectedBarangayRestriction();
                },
        ),
        if (_showBarangayValidationError || _selectedBarangayUnavailable) ...[
          const SizedBox(height: 8),
          Text(
            _barangayRestrictionMessage ??
                'Please select your barangay to continue.',
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (_isCheckingBarangayAvailability) ...[
          const SizedBox(height: 8),
          Text(
            'Checking barangay availability...',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.66),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBarangayDropdownLabel({
    required BarangayReference barangay,
    required BarangayBrandingProfile profile,
    required bool showDistrict,
  }) {
    return Row(
      children: [
        BarangayLogoImage(
          imageUrl: profile.hasCustomLogo ? profile.resolvedLogoUrl : null,
          assetPath: profile.localAssetPath,
          size: 30,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                barangay.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _darkDeepTeal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showDistrict)
                Text(
                  barangay.district,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppDesign.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper method for password field
  Widget _buildPasswordField() {
    return TextField(
      controller: passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      style: const TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: '8+ chars: upper, lower, number, symbol',
        hintStyle: const TextStyle(color: AppDesign.subtle),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: _primaryAqua,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: _mutedCoolGray,
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

  // Helper method for confirm password field
  Widget _buildConfirmPasswordField() {
    return TextField(
      controller: confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: (_) {
        if (!_isLoading) signup();
      },
      style: const TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Re-enter your password',
        hintStyle: const TextStyle(color: AppDesign.subtle),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: _primaryAqua,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
            color: _mutedCoolGray,
            size: 20,
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
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
