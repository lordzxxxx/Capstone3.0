import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
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
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFFF8FBFF);
const Color _sidebarDark = Color(0xFF0D274D);

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
  const Login({super.key, this.expectedRole});

  /// Which portal this login entry point is for ('bhw' or 'cho'), set when
  /// arriving via the dedicated /bhw/login or /cho/login routes. Null for
  /// the generic /login route, which accepts any verified role as before.
  final String? expectedRole;

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
    String? routeName,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    if (routeName != null) {
      Get.offAllNamed(routeName, arguments: arguments);
      return;
    }
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

  /// Display label for the portal this login entry point is for, empty for
  /// the generic /login route.
  String get _portalName => switch (widget.expectedRole) {
    'bhw' => 'BHW',
    'cho' => 'CHO',
    _ => '',
  };

  /// Whether the verified role belongs to the portal the user entered
  /// through. CHO Super Admin accounts count as CHO. Always true when this
  /// page has no expected role (the generic /login route).
  bool _matchesExpectedPortal(String role) {
    return switch (widget.expectedRole) {
      'bhw' => _isBhwRole(role),
      'cho' => _isChoRole(role) || _isChoSuperAdminRole(role),
      _ => true,
    };
  }

  bool _isChoOrBhwRole(String role) {
    return _isChoRole(role) ||
        _isBhwRole(role) ||
        _isDoctorRole(role) ||
        _isChoSuperAdminRole(role);
  }

  Future<void> _navigateByRole(User user, String role) async {
    if (_isChoSuperAdminRole(role)) {
      _clearRoleValidationForDashboard();
      await _safeOffAll(
        const ChoSuperAdminCenter(),
        routeName: WebRoutes.choSuperAdmin,
      );
      return;
    }

    if (_isChoRole(role)) {
      _cacheRoleValidationForDashboard(user);
      await _safeOffAll(
        const cho.ChoDashboard(),
        arguments: {'roleValidated': true, 'uid': user.uid, 'role': 'cho'},
        routeName: WebRoutes.choDashboard,
      );
      return;
    }

    if (_isDoctorRole(role)) {
      _clearRoleValidationForDashboard();
      await _safeOffAll(
        const ReferralsPage(),
        routeName: WebRoutes.doctorReferrals,
      );
      return;
    }

    // BHW and other non-CHO roles should not access the CHO dashboard route.
    _clearRoleValidationForDashboard();
    await _safeOffAll(const HomePage(), routeName: WebRoutes.bhwDashboard);
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

    var message = isSuperAdmin
        ? 'Your CHO Super Admin account is verified. Continue to the governance center.'
        : isCho
        ? 'Your CHO account is verified. Continue to the CHO dashboard.'
        : isDoctor
        ? 'Your doctor account is verified. Continue to the referral center.'
        : 'Your account is verified. Continue to the dashboard.';
    if (!_matchesExpectedPortal(normalizedRole)) {
      message =
          'This account isn\'t registered with the $_portalName portal. '
          '$message';
    }

    final proceedToDashboard = await showLoginSuccessSweetAlert(
      context: context,
      title: 'Login successful',
      message: message,
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
      Map<String, dynamic>? cachedProfile;
      try {
        final cachedDocument = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 8));
        if (cachedDocument.exists) {
          cachedProfile = cachedDocument.data();
          final cachedRole = _normalizeRole(
            (cachedProfile?['role'] ?? '').toString(),
          );
          if (_isApprovedActiveProfile(cachedProfile) &&
              _isChoOrBhwRole(cachedRole)) {
            // The local Firestore cache is a valid degraded-mode source after
            // the user has already authenticated. A server check still runs
            // below when the cached profile is absent or not approved.
            return _RoleCheckResult.allowed(cachedRole);
          }
        }
      } catch (error) {
        if (kDebugMode) {
          print('Cached Firestore role verification failed: $error');
        }
      }

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
        // A non-approved cached profile must never grant access. If there is
        // no server response, report an unavailable verification rather than
        // silently turning a network problem into a denial or false approval.
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
                'Secure access to unified city and barangay health information.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: isCompact ? 15 : 20,
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'A trusted workspace for patient records, referrals, analytics, and community health operations.',
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
            // Static reference background: it never participates in layout
            // and never moves when the browser is resized or zoomed.
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth =
                      (constraints.maxWidth - (isWideScreen ? 64 : 40))
                          .clamp(280.0, 1200.0)
                          .toDouble();
                  final composition = SizedBox(
                    width: contentWidth,
                    child: isWideScreen
                        ? _buildWideScreenLayout(context)
                        : _buildMobileLayout(context),
                  );

                  // Desktop auth is intentionally one viewport tall.  A
                  // scale-down keeps the complete split composition visible
                  // at 720px laptop heights while preserving comfortable
                  // field sizes on larger screens. Mobile remains naturally
                  // scrollable for keyboard and browser chrome.
                  if (isWideScreen) {
                    return ClipRect(child: Center(child: composition));
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: composition,
                  );
                },
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
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

  // Login card widget
  Widget _buildLoginCard(BuildContext context, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 20 : 28),
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
              _portalName.isEmpty
                  ? 'Welcome back'
                  : '$_portalName Portal Login',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: isCompact ? 28 : 34,
                fontWeight: FontWeight.w800,
                color: _darkDeepTeal,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _portalName.isEmpty
                  ? 'Sign in to securely access the AI-DSUHIS platform.'
                  : 'Sign in with your $_portalName account to continue.',
              style: TextStyle(
                fontSize: 14,
                color: _mutedCoolGray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            _buildFieldLabel(context, 'Email address'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: emailController,
              hintText: 'you@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFieldLabel(context, 'Password'),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              pushAuthPage(context, const ForgotPassword()),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFieldLabel(context, 'Password'),
                      TextButton(
                        onPressed: () =>
                            pushAuthPage(context, const ForgotPassword()),
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
            _buildPasswordField(),
            const SizedBox(height: 22),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : signIn,
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
                        'Sign in',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFD8E2E4))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: _mutedCoolGray,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Color(0xFFD8E2E4))),
              ],
            ),
            const SizedBox(height: 14),
            _buildSocialButtonLarge(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata,
              color: const Color(0xFF4285F4),
              onTap: _isLoading ? null : signInWithGoogle,
            ),
            const SizedBox(height: 18),
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: _mutedCoolGray, fontSize: 13.5),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    TextSpan(
                      text: 'Create one',
                      style: const TextStyle(
                        color: _primaryAqua,
                        fontWeight: FontWeight.w800,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => pushAuthPage(
                          context,
                          const Signup(preselectedRole: 'CHO'),
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
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email, AutofillHints.username],
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) {
          if (!_isLoading) signIn();
        },
        style: TextStyle(
          color: _darkDeepTeal,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: 'Enter your password',
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB9C7C9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _darkDeepTeal,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
