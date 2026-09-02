import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/barangay_workspace_service.dart';
import 'package:mycapstone_project/web/shared/services/firestore_rest_reader.dart';
import 'package:mycapstone_project/web/shared/services/rbac_policy.dart';

class UserAccessScopeService {
  UserAccessScopeService._();

  static final UserAccessScopeService instance = UserAccessScopeService._();

  FirebaseFirestore get _firestore => getFirestoreInstance();
  UserAccessScope? _cachedScope;

  void clearCachedScope({String? userId}) {
    if (userId == null || _cachedScope?.userId == userId) {
      _cachedScope = null;
    }
  }

  DateTime? _coerceDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }

  UserAccessScope _buildScope(String userId, Map<String, dynamic> data) {
    return UserAccessScope(
      userId: userId,
      role: (data['role'] ?? '').toString().trim().toLowerCase(),
      barangay: (data['barangay'] ?? '').toString().trim(),
      barangayCode: BarangayFirestorePaths.normalizeBarangayCode(
        (data['barangayCode'] ?? '').toString().trim(),
      ),
      barangayDistrict: (data['barangayDistrict'] ?? '').toString().trim(),
      dataVisibleFrom: _coerceDate(
        data['dataVisibilityStartAt'] ?? data['createdAt'],
      ),
      accessRoleKey: (data['accessRoleKey'] ?? data['role'] ?? '')
          .toString()
          .trim()
          .toUpperCase(),
      permissions: data['permissions'] is List
          ? (data['permissions'] as List)
                .map((permission) => permission.toString())
                .where(
                  (permission) => RbacCatalog.permissions.any(
                    (definition) => definition.key == permission,
                  ),
                )
                .toList()
          : const <String>[],
    );
  }

  bool _hasResolvedRole(Map<String, dynamic> data) {
    return (data['role'] ?? '').toString().trim().isNotEmpty;
  }

  bool _hasApprovedActiveProfile(Map<String, dynamic> data) {
    final approval = (data['approvalStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final status = (data['accountStatus'] ?? data['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return approval == 'approved' &&
        (status == 'active' || status == 'approved');
  }

  String _normalizedRoleValue(Object? value) =>
      value == null ? '' : value.toString().trim().toLowerCase();

  String _defaultAccessScopeForRole(String role) =>
      _normalizedRoleValue(role) == 'bhw' ? 'barangay' : 'citywide';

  bool _isBarangayScopedRole(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    return role == 'bhw';
  }

  bool _hasResolvedScope(Map<String, dynamic> data) {
    if (!_hasResolvedRole(data) || !_hasApprovedActiveProfile(data)) {
      return false;
    }

    if (!_isBarangayScopedRole(data)) {
      return true;
    }

    final barangay = (data['barangay'] ?? '').toString().trim();
    final barangayCode = (data['barangayCode'] ?? '').toString().trim();
    return barangay.isNotEmpty || barangayCode.isNotEmpty;
  }

  bool _isResolvedScope(UserAccessScope scope) {
    if (!scope.isAuthenticated) {
      return false;
    }
    if (scope.canViewAllBarangays) {
      return true;
    }
    if (!scope.isBhw) {
      return scope.role.isNotEmpty;
    }
    return scope.barangay.isNotEmpty || scope.barangayCode.isNotEmpty;
  }

  Future<void> _syncRootUserMirror(
    String userId,
    Map<String, dynamic> data, {
    String? email,
    String? emailLower,
    String? migratedFromDocId,
    String? migratedFromPath,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'uid': userId,
        'email': email ?? data['email'],
        'emailLower':
            emailLower ??
            (data['emailLower'] ??
                (email ?? data['email'] ?? '').toString().trim().toLowerCase()),
        'username': data['username'],
        'usernameLower': data['usernameLower'],
        'fullName': data['fullName'],
        'displayName': data['displayName'],
        'role': data['role'],
        'accessRoleKey': data['accessRoleKey'] ?? data['role'],
        'permissions':
            data['permissions'] ??
            RbacCatalog.defaultPermissionsForRole(
              (data['role'] ?? '').toString(),
            ),
        'accessScope':
            data['accessScope'] ??
            _defaultAccessScopeForRole((data['role'] ?? '').toString()),
        'organizationLevel':
            data['organizationLevel'] ??
            (_isBarangayScopedRole(data) ? 'barangay' : 'citywide'),
        'barangay': data['barangay'],
        'barangayCode': data['barangayCode'],
        'barangayDistrict': data['barangayDistrict'],
        'barangayPath': data['barangayPath'],
        'barangayUserPath': data['barangayUserPath'],
        'dataVisibilityStartAt': data['dataVisibilityStartAt'],
        'approvalStatus': data['approvalStatus'],
        'accountStatus': data['accountStatus'],
        'createdAt': data['createdAt'],
        if (migratedFromDocId != null) 'migratedFromDocId': migratedFromDocId,
        if (migratedFromPath != null) 'migratedFromPath': migratedFromPath,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Keep scope loading resilient even if the compatibility mirror fails.
    }
  }

  Future<Map<String, dynamic>?> _readUserDataByEmail(User user) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return null;

    try {
      final users = _firestore.collection('users');
      final normalizedEmail = email.toLowerCase();

      QuerySnapshot<Map<String, dynamic>> snapshot = await users
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        snapshot = await users.where('email', isEqualTo: email).limit(1).get();
      }

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final doc = snapshot.docs.first;
      final data = Map<String, dynamic>.from(doc.data());

      if (doc.id != user.uid) {
        await _syncRootUserMirror(
          user.uid,
          data,
          email: email,
          emailLower: normalizedEmail,
          migratedFromDocId: doc.id,
        );
      }

      return data;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readUserDataFromUsersGroup(User user) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collectionGroup(BarangayFirestorePaths.usersCollection)
          .where('uid', isEqualTo: user.uid)
          .limit(5)
          .get();

      if (snapshot.docs.isEmpty) {
        final email = user.email?.trim().toLowerCase();
        if (email != null && email.isNotEmpty) {
          snapshot = await _firestore
              .collectionGroup(BarangayFirestorePaths.usersCollection)
              .where('emailLower', isEqualTo: email)
              .limit(5)
              .get();
        }
      }

      if (snapshot.docs.isEmpty) {
        final email = user.email?.trim();
        if (email != null && email.isNotEmpty) {
          snapshot = await _firestore
              .collectionGroup(BarangayFirestorePaths.usersCollection)
              .where('email', isEqualTo: email)
              .limit(5)
              .get();
        }
      }

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final doc = snapshot.docs.firstWhere(
        (candidate) => _hasResolvedScope(candidate.data()),
        orElse: () => snapshot.docs.first,
      );
      final data = Map<String, dynamic>.from(doc.data());

      await _syncRootUserMirror(
        user.uid,
        data,
        email: user.email,
        emailLower: user.email?.trim().toLowerCase(),
        migratedFromPath: doc.reference.path,
      );

      return data;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readUserDataFromRealtimeDb(User user) async {
    try {
      final snapshot = await getRealtimeDatabaseInstance()
          .ref()
          .child('users')
          .child(user.uid)
          .get();
      if (!snapshot.exists || snapshot.value is! Map) {
        return null;
      }

      final raw = Map<Object?, Object?>.from(snapshot.value as Map);
      final data = raw.map((key, value) => MapEntry(key.toString(), value));
      final role = (data['role'] ?? '').toString().trim();
      if (role.isEmpty) {
        return null;
      }

      final email = (data['email'] ?? user.email ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final fullName =
          (data['fullName'] ?? data['displayName'] ?? data['username'] ?? '')
              .toString()
              .trim();
      final username = (data['username'] ?? data['displayName'] ?? fullName)
          .toString()
          .trim();

      return <String, dynamic>{
        'uid': user.uid,
        'email': email.isEmpty ? user.email : email,
        'emailLower': email,
        'username': username,
        'usernameLower': username.toLowerCase(),
        'fullName': fullName,
        'displayName': (data['displayName'] ?? fullName).toString().trim(),
        'role': role,
        'accessRoleKey': data['accessRoleKey'] ?? role,
        'permissions': data['permissions'] is List
            ? data['permissions']
            : RbacCatalog.defaultPermissionsForRole(role),
        'accessScope': (data['accessScope'] ?? _defaultAccessScopeForRole(role))
            .toString(),
        'organizationLevel': _normalizedRoleValue(role) == 'bhw'
            ? 'barangay'
            : 'citywide',
        'approvalStatus': data['approvalStatus'],
        'accountStatus': data['accountStatus'],
        'barangay': (data['barangay'] ?? '').toString().trim(),
        'barangayCode': (data['barangayCode'] ?? '').toString().trim(),
        'barangayDistrict': (data['barangayDistrict'] ?? '').toString().trim(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readUserDataFromClaims(User user) async {
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? const <String, dynamic>{};
      if ((claims['approvalStatus'] ?? '').toString().trim().toLowerCase() !=
              'approved' ||
          !['active', 'approved'].contains(
            (claims['accountStatus'] ?? '').toString().trim().toLowerCase(),
          )) {
        return null;
      }
      String role = (claims['role'] ?? '').toString().trim();
      if (role.isEmpty && claims['roles'] is List) {
        final roles = (claims['roles'] as List)
            .map((value) => value.toString().trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        if (roles.contains('cho_admin')) {
          role = 'CHO_ADMIN';
        } else if (roles.contains('cho_super_admin')) {
          role = 'CHO_SUPER_ADMIN';
        } else if (roles.contains('super_admin')) {
          role = 'SUPER_ADMIN';
        } else if (roles.contains('admin')) {
          role = 'ADMIN';
        } else if (roles.contains('cho')) {
          role = 'CHO';
        } else if (roles.contains('doctor')) {
          role = 'DOCTOR';
        } else if (roles.contains('bhw')) {
          role = 'BHW';
        }
      }

      if (role.isEmpty) {
        return null;
      }

      final email = user.email?.trim() ?? '';
      return <String, dynamic>{
        'uid': user.uid,
        'email': email,
        'emailLower': email.toLowerCase(),
        'role': role,
        'accessRoleKey': claims['accessRoleKey'] ?? role,
        'permissions': claims['permissions'] is List
            ? claims['permissions']
            : RbacCatalog.defaultPermissionsForRole(role),
        'accessScope': _defaultAccessScopeForRole(role),
        'organizationLevel': _normalizedRoleValue(role) == 'bhw'
            ? 'barangay'
            : 'citywide',
        'approvalStatus': claims['approvalStatus'],
        'accountStatus': claims['accountStatus'],
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureCurrentUserRootMirror() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    Map<String, dynamic> data = <String, dynamic>{};

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        data = userDoc.data() ?? <String, dynamic>{};
      }
    } catch (_) {}

    if (!_hasResolvedRole(data)) {
      final realtimeData = await _readUserDataFromRealtimeDb(user);
      if (realtimeData != null) {
        data = <String, dynamic>{...data, ...realtimeData};
      }
    }

    if (!_hasResolvedRole(data)) {
      final claimsData = await _readUserDataFromClaims(user);
      if (claimsData != null) {
        data = <String, dynamic>{...data, ...claimsData};
      }
    }

    if (!_hasResolvedRole(data)) {
      final fallbackData = await _readUserDataByEmail(user);
      if (fallbackData != null) {
        data = <String, dynamic>{...data, ...fallbackData};
      }
    }

    if (!_hasResolvedRole(data)) {
      final scopedData = await _readUserDataFromUsersGroup(user);
      if (scopedData != null) {
        data = <String, dynamic>{...data, ...scopedData};
      }
    }

    if (!_hasResolvedRole(data)) {
      return;
    }

    await _syncRootUserMirror(
      user.uid,
      data,
      email: user.email?.trim(),
      emailLower: user.email?.trim().toLowerCase(),
    );
  }

  Future<UserAccessScope> loadCurrentScope({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cachedScope = null;
      return UserAccessScope.unauthenticated;
    }

    final cachedScope = _cachedScope;
    if (!forceRefresh &&
        cachedScope != null &&
        cachedScope.userId == user.uid &&
        _isResolvedScope(cachedScope)) {
      return cachedScope;
    }

    Map<String, dynamic> data = <String, dynamic>{};

    // Read the Firestore SDK cache first on every platform. The web client
    // intentionally enables persistence, so a cached approved scope keeps
    // the shell usable during a brief outage. The REST reader remains a
    // network-only compatibility fallback for legacy profiles.
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 8));
      if (userDoc.exists) {
        data = userDoc.data() ?? <String, dynamic>{};
      }
    } catch (_) {}

    if (kIsWeb && !_hasResolvedScope(data)) {
      try {
        final userDoc = await const FirestoreRestReader().getDocument(
          'users',
          user.uid,
        );
        if (userDoc != null) {
          data = userDoc.data();
        }
      } catch (_) {}
    }

    if (!_hasResolvedScope(data)) {
      final fallbackData = await _readUserDataByEmail(user);
      if (fallbackData != null && _hasResolvedScope(fallbackData)) {
        data = fallbackData;
      }
    }

    if (!_hasResolvedScope(data)) {
      final realtimeData = await _readUserDataFromRealtimeDb(user);
      if (realtimeData != null) {
        data = realtimeData;
        await _syncRootUserMirror(
          user.uid,
          data,
          email: user.email,
          emailLower: user.email?.trim().toLowerCase(),
        );
      }
    }

    if (!_hasResolvedScope(data)) {
      final claimsData = await _readUserDataFromClaims(user);
      if (claimsData != null) {
        data = claimsData;
        await _syncRootUserMirror(
          user.uid,
          data,
          email: user.email,
          emailLower: user.email?.trim().toLowerCase(),
        );
      }
    }

    if (!_hasResolvedScope(data)) {
      final scopedData = await _readUserDataFromUsersGroup(user);
      if (scopedData != null) {
        data = scopedData;
      }
    }

    final scope = _buildScope(user.uid, data);
    if (_isResolvedScope(scope)) {
      _cachedScope = scope;
      if (scope.barangayCode.isNotEmpty) {
        try {
          await BarangayWorkspaceService.instance.ensureWorkspace(scope);
        } catch (_) {
          // Workspace bootstrapping is helpful but should never block login.
        }
      }
    }
    return scope;
  }
}
