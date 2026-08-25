import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:flutter/gestures.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/features/auth/landing.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/features/auth/cho_access_session.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';
import 'package:mycapstone_project/web/shared/widgets/barangay_logo_image.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFFF8FBFF);
const Color _sidebarDark = Color(0xFF0D274D);
const Color _panelSurface = Color(0xFF0D274D);

class Signup extends StatefulWidget {
  final String? preselectedRole;

  const Signup({super.key, this.preselectedRole});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
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
  bool _emailExists = false;
  bool _usernameExists = false;
  bool _selectedBarangayUnavailable = false;
  bool _isCheckingEmail = false;
  bool _isCheckingUsername = false;
  bool _isCheckingBarangayAvailability = false;
  String? _emailValidationMessage;
  String? _usernameValidationMessage;
  String? _barangayRestrictionMessage;
  Timer? _emailValidationDebounce;
  Timer? _usernameValidationDebounce;
  final Map<String, BarangayBrandingProfile> _brandingCache =
      <String, BarangayBrandingProfile>{};
  final Map<String, BarangayAvailabilityStatus> _barangayAvailabilityByCode =
      <String, BarangayAvailabilityStatus>{};
  StreamSubscription<List<BarangayBrandingProfile>>? _brandingSubscription;
  static const int _realtimeDbWriteAttempts = 3;

  static const String _duplicateAccountConflict = 'duplicate-account';
  static const String _duplicateBarangayConflict = 'duplicate-barangay';

  @override
  void initState() {
    super.initState();
    final incomingRole = widget.preselectedRole?.trim().toUpperCase();
    if (incomingRole == 'CHO' || incomingRole == 'BHW') {
      _selectedRole = incomingRole;
    }
    _brandingSubscription = BarangayBrandingService.instance
        .watchAllBranding()
        .listen((profiles) {
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
        });
    usernameController.addListener(_scheduleUsernameAvailabilityCheck);
    emailController.addListener(_scheduleEmailAvailabilityCheck);
    unawaited(_refreshBarangayAvailability(silent: true));
  }

  @override
  void dispose() {
    _brandingSubscription?.cancel();
    _emailValidationDebounce?.cancel();
    _usernameValidationDebounce?.cancel();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _requiresBarangayAssignment => _selectedRole == 'BHW';

  bool get _isChoRegistration => _selectedRole == 'CHO';

  void _scheduleUsernameAvailabilityCheck() {
    _usernameValidationDebounce?.cancel();
    final username = usernameController.text.trim();

    if (username.isEmpty) {
      if (!mounted) return;
      setState(() {
        _usernameExists = false;
        _isCheckingUsername = false;
        _usernameValidationMessage = null;
      });
      return;
    }

    if (username.length < 3) {
      if (!mounted) return;
      setState(() {
        _usernameExists = false;
        _isCheckingUsername = false;
        _usernameValidationMessage = 'Username must be at least 3 characters.';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameValidationMessage = 'Checking username availability...';
    });

    _usernameValidationDebounce = Timer(
      const Duration(milliseconds: 450),
      () async {
        try {
          final result = await _accountPolicyService.validateRegistrationPolicy(
            username: username,
          );
          if (!mounted || usernameController.text.trim() != username) return;
          setState(() {
            _isCheckingUsername = false;
            _usernameExists = result.usernameExists;
            _usernameValidationMessage = result.usernameExists
                ? result.duplicateAccountMessage
                : 'Username is available.';
          });
        } catch (_) {
          if (!mounted || usernameController.text.trim() != username) return;
          setState(() {
            _isCheckingUsername = false;
            _usernameValidationMessage =
                'Username availability will be confirmed during signup.';
          });
        }
      },
    );
  }

  void _scheduleEmailAvailabilityCheck() {
    _emailValidationDebounce?.cancel();
    final email = emailController.text.trim();

    if (email.isEmpty) {
      if (!mounted) return;
      setState(() {
        _emailExists = false;
        _isCheckingEmail = false;
        _emailValidationMessage = null;
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailValidationMessage = 'Checking email availability...';
    });

    _emailValidationDebounce = Timer(
      const Duration(milliseconds: 450),
      () async {
        try {
          final result = await _accountPolicyService.validateRegistrationPolicy(
            email: email,
          );
          if (!mounted || emailController.text.trim() != email) return;
          setState(() {
            _isCheckingEmail = false;
            _emailExists = result.emailExists;
            _emailValidationMessage = result.emailExists
                ? result.duplicateAccountMessage
                : 'Email is available.';
          });
        } catch (_) {
          if (!mounted || emailController.text.trim() != email) return;
          setState(() {
            _isCheckingEmail = false;
            _emailValidationMessage =
                'Email availability will be confirmed during signup.';
          });
        }
      },
    );
  }

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

  Widget? _buildAvailabilitySuffix({
    required String value,
    required bool isChecking,
    required bool isUnavailable,
    required int minLength,
  }) {
    if (isChecking) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (value.trim().length < minLength) {
      return null;
    }

    return Icon(
      isUnavailable ? Icons.error_outline_rounded : Icons.check_circle_rounded,
      color: isUnavailable ? const Color(0xFFFF8A65) : const Color(0xFF81C784),
      size: 20,
    );
  }

  Widget _buildValidationMessage({
    required String? message,
    required bool isError,
  }) {
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFFFF8A65) : const Color(0xFF81C784),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _writeUserRoleToRealtimeDb({
    required String uid,
    required String username,
    required String email,
    required String role,
    BarangayReference? barangay,
  }) async {
    final roleRef = FirebaseDatabase.instance.ref().child('users').child(uid);

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
      'approvalStatus': 'approved',
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
        final retryableCodes = <String>{
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
      'approvalStatus': 'approved',
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
        'source': 'firestore-signup-fallback',
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
          'approvalStatus': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'firestore-signup-fallback',
        }, SetOptions(merge: true));
      }

      if (barangayStatusRef != null && barangay != null) {
        transaction.set(barangayStatusRef, {
          'uid': uid,
          'barangay': barangay.name,
          'barangayCode': normalizedBarangayCode,
          'barangayDistrict': barangay.district,
          'accountStatus': 'active',
          'approvalStatus': 'approved',
          'isAvailable': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'firestore-signup-fallback',
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

    if (_isCheckingEmail ||
        _isCheckingUsername ||
        _isCheckingBarangayAvailability) {
      Get.snackbar(
        'Validation in progress',
        'Please wait while the system verifies account and barangay availability.',
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
        if (mounted) {
          setState(() {
            _emailExists = precheck.emailExists;
            _usernameExists = precheck.usernameExists;
            if (precheck.emailExists) {
              _emailValidationMessage = precheck.duplicateAccountMessage;
            }
            if (precheck.usernameExists) {
              _usernameValidationMessage = precheck.duplicateAccountMessage;
            }
          });
        }
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
        debugPrint(
          'Signup policy precheck unavailable, continuing with fallback: $e',
        );
      }
      if (_requiresStrictBarangayPolicy(_selectedRole) &&
          _selectedBarangay != null) {
        try {
          final barangayCode = _selectedBarangay!.code;
          final fallbackStatus = await _accountPolicyService
              .getBarangayAvailabilityStatus(barangayCode);

          if (mounted) {
            setState(() {
              if (fallbackStatus == null) {
                _barangayAvailabilityByCode.remove(barangayCode);
              } else {
                _barangayAvailabilityByCode[barangayCode] = fallbackStatus;
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
      // Create user account
      userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text,
          )
          .timeout(const Duration(seconds: 45));

      // Update display name
      await userCredential.user!
          .updateDisplayName(usernameController.text.trim())
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
            debugPrint(
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

      // Best-effort mirror for login fallback when Firestore is temporarily unavailable.
      // Run in background so RTDB timeouts don't block signup completion.
      unawaited(
        _writeUserRoleToRealtimeDb(
          uid: userCredential.user!.uid,
          username: username,
          email: email,
          role: _selectedRole!,
          barangay: _selectedBarangay,
        ).catchError((Object e) {
          if (kDebugMode) {
            debugPrint('RTDB role mirror write failed during signup: $e');
          }
        }),
      );

      Get.snackbar(
        'Account created',
        'Your ${_selectedRole!} account is authenticated and ready to use.',
        backgroundColor: const Color(0xFF388E3C),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );

      // Firebase authentication plus the validated BHW/CHO registration is
      // sufficient for immediate access. Admin roles are never accepted here.
      final role = (_selectedRole ?? '').toUpperCase();
      try {
        await userCredential.user!.getIdToken(true);
      } catch (_) {
        // Firestore profile fallback still provides the approved role.
      }
      if (role == 'CHO') {
        ChoAccessSession.trustedUid = userCredential.user!.uid;
        Get.offAllNamed(
          WebRoutes.choDashboard,
          arguments: {
            'roleValidated': true,
            'uid': userCredential.user!.uid,
            'role': 'cho',
          },
        );
      } else {
        ChoAccessSession.trustedUid = null;
        Get.offAllNamed(WebRoutes.bhwDashboard);
      }
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

  Widget _buildBrandMark(double size) {
    // Pre-processed white-on-transparent PNG (derived from newlogo.png's
    // luminance) — avoids ColorFilter.matrix, whose offset-scale behavior
    // is inconsistent across Flutter's web renderers.
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/newlogo_white.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.health_and_safety_rounded,
          color: Colors.white,
          size: size * 0.68,
        ),
      ),
    );
  }

  Widget _buildHeroPanel({required bool isCompact}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 20 : 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBrandMark(isCompact ? 190 : 300),
              const SizedBox(height: 28),
              Text(
                'AI-DSUHIS',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: isCompact ? 32 : 52,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Create secure access to unified city and barangay health information.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: isCompact ? 15 : 20,
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Choose the correct role and provide the details needed for a reliable, approval-aware account.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: isCompact ? 13 : 15,
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 900;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Manrope'),
      ),
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        body: Stack(
          children: [
            // Static reference background. It is isolated from the form
            // layout so resizing/zooming cannot move the composition.
            Positioned.fill(
              child: Image.asset(
                'assets/bg2.2.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(color: _darkDeepTeal);
                },
              ),
            ),
            Positioned.fill(child: ColoredBox(color: Color(0xD9071A33))),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWideScreen ? 32 : 24,
                    vertical: 40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: isWideScreen
                        ? _buildWideScreenLayout(context)
                        : _buildMobileLayout(context),
                  ),
                ),
              ),
            ),

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
                      const LandingPage(),
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

  // Wide screen layout (desktop/tablet landscape)
  Widget _buildWideScreenLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 10,
          child: Padding(
            padding: const EdgeInsets.only(right: 28),
            child: _buildHeroPanel(isCompact: false),
          ),
        ),
        Expanded(flex: 11, child: _buildSignupCard(context, isCompact: false)),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeroPanel(isCompact: true),
        const SizedBox(height: 16),
        _buildSignupCard(context, isCompact: true),
      ],
    );
  }

  // Signup card widget
  Widget _buildSignupCard(BuildContext context, {required bool isCompact}) {
    Widget fieldLabel(String label, Widget child) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(context, label),
          const SizedBox(height: 8),
          child,
        ],
      );
    }

    final username = fieldLabel(
      'Username',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: usernameController,
            hintText: 'Enter your username',
            icon: Icons.person_outline,
            suffixIcon: _buildAvailabilitySuffix(
              value: usernameController.text,
              isChecking: _isCheckingUsername,
              isUnavailable: _usernameExists,
              minLength: 3,
            ),
          ),
          _buildValidationMessage(
            message: _usernameValidationMessage,
            isError: _usernameExists,
          ),
        ],
      ),
    );
    final email = fieldLabel(
      'Email address',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: emailController,
            hintText: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            suffixIcon: _buildAvailabilitySuffix(
              value: emailController.text,
              isChecking: _isCheckingEmail,
              isUnavailable: _emailExists,
              minLength: 4,
            ),
          ),
          _buildValidationMessage(
            message: _emailValidationMessage,
            isError: _emailExists,
          ),
        ],
      ),
    );
    final accountType = fieldLabel('Account type', _buildRoleSelector());
    final password = fieldLabel('Password', _buildPasswordField());
    final confirm = fieldLabel(
      'Confirm password',
      _buildConfirmPasswordField(),
    );

    Widget desktopPair(Widget first, Widget second) {
      if (isCompact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 14), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 14),
          Expanded(child: second),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.all(isCompact ? 20 : 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create your account',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: isCompact ? 27 : 32,
                fontWeight: FontWeight.w800,
                color: _darkDeepTeal,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Register with the role and access details required for your health workflow.',
              style: TextStyle(color: _mutedCoolGray, height: 1.4),
            ),
            const SizedBox(height: 22),
            desktopPair(username, email),
            const SizedBox(height: 14),
            desktopPair(accountType, password),
            const SizedBox(height: 14),
            if (isCompact) confirm else desktopPair(confirm, const SizedBox()),
            if (_requiresBarangayAssignment) ...[
              const SizedBox(height: 16),
              _buildFieldLabel(context, 'Assigned barangay'),
              const SizedBox(height: 8),
              _buildBarangaySelector(),
              if (_selectedBarangay != null && !isCompact) ...[
                const SizedBox(height: 12),
                _buildBarangayLogoPreview(),
              ],
            ] else if (_isChoRegistration) ...[
              const SizedBox(height: 16),
              _buildChoAccessNotice(),
            ],
            const SizedBox(height: 18),
            Text(
              'CHO account registration is handled here. BHW applicants must use the dedicated BHW request page and wait for approval.',
              style: TextStyle(
                color: _mutedCoolGray,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : signup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB8C9CC),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Create account',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: _mutedCoolGray, fontSize: 13),
                  children: [
                    const TextSpan(text: 'Already have an account? '),
                    TextSpan(
                      text: 'Sign in',
                      style: const TextStyle(
                        color: _primaryAqua,
                        fontWeight: FontWeight.w800,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => replaceWithAuthPage(
                          context,
                          const Login(),
                          begin: const Offset(-0.06, 0),
                        ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method for field labels
  Widget _buildFieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        color: _darkDeepTeal,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Future<void> _showBarangayPicker() async {
    await _refreshBarangayAvailability(silent: true);
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 720;
    final selection = isMobile
        ? await showModalBottomSheet<BarangayReference>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (dialogContext) => FractionallySizedBox(
              heightFactor: 0.92,
              child: _BarangayPickerSheet(
                selectedBarangay: _selectedBarangay,
                brandingCache: _brandingCache,
                availabilityByCode: _barangayAvailabilityByCode,
                onSelected: (barangay) {
                  Navigator.of(dialogContext).pop(barangay);
                },
              ),
            ),
          )
        : await showDialog<BarangayReference>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.55),
            builder: (dialogContext) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 880,
                  maxHeight: 760,
                ),
                child: _BarangayPickerSheet(
                  selectedBarangay: _selectedBarangay,
                  brandingCache: _brandingCache,
                  availabilityByCode: _barangayAvailabilityByCode,
                  onSelected: (barangay) {
                    Navigator.of(dialogContext).pop(barangay);
                  },
                ),
              ),
            ),
          );

    if (selection != null && mounted) {
      setState(() {
        _selectedBarangay = selection;
        _showBarangayValidationError = false;
      });
      _syncSelectedBarangayRestriction();
    }
  }

  // Helper method for text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        autofillHints: keyboardType == TextInputType.emailAddress
            ? const [AutofillHints.email]
            : const [AutofillHints.username],
        style: TextStyle(
          color: _darkDeepTeal,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.72),
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: const Color(0xFFD7E3E5), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FBFB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.32)),
        color: const Color(0xFFF8FBFB),
      ),
      child: Row(
        children: [Expanded(child: _buildRoleOption(label: 'CHO'))],
      ),
    );
  }

  Widget _buildBarangaySelector() {
    final barangay = _selectedBarangay;
    final profile = barangay == null
        ? null
        : _brandingCache[barangay.code] ??
              BarangayBrandingProfile.fallback(barangay);
    final availability = barangay == null
        ? null
        : _barangayAvailabilityByCode[barangay.code];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _isLoading ? null : _showBarangayPicker,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: const Color(0xFFF8FBFB),
              border: Border.all(
                color:
                    _showBarangayValidationError || _selectedBarangayUnavailable
                    ? const Color(0xFFFF7043)
                    : barangay == null
                    ? _primaryAqua.withValues(alpha: 0.22)
                    : _primaryAqua,
                width: _showBarangayValidationError ? 1.6 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      ((_showBarangayValidationError ||
                                  _selectedBarangayUnavailable)
                              ? const Color(0xFFFF7043)
                              : Colors.black)
                          .withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: _primaryAqua,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            barangay == null
                                ? 'Search barangay or district'
                                : 'Assigned Barangay Selected',
                            style: TextStyle(
                              color: barangay == null
                                  ? _darkDeepTeal
                                  : _primaryAqua,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            barangay == null
                                ? 'Type to search, browse by district, and select in seconds.'
                                : 'Tap to change or remove the current assignment.',
                            style: TextStyle(
                              color: _mutedCoolGray,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _primaryAqua,
                      size: 28,
                    ),
                  ],
                ),
                if (barangay != null) ...[
                  const SizedBox(height: 16),
                  _buildSelectedBarangayPill(
                    barangay,
                    profile!,
                    availability: availability,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_showBarangayValidationError || _selectedBarangayUnavailable) ...[
          const SizedBox(height: 8),
          Text(
            _barangayRestrictionMessage ??
                'Please select your barangay to continue',
            style: TextStyle(
              color: const Color(0xFFFF8A65),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (_isCheckingBarangayAvailability) ...[
          const SizedBox(height: 8),
          Text(
            'Checking barangay availability...',
            style: TextStyle(
              color: _mutedCoolGray,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedBarangayPill(
    BarangayReference barangay,
    BarangayBrandingProfile profile, {
    BarangayAvailabilityStatus? availability,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          BarangayLogoImage(
            imageUrl: profile.hasCustomLogo ? profile.resolvedLogoUrl : null,
            assetPath: profile.localAssetPath,
            size: 52,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        barangay.name,
                        style: const TextStyle(
                          color: _darkDeepTeal,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF81C784),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  barangay.district,
                  style: TextStyle(color: _mutedCoolGray, fontSize: 12.5),
                ),
                if (availability != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    availability.availabilityLabel,
                    style: TextStyle(
                      color: availability.isAvailable
                          ? const Color(0xFF81C784)
                          : const Color(0xFFFF8A65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _selectedBarangay = null;
                        _showBarangayValidationError = false;
                      });
                    },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: _darkDeepTeal,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarangayLogoPreview() {
    final barangay = _selectedBarangay;
    if (barangay == null) {
      return const SizedBox.shrink();
    }

    return Builder(
      builder: (context) {
        final profile =
            _brandingCache[barangay.code] ??
            BarangayBrandingProfile.fallback(barangay);
        final hasOfficialMetadata =
            profile.assignedOfficial.trim().isNotEmpty ||
            profile.effectiveDate.trim().isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFF0F8F8),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BarangayLogoImage(
                imageUrl: profile.hasCustomLogo
                    ? profile.resolvedLogoUrl
                    : null,
                assetPath: profile.localAssetPath,
                size: 88,
                borderRadius: BorderRadius.circular(18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      barangay.name,
                      style: const TextStyle(
                        color: _darkDeepTeal,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      barangay.district,
                      style: TextStyle(color: _mutedCoolGray, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.hasCustomLogo
                          ? 'Official barangay logo loaded from the centralized repository.'
                          : profile.hasLocalAssetLogo
                          ? 'Official barangay logo loaded from the local logo library for this barangay.'
                          : 'No barangay-specific logo has been published yet for this barangay.',
                      style: TextStyle(
                        color: _mutedCoolGray,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (hasOfficialMetadata) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (profile.assignedOfficial.trim().isNotEmpty)
                            _buildBrandingMetaChip(
                              Icons.badge_outlined,
                              profile.assignedOfficial,
                            ),
                          if (profile.effectiveDate.trim().isNotEmpty)
                            _buildBrandingMetaChip(
                              Icons.event_outlined,
                              profile.effectiveDate,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBrandingMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFF8FBFB),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _primaryAqua),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _mutedCoolGray,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOption({required String label}) {
    final isSelected = _selectedRole == label;
    return InkWell(
      onTap: () => setState(() {
        _selectedRole = label;
        if (label == 'CHO') {
          _selectedBarangay = null;
          _showBarangayValidationError = false;
          _selectedBarangayUnavailable = false;
          _barangayRestrictionMessage = null;
        } else {
          unawaited(_refreshBarangayAvailability(silent: true));
        }
      }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? _primaryAqua : const Color(0xFFF8FBFB),
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
              color: _darkDeepTeal,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoAccessNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F8F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, color: _primaryAqua),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHO accounts use city-wide access',
                  style: TextStyle(
                    color: _darkDeepTeal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No barangay assignment is required. A successfully registered CHO account receives city-wide access immediately.',
                  style: TextStyle(color: _mutedCoolGray, height: 1.4),
                ),
              ],
            ),
          ),
        ],
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
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: passwordController,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.newPassword],
        style: TextStyle(
          color: _darkDeepTeal,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'At least 6 characters',
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.72),
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            color: _primaryAqua,
            size: 20,
          ),
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
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
            borderSide: BorderSide(color: const Color(0xFFD7E3E5), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FBFB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  // Helper method for confirm password field
  Widget _buildConfirmPasswordField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: confirmPasswordController,
        obscureText: _obscureConfirmPassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        style: TextStyle(
          color: _darkDeepTeal,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'Re-enter your password',
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.72),
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            color: _primaryAqua,
            size: 20,
          ),
          suffixIcon: IconButton(
            tooltip: _obscureConfirmPassword
                ? 'Show password'
                : 'Hide password',
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _mutedCoolGray,
              size: 20,
            ),
            onPressed: () {
              setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              );
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFFD7E3E5), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FBFB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}

class _BarangayPickerSheet extends StatefulWidget {
  final BarangayReference? selectedBarangay;
  final Map<String, BarangayBrandingProfile> brandingCache;
  final Map<String, BarangayAvailabilityStatus> availabilityByCode;
  final ValueChanged<BarangayReference> onSelected;

  const _BarangayPickerSheet({
    required this.selectedBarangay,
    required this.brandingCache,
    required this.availabilityByCode,
    required this.onSelected,
  });

  @override
  State<_BarangayPickerSheet> createState() => _BarangayPickerSheetState();
}

class _BarangayPickerSheetState extends State<_BarangayPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late Set<String> _expandedDistricts;
  int _highlightedIndex = 0;
  String _selectedDistrictFilter = 'ALL';

  List<String> get _districtOrder => MalaybalayBarangays.districtOrder;

  List<String> get _availableDistrictFilters {
    final seen = <String>{};
    final ordered = <String>['ALL'];

    for (final district in _districtOrder) {
      if (seen.add(district)) {
        ordered.add(district);
      }
    }

    for (final barangay in MalaybalayBarangays.all) {
      if (seen.add(barangay.district)) {
        ordered.add(barangay.district);
      }
    }

    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _expandedDistricts = _districtOrder.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _keyboardFocusNode.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<BarangayReference> get _filteredBarangays {
    return MalaybalayBarangays.search(
      _query,
      district: _selectedDistrictFilter == 'ALL'
          ? null
          : _selectedDistrictFilter,
    );
  }

  Map<String, List<BarangayReference>> get _groupedBarangays {
    final grouped = <String, List<BarangayReference>>{
      for (final district in _districtOrder) district: <BarangayReference>[],
    };
    for (final barangay in _filteredBarangays) {
      grouped.putIfAbsent(barangay.district, () => <BarangayReference>[]);
      grouped[barangay.district]!.add(barangay);
    }
    grouped.removeWhere((_, value) => value.isEmpty);
    return grouped;
  }

  List<BarangayReference> get _visibleBarangays {
    final result = <BarangayReference>[];
    final grouped = _groupedBarangays;
    for (final district in _districtOrder) {
      final items = grouped[district];
      if (items == null || !_expandedDistricts.contains(district)) continue;
      result.addAll(items);
    }
    for (final entry in grouped.entries) {
      if (_districtOrder.contains(entry.key)) continue;
      if (_expandedDistricts.contains(entry.key)) {
        result.addAll(entry.value);
      }
    }
    return result;
  }

  void _refreshExpandedDistricts() {
    _expandedDistricts = _groupedBarangays.keys.toSet();
  }

  void _moveHighlight(int delta) {
    final total = _visibleBarangays.length;
    if (total == 0) return;
    setState(() {
      _highlightedIndex = (_highlightedIndex + delta) % total;
      if (_highlightedIndex < 0) {
        _highlightedIndex = total - 1;
      }
    });
    final offset = (_highlightedIndex * 98.0).clamp(
      0.0,
      _scrollController.position.hasContentDimensions
          ? _scrollController.position.maxScrollExtent
          : 0.0,
    );
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectHighlighted() {
    final options = _visibleBarangays;
    if (options.isEmpty) return;
    final selected = options[_highlightedIndex];
    final availability = widget.availabilityByCode[selected.code];
    if (availability != null && !availability.isAvailable) {
      return;
    }
    widget.onSelected(selected);
  }

  List<TextSpan> _highlightText(
    String source,
    TextStyle baseStyle,
    TextStyle highlightedStyle,
  ) {
    if (_query.isEmpty) {
      return <TextSpan>[TextSpan(text: source, style: baseStyle)];
    }

    final lowerSource = source.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final matchIndex = lowerSource.indexOf(_query, start);
      if (matchIndex < 0) {
        spans.add(TextSpan(text: source.substring(start), style: baseStyle));
        break;
      }
      if (matchIndex > start) {
        spans.add(
          TextSpan(text: source.substring(start, matchIndex), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: source.substring(matchIndex, matchIndex + _query.length),
          style: highlightedStyle,
        ),
      );
      start = matchIndex + _query.length;
    }
    return spans;
  }

  Widget _buildDistrictFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableDistrictFilters.map((district) {
        final isSelected = _selectedDistrictFilter == district;
        final label = district == 'ALL' ? 'All Districts' : district;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDistrictFilter = district;
              _highlightedIndex = 0;
              _refreshExpandedDistricts();
            });
          },
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? _primaryAqua.withValues(alpha: 0.18)
                  : _panelSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? _primaryAqua
                    : _primaryAqua.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? _primaryAqua : _lightOffWhite,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedBarangays;
    final visible = _visibleBarangays;

    if (_highlightedIndex >= visible.length && visible.isNotEmpty) {
      _highlightedIndex = 0;
    }

    return Focus(
      autofocus: true,
      focusNode: _keyboardFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveHighlight(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveHighlight(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _selectHighlighted();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _sidebarDark,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.18),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _darkDeepTeal.withValues(alpha: 0.96),
                      _panelSurface.withValues(alpha: 0.96),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _primaryAqua.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.travel_explore_rounded,
                            color: _primaryAqua,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Assigned Barangay',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Search instantly, browse by district, or navigate with arrow keys and Enter.',
                                style: TextStyle(
                                  color: _mutedCoolGray,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: _lightOffWhite,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _panelSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.16),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: (_) {
                          setState(() {
                            _highlightedIndex = 0;
                            _refreshExpandedDistricts();
                          });
                        },
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type barangay name, district, or code',
                          hintStyle: TextStyle(
                            color: _mutedCoolGray.withValues(alpha: 0.88),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _primaryAqua,
                          ),
                          suffixIcon: _searchController.text.isEmpty
                              ? const Icon(
                                  Icons.keyboard_command_key_rounded,
                                  color: _mutedCoolGray,
                                  size: 18,
                                )
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _highlightedIndex = 0;
                                      _refreshExpandedDistricts();
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _lightOffWhite,
                                  ),
                                ),
                          filled: true,
                          fillColor: _panelSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _primaryAqua.withValues(alpha: 0.16),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: _primaryAqua,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildDistrictFilterChips(),
                    if (widget.selectedBarangay != null) ...[
                      const SizedBox(height: 14),
                      _SelectedBarangayChip(
                        barangay: widget.selectedBarangay!,
                        profile:
                            widget.brandingCache[widget
                                .selectedBarangay!
                                .code] ??
                            BarangayBrandingProfile.fallback(
                              widget.selectedBarangay!,
                            ),
                        availability: widget
                            .availabilityByCode[widget.selectedBarangay!.code],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 46,
                                color: _mutedCoolGray.withValues(alpha: 0.72),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No barangay matches your search.',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Try a barangay name, district, or code.',
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.64),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                        itemCount: grouped.keys.length,
                        itemBuilder: (context, groupIndex) {
                          final district = grouped.keys.elementAt(groupIndex);
                          final items = grouped[district]!;
                          final expanded = _expandedDistricts.contains(
                            district,
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _panelSurface,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (expanded) {
                                          _expandedDistricts.remove(district);
                                        } else {
                                          _expandedDistricts.add(district);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(22),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _primaryAqua.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: const Icon(
                                              Icons.account_tree_outlined,
                                              color: _primaryAqua,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  district,
                                                  style: const TextStyle(
                                                    color: _lightOffWhite,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${items.length} barangay${items.length == 1 ? '' : 's'}',
                                                  style: TextStyle(
                                                    color: _lightOffWhite
                                                        .withValues(
                                                          alpha: 0.60,
                                                        ),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          AnimatedRotation(
                                            turns: expanded ? 0.5 : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: _primaryAqua,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        12,
                                      ),
                                      child: Column(
                                        children: items.asMap().entries.map((
                                          entry,
                                        ) {
                                          final barangay = entry.value;
                                          final globalIndex = visible.indexOf(
                                            barangay,
                                          );
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              top: entry.key == 0 ? 0 : 10,
                                            ),
                                            child: _BarangayResultTile(
                                              barangay: barangay,
                                              profile:
                                                  widget.brandingCache[barangay
                                                      .code] ??
                                                  BarangayBrandingProfile.fallback(
                                                    barangay,
                                                  ),
                                              availability:
                                                  widget
                                                      .availabilityByCode[barangay
                                                      .code],
                                              query: _query,
                                              isSelected:
                                                  widget
                                                      .selectedBarangay
                                                      ?.code ==
                                                  barangay.code,
                                              isHighlighted:
                                                  globalIndex ==
                                                  _highlightedIndex,
                                              highlightText: _highlightText,
                                              onTap: () =>
                                                  widget.onSelected(barangay),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    crossFadeState: expanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    duration: const Duration(milliseconds: 180),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedBarangayChip extends StatelessWidget {
  final BarangayReference barangay;
  final BarangayBrandingProfile profile;
  final BarangayAvailabilityStatus? availability;

  const _SelectedBarangayChip({
    required this.barangay,
    required this.profile,
    this.availability,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          BarangayLogoImage(
            imageUrl: profile.hasCustomLogo ? profile.resolvedLogoUrl : null,
            assetPath: profile.localAssetPath,
            size: 44,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current selection',
                  style: TextStyle(
                    color: _primaryAqua,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  barangay.name,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  barangay.district,
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
                if (availability != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    availability!.availabilityLabel,
                    style: TextStyle(
                      color: availability!.isAvailable
                          ? const Color(0xFF81C784)
                          : const Color(0xFFFF8A65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Color(0xFF81C784)),
        ],
      ),
    );
  }
}

class _BarangayResultTile extends StatelessWidget {
  final BarangayReference barangay;
  final BarangayBrandingProfile profile;
  final BarangayAvailabilityStatus? availability;
  final String query;
  final bool isSelected;
  final bool isHighlighted;
  final List<TextSpan> Function(
    String source,
    TextStyle baseStyle,
    TextStyle highlightedStyle,
  )
  highlightText;
  final VoidCallback onTap;

  const _BarangayResultTile({
    required this.barangay,
    required this.profile,
    required this.availability,
    required this.query,
    required this.isSelected,
    required this.isHighlighted,
    required this.highlightText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnavailable = availability != null && !availability!.isAvailable;
    const nameStyle = TextStyle(
      color: _lightOffWhite,
      fontWeight: FontWeight.w700,
      fontSize: 14.5,
    );
    final mutedStyle = TextStyle(
      color: _lightOffWhite.withValues(alpha: 0.62),
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
    );
    const highlightedStyle = TextStyle(
      color: Color(0xFFFFC857),
      fontWeight: FontWeight.w800,
      fontSize: 14.5,
    );
    final districtHighlightedStyle = highlightedStyle.copyWith(fontSize: 12.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isUnavailable ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnavailable
                ? Colors.white.withValues(alpha: 0.025)
                : isSelected
                ? _primaryAqua.withValues(alpha: 0.12)
                : isHighlighted
                ? Colors.white.withValues(alpha: 0.05)
                : _darkDeepTeal,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUnavailable
                  ? const Color(0xFFFF8A65).withValues(alpha: 0.35)
                  : isSelected
                  ? _primaryAqua
                  : isHighlighted
                  ? _primaryAqua.withValues(alpha: 0.38)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              BarangayLogoImage(
                imageUrl: profile.hasCustomLogo
                    ? profile.resolvedLogoUrl
                    : null,
                assetPath: profile.localAssetPath,
                size: 56,
                borderRadius: BorderRadius.circular(16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: highlightText(
                          barangay.name,
                          nameStyle.copyWith(
                            color: isUnavailable
                                ? _lightOffWhite.withValues(alpha: 0.74)
                                : _lightOffWhite,
                          ),
                          highlightedStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: highlightText(
                          barangay.district,
                          mutedStyle.copyWith(
                            color: isUnavailable
                                ? _lightOffWhite.withValues(alpha: 0.48)
                                : _lightOffWhite.withValues(alpha: 0.62),
                          ),
                          districtHighlightedStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            barangay.code,
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.58),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isUnavailable)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF7043,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF8A65,
                                ).withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Text(
                              'Already Registered',
                              style: TextStyle(
                                color: Color(0xFFFF8A65),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isUnavailable
                    ? Icons.block_rounded
                    : isSelected
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_ios_rounded,
                color: isUnavailable
                    ? const Color(0xFFFF8A65)
                    : isSelected
                    ? const Color(0xFF81C784)
                    : _primaryAqua,
                size: isSelected || isUnavailable ? 22 : 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
