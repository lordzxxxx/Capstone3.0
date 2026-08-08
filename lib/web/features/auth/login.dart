import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/roles/cho/admin/cho_super_admin_center.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/features/auth/landing.dart';
import 'package:flutter/gestures.dart';
import 'package:mycapstone_project/web/features/auth/signup.dart';
import 'package:mycapstone_project/web/features/auth/forgot.dart';
import 'package:mycapstone_project/web/roles/cho/dashboard/cho_dashboard.dart'
    as cho;
import 'package:mycapstone_project/web/features/auth/cho_access_session.dart';
import 'package:mycapstone_project/web/roles/bhw/referrals/referrals.dart';
import 'package:mycapstone_project/web/shared/widgets/auth_page_transition.dart';
import 'package:mycapstone_project/web/shared/widgets/login_success_sweet_alert.dart';
import 'package:mycapstone_project/web/shared/services/firestore_rest_reader.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = Color(0xFF0E2F34);
const Color _panelSurface = Color(0xFF061920);

class _RoleCheckResult {
  final bool hasAccess;
  final bool verificationUnavailable;
  final String? resolvedRole;

  const _RoleCheckResult._({
    required this.hasAccess,
    required this.verificationUnavailable,
    this.resolvedRole,
  });

  const _RoleCheckResult.allowed(String role)
    : this._(
        hasAccess: true,
        verificationUnavailable: false,
        resolvedRole: role,
      );
  const _RoleCheckResult.denied()
    : this._(hasAccess: false, verificationUnavailable: false);
  const _RoleCheckResult.unavailable()
    : this._(hasAccess: false, verificationUnavailable: true);
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  static const String _roleCacheKeyPrefix = 'verified_role_';
  FirebaseFirestore get _firestore => getFirestoreInstance();
  final FirestoreRestReader _restReader = const FirestoreRestReader();

  String _roleCacheKey(String uid) => '$_roleCacheKeyPrefix$uid';

  Future<void> _cacheRoleLocally(User user, String role) async {
    if (!_isChoOrBhwRole(role)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleCacheKey(user.uid), _normalizeRole(role));
      if (kDebugMode) {
        print(
          'Login role cache - saved local role "${_normalizeRole(role)}" for ${user.uid}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Login role cache - failed to save local role: $e');
      }
    }
  }

  Future<void> _clearCachedRoleLocally(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_roleCacheKey(user.uid));
      if (kDebugMode) {
        print('Login role cache - cleared local role for ${user.uid}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Login role cache - failed to clear local role: $e');
      }
    }
  }

  void _cacheRoleValidationForDashboard(User user) {
    ChoAccessSession.trustedUid = user.uid;
  }

  void _clearRoleValidationForDashboard() {
    ChoAccessSession.trustedUid = null;
  }

  Future<void> _safeOffAll(
    Widget page, {
    Map<String, dynamic>? arguments,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    Get.offAll(
      () => page,
      arguments: arguments,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 420),
    );
  }

  String _normalizeRole(String role) => role.toLowerCase().trim();

  bool _isApprovedActiveProfile(Map<String, dynamic>? data) {
    if (data == null) return false;
    final approval = (data['approvalStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final account = (data['accountStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return approval == 'approved' && account == 'active';
  }

  Future<Map<String, dynamic>?> _activateLegacyBhwOrChoProfile(
    User user,
    DocumentReference<Map<String, dynamic>> sourceReference,
    Map<String, dynamic>? profile,
  ) async {
    // Pending accounts must only be activated by an authorized CHO reviewer.
    // Keep this method for legacy document lookup without self-approving users.
    return profile;
  }

  Future<bool> _blockUnapprovedRegistration(User user) async {
    try {
      final profile = kIsWeb
          ? (await _restReader.getDocument('users', user.uid))?.data()
          : (await _firestore.collection('users').doc(user.uid).get()).data();
      if (profile == null) return false;
      final status = (profile['status'] ?? profile['accountStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final approval = (profile['approvalStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final isApproved = profile['isApproved'];
      final pending =
          approval == 'pending' ||
          status.contains('pending') ||
          isApproved == false && !status.contains('reject');
      final rejected = approval == 'rejected' || status.contains('reject');
      if (!pending && !rejected) return false;

      await _clearCachedRoleLocally(user);
      await FirebaseAuth.instance.signOut();
      if (rejected) {
        final reason = (profile['rejectionReason'] ?? 'No reason provided.')
            .toString()
            .trim();
        Get.snackbar(
          'Registration not approved',
          'Your registration request was not approved.\nReason: ${reason.isEmpty ? 'No reason provided.' : reason}',
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
          duration: const Duration(seconds: 8),
          mainButton: TextButton(
            onPressed: () => Get.snackbar(
              'Contact CHO',
              'Please contact the City Health Office to review your registration.',
              backgroundColor: _secondaryIceBlue,
              colorText: Colors.white,
            ),
            child: const Text(
              'Contact CHO',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      } else {
        Get.snackbar(
          'Account awaiting approval',
          'Your account is awaiting approval by the City Health Office. Please wait for approval before accessing AI-DSUHIS.',
          backgroundColor: Colors.orange.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 7),
        );
      }
      return true;
    } catch (error) {
      if (kDebugMode) print('Registration status check failed: $error');
      return false;
    }
  }

  bool _isChoRole(String role) => _normalizeRole(role) == 'cho';

  bool _isChoSuperAdminRole(String role) {
    final normalized = _normalizeRole(role);
    return normalized == 'cho_super_admin' ||
        normalized == 'super_admin' ||
        normalized == 'admin';
  }

  bool _isBhwRole(String role) => _normalizeRole(role) == 'bhw';

  bool _isDoctorRole(String role) => _normalizeRole(role) == 'doctor';

  bool _isChoOrBhwRole(String role) {
    return _isChoRole(role) ||
        _isBhwRole(role) ||
        _isDoctorRole(role) ||
        _isChoSuperAdminRole(role);
  }

  Future<void> _navigateByRole(User user, String role) async {
    if (_isChoSuperAdminRole(role)) {
      _clearRoleValidationForDashboard();
      await _safeOffAll(const ChoSuperAdminCenter());
      return;
    }

    if (_isChoRole(role)) {
      _cacheRoleValidationForDashboard(user);
      await _safeOffAll(
        const cho.ChoDashboard(),
        arguments: {'roleValidated': true, 'uid': user.uid, 'role': 'cho'},
      );
      return;
    }

    if (_isDoctorRole(role)) {
      _clearRoleValidationForDashboard();
      await _safeOffAll(const ReferralsPage());
      return;
    }

    // BHW and other non-CHO roles should not access the CHO dashboard route.
    _clearRoleValidationForDashboard();
    await _safeOffAll(const HomePage());
  }

  Future<void> _showSuccessDialogAndNavigate(User user, String role) async {
    final normalizedRole = _normalizeRole(role);
    final isSuperAdmin = _isChoSuperAdminRole(normalizedRole);
    final isCho = _isChoRole(normalizedRole);
    final isDoctor = _isDoctorRole(normalizedRole);
    final dashboardLabel = isSuperAdmin
        ? 'Super Admin Center'
        : isCho
        ? 'CHO Dashboard'
        : isDoctor
        ? 'Referral Center'
        : 'Dashboard';

    final proceedToDashboard = await showLoginSuccessSweetAlert(
      title: 'Login successful',
      message: isSuperAdmin
          ? 'Your CHO Super Admin account is verified. Continue to the governance center.'
          : isCho
          ? 'Your CHO account is verified. Continue to the CHO dashboard.'
          : isDoctor
          ? 'Your doctor account is verified. Continue to the referral center.'
          : 'Your account is verified. Continue to the dashboard.',
      confirmButtonText: 'Open $dashboardLabel',
    );

    if (!proceedToDashboard || !mounted) return;
    await _navigateByRole(user, normalizedRole);
  }

  bool _isRetryableFirestoreError(FirebaseException e) {
    const retryableCodes = <String>{
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'resource-exhausted',
      'unavailable',
      'unknown',
    };
    return retryableCodes.contains(e.code);
  }

  Future<void> _ensureFirestoreNetworkReady() async {
    try {
      await _firestore.enableNetwork().timeout(const Duration(seconds: 4));
      if (kDebugMode) {
        print('Firestore network check - network enabled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Firestore network check - enableNetwork failed: $e');
      }
    }
  }

  Future<String?> _readRoleFromUsersByEmail(
    User user, {
    GetOptions? options,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return null;

    final normalizedEmail = email.toLowerCase();
    QuerySnapshot<Map<String, dynamic>> snapshot;

    if (options == null) {
      snapshot = await _firestore
          .collection('users')
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get()
          .timeout(timeout);
    } else {
      snapshot = await _firestore
          .collection('users')
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get(options)
          .timeout(timeout);
    }

    if (snapshot.docs.isEmpty) {
      if (options == null) {
        snapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get()
            .timeout(timeout);
      } else {
        snapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(options)
            .timeout(timeout);
      }
    }

    if (snapshot.docs.isEmpty) {
      if (kDebugMode) {
        print('Firestore email lookup - no users doc found for $email');
      }
      return null;
    }

    final doc = snapshot.docs.first;
    final profile = await _activateLegacyBhwOrChoProfile(
      user,
      doc.reference,
      doc.data(),
    );
    if (!_isApprovedActiveProfile(profile)) return null;
    final role = _normalizeRole((profile!['role'] ?? '').toString());
    if (kDebugMode) {
      print('Firestore email lookup - role="$role" docId=${doc.id}');
    }

    if (!_isChoOrBhwRole(role)) {
      return null;
    }

    if (doc.id != user.uid) {
      // Keep users/{uid} in sync when a legacy/non-uid doc id is detected.
      unawaited(
        _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'emailLower': normalizedEmail,
          'role': role.toUpperCase(),
          'migratedFromDocId': doc.id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    }

    return role;
  }

  Future<_RoleCheckResult> _hasChoOrBhwAccess(User user) async {
    if (kIsWeb) {
      try {
        if (kDebugMode) {
          print('Checking Firestore user role through authenticated REST...');
        }
        final document = await _restReader.getDocument('users', user.uid);
        if (document == null) return const _RoleCheckResult.denied();
        final profile = document.data();
        final role = _normalizeRole((profile['role'] ?? '').toString());
        if (_isApprovedActiveProfile(profile) && _isChoOrBhwRole(role)) {
          if (kDebugMode) print('Access granted via Firestore REST role');
          return _RoleCheckResult.allowed(role);
        }
        return const _RoleCheckResult.denied();
      } catch (error) {
        if (kDebugMode) {
          print('Firestore REST role verification failed: $error');
        }
        return const _RoleCheckResult.unavailable();
      }
    }

    // Verify strictly from Firestore users collection.
    bool sawTransientFailure = false;
    Object? lastFailure;

    await _ensureFirestoreNetworkReady();

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (kDebugMode) {
          print('Checking Firestore user role (attempt $attempt/3)...');
        }

        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 20));

        if (!userDoc.exists) {
          if (kDebugMode) {
            print(
              'User document users/${user.uid} not found in Firestore, trying email lookup...',
            );
          }
          final roleByEmail = await _readRoleFromUsersByEmail(
            user,
            timeout: const Duration(seconds: 12),
          );
          if (roleByEmail != null) {
            if (kDebugMode) {
              print('Access granted via Firestore email lookup');
            }
            return _RoleCheckResult.allowed(roleByEmail);
          }

          if (kDebugMode) print('User document not found in Firestore');
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 300 * attempt));
            continue;
          }
          break;
        }

        final profile = await _activateLegacyBhwOrChoProfile(
          user,
          userDoc.reference,
          userDoc.data(),
        );
        final role = (profile?['role'] ?? '').toString();
        if (kDebugMode) {
          print('Firestore role check result: role="$role"');
        }

        if (_isApprovedActiveProfile(profile) && _isChoOrBhwRole(role)) {
          if (kDebugMode) print('Access granted via Firestore role');
          return _RoleCheckResult.allowed(role);
        }

        if (kDebugMode) {
          print(
            'Firestore role exists but is not an allowed operations role: "$role"',
          );
        }
        return const _RoleCheckResult.denied();
      } on TimeoutException catch (e) {
        sawTransientFailure = true;
        lastFailure = e;
        if (kDebugMode) {
          print('Firestore attempt $attempt failed: $e');
        }
      } on FirebaseException catch (e) {
        if (kDebugMode) {
          print('Firestore attempt $attempt failed: [${e.code}] ${e.message}');
        }
        if (_isRetryableFirestoreError(e)) {
          sawTransientFailure = true;
          lastFailure = e;
        } else {
          // Verification could not be completed due to a non-retryable backend error.
          return const _RoleCheckResult.unavailable();
        }
      } catch (e) {
        sawTransientFailure = true;
        lastFailure = e;
        if (kDebugMode) {
          print('Firestore attempt $attempt failed: $e');
        }
      }

      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    if (sawTransientFailure) {
      await _ensureFirestoreNetworkReady();
      try {
        final recoveredDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (recoveredDoc.exists) {
          final recoveredProfile = await _activateLegacyBhwOrChoProfile(
            user,
            recoveredDoc.reference,
            recoveredDoc.data(),
          );
          final recoveredRole = _normalizeRole(
            (recoveredProfile?['role'] ?? '').toString(),
          );
          if (_isApprovedActiveProfile(recoveredProfile) &&
              _isChoOrBhwRole(recoveredRole)) {
            if (kDebugMode) {
              print('Access granted via Firestore role after network recovery');
            }
            return _RoleCheckResult.allowed(recoveredRole);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Firestore uid lookup after recovery failed: $e');
        }
      }

      try {
        final roleByEmail = await _readRoleFromUsersByEmail(
          user,
          options: const GetOptions(source: Source.server),
          timeout: const Duration(seconds: 10),
        );
        if (roleByEmail != null) {
          if (kDebugMode) {
            print(
              'Access granted via Firestore email lookup after network recovery',
            );
          }
          return _RoleCheckResult.allowed(roleByEmail);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Firestore email lookup after recovery failed: $e');
        }
      }

      if (kDebugMode) {
        print(
          'Could not verify CHO/BHW/Doctor/Super Admin role due to Firestore availability issues: $lastFailure',
        );
      }
      return const _RoleCheckResult.unavailable();
    }

    if (kDebugMode) {
      print(
        'No valid CHO/BHW/Doctor/Super Admin role found in Firestore users collection',
      );
    }
    return const _RoleCheckResult.denied();
  }

  Future<void> _handleRoleVerificationFailure(_RoleCheckResult result) async {
    _clearRoleValidationForDashboard();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!result.verificationUnavailable && currentUser != null) {
      await _clearCachedRoleLocally(currentUser);
    }
    await FirebaseAuth.instance.signOut();

    if (result.verificationUnavailable) {
      Get.snackbar(
        'Account Verification Unavailable',
        'Signed in, but we could not verify your role because Firestore is temporarily unavailable. Please check your connection and try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    if (kDebugMode) {
      print(
        'No valid CHO/BHW/Doctor/Super Admin role found in Firestore users collection',
      );
    }
    Get.snackbar(
      'Access Denied',
      'Your account was not verified in users collection as CHO, BHW, Doctor, or CHO Super Admin.',
      backgroundColor: const Color(0xFFD32F2F),
      colorText: Colors.white,
      duration: const Duration(seconds: 5),
    );
  }

  Future<String?> _readChoOrBhwRoleFromClaims(User user) async {
    try {
      if (kDebugMode) {
        print('Login fallback - checking custom claims...');
      }
      final idToken = await user
          .getIdTokenResult(true)
          .timeout(const Duration(seconds: 12));
      final claims = idToken.claims ?? {};
      final claimRole = _normalizeRole((claims['role'] ?? '').toString());
      final claimRoles = (claims['roles'] is List)
          ? (claims['roles'] as List)
                .map((e) => _normalizeRole(e.toString()))
                .toList()
          : <String>[];
      if (kDebugMode) {
        print('Login fallback - claim role: "$claimRole", roles: $claimRoles');
      }

      if (_isChoOrBhwRole(claimRole)) {
        return claimRole;
      }
      for (final role in claimRoles) {
        if (_isChoOrBhwRole(role)) {
          return role;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Login fallback - custom claims check failed: $e');
      }
      return null;
    }
  }

  Future<String?> _tryRoleFallbackSources(User user) async {
    // Only server-issued custom claims are trusted when Firestore cannot be
    // verified. Local, cached, and Realtime Database roles can be stale.
    final claimRole = await _readChoOrBhwRoleFromClaims(user);
    if (claimRole != null) {
      if (kDebugMode) {
        print('Login fallback - access granted via custom claims: $claimRole');
      }
      return claimRole;
    }

    return null;
  }

  Future<void> signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final googleProvider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'login_hint': 'user@example.com'});

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithPopup(googleProvider);
      final user = userCredential.user;
      if (user == null) return;

      if (await _blockUnapprovedRegistration(user)) return;

      if (kDebugMode) {
        print('Verifying Google account from Firestore users collection...');
      }

      final roleCheckResult = await _hasChoOrBhwAccess(user);
      if (!roleCheckResult.hasAccess) {
        if (roleCheckResult.verificationUnavailable) {
          final fallbackRole = await _tryRoleFallbackSources(user);
          if (fallbackRole != null) {
            await _cacheRoleLocally(user, fallbackRole);
            await _showSuccessDialogAndNavigate(user, fallbackRole);
            return;
          }
        }
        await _handleRoleVerificationFailure(roleCheckResult);
        return;
      }

      if (kDebugMode) {
        print('Google login verified from Firestore users collection');
      }
      final resolvedRole = roleCheckResult.resolvedRole;
      if (resolvedRole == null || !_isChoOrBhwRole(resolvedRole)) {
        await _handleRoleVerificationFailure(const _RoleCheckResult.denied());
        return;
      }
      await _cacheRoleLocally(user, resolvedRole);
      await _showSuccessDialogAndNavigate(user, resolvedRole);
    } catch (e) {
      Get.snackbar(
        'Google Sign-In Failed',
        'Failed to sign in with Google. Please try again.',
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
      );
      debugPrint('Google Sign-In Error: $e');
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
    if (kDebugMode) {
      // Do not print the password itself; print length for debugging only
      final email = emailController.text.trim();
      final pwdLen = passwordController.text.length;
      // ignore: avoid_print
      print('Attempting signIn email=$email passwordLength=$pwdLen');
    }

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

      if (await _blockUnapprovedRegistration(currentUser)) return;

      // Verify account strictly from Firestore users collection.
      if (kDebugMode) {
        print(
          'Verifying account from Firestore users collection for ${currentUser.email}...',
        );
      }

      // Verify role
      final roleCheckResult = await _hasChoOrBhwAccess(currentUser);
      if (!roleCheckResult.hasAccess) {
        if (roleCheckResult.verificationUnavailable) {
          final fallbackRole = await _tryRoleFallbackSources(currentUser);
          if (fallbackRole != null) {
            if (kDebugMode) {
              print(
                'Login verified via fallback source (RTDB/custom claims): role=$fallbackRole',
              );
            }
            await _cacheRoleLocally(currentUser, fallbackRole);
            await _showSuccessDialogAndNavigate(currentUser, fallbackRole);
            return;
          }
        }
        await _handleRoleVerificationFailure(roleCheckResult);
        return;
      }

      if (kDebugMode) print('Login verified from Firestore users collection');
      final resolvedRole = roleCheckResult.resolvedRole;
      if (resolvedRole == null || !_isChoOrBhwRole(resolvedRole)) {
        await _handleRoleVerificationFailure(const _RoleCheckResult.denied());
        return;
      }
      await _cacheRoleLocally(currentUser, resolvedRole);
      await _showSuccessDialogAndNavigate(currentUser, resolvedRole);
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
          'FirebaseAuthException during signIn: code=${e.code} message=${e.message}',
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
      print('Unexpected signIn error: $e');
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

  Widget _buildBrandMark(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
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
          'assets/bg3.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_primaryAqua, _secondaryIceBlue],
                ),
              ),
              child: const Center(
                child: Text(
                  'DS',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroMetric(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _panelSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.68),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPanel({required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 24 : 34),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_sidebarDark, _panelSurface],
        ),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoPill(
                Icons.health_and_safety_outlined,
                'City health command center',
              ),
              _buildInfoPill(
                Icons.verified_user_outlined,
                'Role-secured access',
              ),
            ],
          ),
          SizedBox(height: isCompact ? 18 : 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBrandMark(isCompact ? 72 : 86),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DSUHIS',
                      style: TextStyle(
                        fontSize: isCompact ? 28 : 42,
                        fontWeight: FontWeight.w800,
                        color: _lightOffWhite,
                        letterSpacing: -1.2,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A calmer way to manage city and barangay health workflows.',
                      style: TextStyle(
                        fontSize: isCompact ? 15 : 18,
                        color: _lightOffWhite.withValues(alpha: 0.82),
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 20 : 28),
          Text(
            'Sign in once, then move directly into patients, referrals, analytics, and barangay-level monitoring without digging through disconnected screens.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.72),
              fontSize: isCompact ? 13.5 : 15,
              height: 1.65,
            ),
          ),
          SizedBox(height: isCompact ? 18 : 26),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildHeroMetric(
                '24/7',
                'Access to synchronized records and live dashboards',
              ),
              _buildHeroMetric(
                'Role-based',
                'CHO, doctor, and barangay workflows kept separated',
              ),
              _buildHeroMetric(
                'Fast',
                'Designed for quick log-in and fewer input errors',
              ),
            ],
          ),
          SizedBox(height: isCompact ? 20 : 28),
          _buildFeatureItem(
            Icons.shield_outlined,
            'Protected access and verified role routing',
          ),
          const SizedBox(height: 14),
          _buildFeatureItem(
            Icons.analytics_outlined,
            'Immediate visibility across health activity and outcomes',
          ),
          const SizedBox(height: 14),
          _buildFeatureItem(
            Icons.hub_outlined,
            'Connected city and barangay operations in one workspace',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelSurface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _primaryAqua),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.9),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 900;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_darkDeepTeal, _darkDeepTeal, _sidebarDark],
                ),
              ),
            ),

            Positioned(
              top: -100,
              right: -100,
              child: _buildBackdropOrb(
                size: 300,
                color: _primaryAqua.withValues(alpha: 0.14),
              ),
            ),

            Positioned(
              bottom: -150,
              left: -150,
              child: _buildBackdropOrb(
                size: 400,
                color: _secondaryIceBlue.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              top: size.height * 0.18,
              left: size.width * 0.12,
              child: _buildBackdropOrb(
                size: 220,
                color: _sidebarDark.withValues(alpha: 0.82),
              ),
            ),
            Positioned(
              top: size.height * 0.1,
              right: size.width * 0.24,
              child: _buildBackdropOrb(
                size: 180,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWideScreen ? 32 : 24,
                    vertical: 40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 11,
          child: Padding(
            padding: const EdgeInsets.only(right: 28),
            child: _buildHeroPanel(isCompact: false),
          ),
        ),
        Expanded(flex: 8, child: _buildLoginCard(context, isCompact: false)),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeroPanel(isCompact: true),
        const SizedBox(height: 16),
        _buildLoginCard(context, isCompact: true),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _panelSurface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: _primaryAqua, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: _lightOffWhite,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  // Login card widget
  Widget _buildLoginCard(BuildContext context, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 24 : 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sidebarDark, _sidebarDark, _panelSurface],
        ),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.20),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 44,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -10,
            child: _buildBackdropOrb(
              size: 180,
              color: _primaryAqua.withValues(alpha: 0.14),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _panelSurface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    _buildBrandMark(isCompact ? 48 : 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome Back',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: isCompact ? 26 : 30,
                              fontWeight: FontWeight.w800,
                              color: _lightOffWhite,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Secure access to city and barangay health operations.',
                            style: TextStyle(
                              fontSize: 13,
                              color: _lightOffWhite.withValues(alpha: 0.72),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Live',
                        style: TextStyle(
                          color: _primaryAqua,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 16 : 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildInfoPill(Icons.lock_outline_rounded, 'Secure sign in'),
                  _buildInfoPill(Icons.bolt_rounded, 'Fast dashboard access'),
                ],
              ),
              SizedBox(height: isCompact ? 16 : 18),
              _buildFieldLabel(context, 'Email Address'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: emailController,
                hintText: 'you@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _buildFieldLabel(context, 'Password'),
              const SizedBox(height: 8),
              _buildPasswordField(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    pushAuthPage(context, const ForgotPassword());
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: _primaryAqua,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _panelSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: _primaryAqua,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Use your approved CHO, doctor, or barangay account. Access is routed automatically after verification.',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.76),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua,
                    foregroundColor: _darkDeepTeal,
                    disabledBackgroundColor: _mutedCoolGray.withValues(
                      alpha: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
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
                            const Icon(Icons.login, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Sign In',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: _lightOffWhite.withValues(alpha: 0.14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: _lightOffWhite.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSocialButtonLarge(
                label: 'Continue with Google',
                icon: Icons.g_mobiledata,
                color: const Color(0xFF4285F4),
                onTap: _isLoading ? null : signInWithGoogle,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _panelSurface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.12),
                  ),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.78),
                      fontSize: 13.5,
                    ),
                    children: [
                      const TextSpan(text: "Don't have an account? "),
                      TextSpan(
                        text: 'Sign Up',
                        style: const TextStyle(
                          color: _primaryAqua,
                          fontWeight: FontWeight.w800,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            pushAuthPage(
                              context,
                              const Signup(preselectedRole: 'CHO'),
                            );
                          },
                      ),
                      const TextSpan(
                        text:
                            ' and wait for approval if your role requires review.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
        fontSize: 12.5,
        color: _lightOffWhite,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
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
        style: TextStyle(
          color: _lightOffWhite,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: _mutedCoolGray.withValues(alpha: 0.85),
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          filled: true,
          fillColor: _panelSurface.withValues(alpha: 0.96),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
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
            color: Colors.black.withValues(alpha: 0.12),
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
            color: _mutedCoolGray.withValues(alpha: 0.85),
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
              color: _primaryAqua.withValues(alpha: 0.22),
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
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
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
