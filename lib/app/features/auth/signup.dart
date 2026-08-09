import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:flutter/gestures.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';
import 'package:mycapstone_project/web/shared/widgets/barangay_logo_image.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.navySoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.subtle;
const Color _lightOffWhite = AppDesign.ink;
const Color _sidebarDark = Colors.white;
const Color _panelSurface = AppDesign.page;

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  static const int _realtimeDbWriteAttempts = 3;
  static const String _duplicateAccountConflict = 'duplicate-account';
  static const String _duplicateBarangayConflict = 'duplicate-barangay';

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
      'approvalStatus': 'pending',
      'accountStatus': 'active',
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

  Future<void> _writeUserProfileToFirestoreFallback({
    required String uid,
    required String username,
    required String email,
    required String role,
    BarangayReference? barangay,
  }) async {
    final firestore = getFirestoreInstance();
    final normalizedRole = role.trim().toUpperCase();
    final normalizedUsername = username.toLowerCase().trim();
    final isBarangayScoped = normalizedRole == 'BHW' && barangay != null;
    final normalizedBarangayCode = isBarangayScoped
        ? BarangayFirestorePaths.normalizeBarangayCode(barangay.code)
        : '';
    final barangayPath = isBarangayScoped
        ? BarangayFirestorePaths.barangayDocumentPath(normalizedBarangayCode)
        : null;
    final barangayUserPath = isBarangayScoped
        ? BarangayFirestorePaths.barangayUserDocumentPath(
            normalizedBarangayCode,
            uid,
          )
        : null;
    final rootUserRef = firestore.collection('users').doc(uid);
    final usernameLockRef = firestore
        .collection('registration_username_locks')
        .doc(normalizedUsername);
    final barangayLockRef = isBarangayScoped
        ? firestore
              .collection('registration_barangay_locks')
              .doc(normalizedBarangayCode)
        : null;
    final barangayStatusRef = isBarangayScoped
        ? firestore
              .collection('barangay_registration_status')
              .doc(normalizedBarangayCode)
        : null;
    final barangayUserRef = isBarangayScoped
        ? firestore
              .collection('barangays')
              .doc(normalizedBarangayCode)
              .collection('users')
              .doc(uid)
        : null;

    final rootPayload = <String, dynamic>{
      'uid': uid,
      'username': username,
      'usernameLower': normalizedUsername,
      'email': email,
      'emailLower': email.toLowerCase().trim(),
      'role': normalizedRole,
      'accessScope': isBarangayScoped ? 'barangay' : 'citywide',
      'organizationLevel': isBarangayScoped ? 'barangay' : 'citywide',
      'dataVisibilityStartAt': FieldValue.serverTimestamp(),
      'barangay': isBarangayScoped ? barangay.name : FieldValue.delete(),
      'barangayCode': isBarangayScoped
          ? normalizedBarangayCode
          : FieldValue.delete(),
      'barangayDistrict': isBarangayScoped
          ? barangay.district
          : FieldValue.delete(),
      'barangayVerified': isBarangayScoped,
      'barangayPath': barangayPath ?? FieldValue.delete(),
      'barangayUserPath': barangayUserPath ?? FieldValue.delete(),
      'approvalStatus': 'pending',
      'accountStatus': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final conflict = await firestore.runTransaction<String?>((
      transaction,
    ) async {
      final usernameLockSnapshot = await transaction.get(usernameLockRef);
      if (usernameLockSnapshot.exists) {
        final existingUid = (usernameLockSnapshot.data()?['uid'] ?? '')
            .toString();
        if (existingUid.isNotEmpty && existingUid != uid) {
          return _duplicateAccountConflict;
        }
      }

      if (barangayLockRef != null) {
        final barangayLockSnapshot = await transaction.get(barangayLockRef);
        if (barangayLockSnapshot.exists) {
          final lockData = barangayLockSnapshot.data() ?? <String, dynamic>{};
          final existingUid = (lockData['uid'] ?? '').toString();
          final accountStatus = (lockData['accountStatus'] ?? 'active')
              .toString();
          final isActiveLock =
              accountStatus != 'disabled' && accountStatus != 'archived';
          if (existingUid.isNotEmpty && existingUid != uid && isActiveLock) {
            return _duplicateBarangayConflict;
          }
        }
      }

      transaction.set(rootUserRef, rootPayload, SetOptions(merge: true));
      transaction.set(usernameLockRef, {
        'uid': uid,
        'username': username,
        'usernameLower': normalizedUsername,
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'mobile-signup-fallback',
      }, SetOptions(merge: true));

      if (barangayLockRef != null && barangay != null) {
        transaction.set(barangayLockRef, {
          'uid': uid,
          'barangay': barangay.name,
          'barangayCode': normalizedBarangayCode,
          'barangayDistrict': barangay.district,
          'username': username,
          'email': email,
          'accountStatus': 'active',
          'approvalStatus': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile-signup-fallback',
        }, SetOptions(merge: true));
      }

      if (barangayStatusRef != null && barangay != null) {
        transaction.set(barangayStatusRef, {
          'uid': uid,
          'barangay': barangay.name,
          'barangayCode': normalizedBarangayCode,
          'barangayDistrict': barangay.district,
          'accountStatus': 'active',
          'approvalStatus': 'pending',
          'isAvailable': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile-signup-fallback',
        }, SetOptions(merge: true));
      }

      if (barangayUserRef != null) {
        transaction.set(barangayUserRef, {
          ...rootPayload,
          'rootUserPath': rootUserRef.path,
          'storedUnderBarangay': true,
        }, SetOptions(merge: true));
      }

      return null;
    });

    if (conflict == _duplicateAccountConflict) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-exists',
        message: 'This account is already registered. Please log in instead.',
      );
    }

    if (conflict == _duplicateBarangayConflict) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-exists',
        message: 'This barangay is already registered under another account.',
      );
    }
  }

  bool _requiresStrictBarangayPolicy(String? role) {
    return (role ?? '').trim().toUpperCase() == 'BHW';
  }

  Future<void> signup() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();

    if (usernameController.text.isEmpty ||
        emailController.text.isEmpty ||
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

    if (usernameController.text.length < 3) {
      Get.snackbar(
        'Error',
        'Username must be at least 3 characters',
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

    if (passwordController.text.length < 6) {
      Get.snackbar(
        'Error',
        'Password must be at least 6 characters',
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

    bool backendPolicyAvailable = true;
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
      backendPolicyAvailable = false;
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
      userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: passwordController.text,
          )
          .timeout(const Duration(seconds: 45));

      await userCredential.user!
          .updateDisplayName(username)
          .timeout(const Duration(seconds: 20));

      if (backendPolicyAvailable) {
        try {
          await _accountPolicyService.completeRegistration(
            uid: userCredential.user!.uid,
            username: username,
            email: email,
            role: _selectedRole!,
            barangay: _selectedBarangay?.name,
            barangayCode: _selectedBarangay?.code,
            barangayDistrict: _selectedBarangay?.district,
          );
        } catch (e) {
          if (kDebugMode) {
            print(
              'Signup completeRegistration failed, using Firestore fallback: $e',
            );
          }
          await _writeUserProfileToFirestoreFallback(
            uid: userCredential.user!.uid,
            username: username,
            email: email,
            role: _selectedRole!,
            barangay: _selectedBarangay,
          );
        }
      } else {
        await _writeUserProfileToFirestoreFallback(
          uid: userCredential.user!.uid,
          username: username,
          email: email,
          role: _selectedRole!,
          barangay: _selectedBarangay,
        );
      }

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

      Get.snackbar(
        'Success',
        'Welcome $username! Account created successfully.',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );

      Get.offAll(() => const HomePage());
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

      String errorMessage = e.toString();

      // Provide user-friendly error messages
      if (errorMessage.contains('email-already-in-use')) {
        errorMessage =
            'This account is already registered. Please log in instead.';
      } else if (errorMessage.contains('already-exists')) {
        errorMessage = errorMessage.contains('barangay')
            ? 'This barangay is already registered under another account.'
            : 'This account is already registered. Please log in instead.';
      } else if (errorMessage.contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      } else if (errorMessage.contains('weak-password')) {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      } else if (errorMessage.contains('network-request-failed')) {
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
            Get.offAll(() => Login());
          },
        ),
        title: Text(
          'Create Account',
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create Account',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: _darkDeepTeal,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select your barangay and continue with account creation.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppDesign.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  _buildFieldLabel(context, 'Username'),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: usernameController,
                    hintText: 'Enter your username',
                    icon: Icons.person_outline,
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 24),
                  _buildFieldLabel(context, 'Email Address'),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: emailController,
                    hintText: 'you@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),
                  _buildFieldLabel(context, 'Select Barangay'),
                  const SizedBox(height: 10),
                  _buildBarangaySelector(),
                  const SizedBox(height: 24),
                  _buildFieldLabel(context, 'Password'),
                  const SizedBox(height: 10),
                  _buildPasswordField(),
                  const SizedBox(height: 24),
                  _buildFieldLabel(context, 'Confirm Password'),
                  const SizedBox(height: 10),
                  _buildConfirmPasswordField(),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : signup,
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
                          : const Icon(Icons.person_add, size: 20),
                      label: Text(
                        _isLoading ? 'Creating Account...' : 'Create Account',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppDesign.muted,
                        ),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(
                            text: 'Sign In',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _primaryAqua,
                                  fontWeight: FontWeight.bold,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                final navigator = Navigator.of(context);
                                if (navigator.canPop()) {
                                  navigator.pop();
                                  return;
                                }
                                Get.offAll(() => Login());
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

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.32)),
        color: _panelSurface,
      ),
      child: Row(
        children: [
          Expanded(child: _buildRoleOption(label: 'CHO')),
          const SizedBox(width: 8),
          Expanded(child: _buildRoleOption(label: 'BHW')),
        ],
      ),
    );
  }

  Widget _buildRoleOption({required String label}) {
    final isSelected = _selectedRole == label;
    return InkWell(
      onTap: _isLoading
          ? null
          : () {
              setState(() {
                _selectedRole = label;
                if (label == 'CHO') {
                  _selectedBarangay = null;
                  _showBarangayValidationError = false;
                  _selectedBarangayUnavailable = false;
                  _barangayRestrictionMessage = null;
                } else {
                  _showBarangayValidationError = false;
                }
              });
              if (label == 'BHW') {
                unawaited(_refreshBarangayAvailability(silent: true));
              }
            },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? _primaryAqua : _darkDeepTeal,
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : _primaryAqua.withValues(alpha: 0.18),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : _darkDeepTeal,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
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
      style: const TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'At least 6 characters',
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
