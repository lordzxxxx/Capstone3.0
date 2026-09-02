import 'package:mycapstone_project/web/shared/services/rbac_policy.dart';

class UserAccessScope {
  final String userId;
  final String role;
  final String barangay;
  final String barangayCode;
  final String barangayDistrict;
  final DateTime? dataVisibleFrom;
  final String accessRoleKey;
  final List<String> permissions;

  const UserAccessScope({
    required this.userId,
    required this.role,
    required this.barangay,
    required this.barangayCode,
    required this.barangayDistrict,
    required this.dataVisibleFrom,
    this.accessRoleKey = '',
    this.permissions = const <String>[],
  });

  bool get isAuthenticated => userId.isNotEmpty;

  bool get canViewAllBarangays {
    return role == 'cho' || role == 'cho_admin' || role == 'cho_super_admin';
  }

  bool get isBhw => role == 'bhw';

  bool get isChoAdmin => role == 'cho_admin' || role == 'cho_super_admin';

  bool get hasVisibilityBoundary => dataVisibleFrom != null;

  bool hasPermission(String permission) {
    return RbacCatalog.hasPermission(
      role: role,
      accessRoleKey: accessRoleKey,
      assignedPermissions: permissions,
      permission: permission,
    );
  }

  static const UserAccessScope unauthenticated = UserAccessScope(
    userId: '',
    role: '',
    barangay: '',
    barangayCode: '',
    barangayDistrict: '',
    dataVisibleFrom: null,
    accessRoleKey: '',
    permissions: <String>[],
  );
}
