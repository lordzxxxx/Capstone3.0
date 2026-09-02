/// Shared permission vocabulary used by the CHO access center and route UX.
///
/// Firestore rules and callable functions remain the security boundary. This
/// catalog keeps the browser's controls aligned with those server-checked
/// capabilities and prevents free-form permission strings in the UI.
class RbacPermissionDefinition {
  final String key;
  final String label;
  final String group;

  const RbacPermissionDefinition({
    required this.key,
    required this.label,
    required this.group,
  });

  factory RbacPermissionDefinition.fromMap(Map<Object?, Object?> map) {
    return RbacPermissionDefinition(
      key: (map['key'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      group: (map['group'] ?? 'Other').toString(),
    );
  }
}

class RbacRoleDefinition {
  final String roleKey;
  final String name;
  final String description;
  final String baseRole;
  final List<String> permissions;
  final bool isSystem;
  final bool isProtected;
  final bool active;
  final int assignedUsers;

  const RbacRoleDefinition({
    required this.roleKey,
    required this.name,
    required this.description,
    required this.baseRole,
    required this.permissions,
    required this.isSystem,
    required this.isProtected,
    required this.active,
    this.assignedUsers = 0,
  });

  factory RbacRoleDefinition.fromMap(Map<Object?, Object?> map) {
    final rawPermissions = map['permissions'];
    return RbacRoleDefinition(
      roleKey: (map['roleKey'] ?? '').toString().trim().toUpperCase(),
      name: (map['name'] ?? map['roleKey'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      baseRole: (map['baseRole'] ?? '').toString().trim().toUpperCase(),
      permissions: rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toList()
          : const <String>[],
      isSystem: map['isSystem'] == true,
      isProtected: map['protected'] == true,
      active: map['active'] != false,
      assignedUsers: int.tryParse((map['assignedUsers'] ?? 0).toString()) ?? 0,
    );
  }

  bool hasPermission(String permission) => permissions.contains(permission);
}

class RbacRoleCatalog {
  final List<RbacRoleDefinition> roles;
  final List<RbacPermissionDefinition> permissions;

  const RbacRoleCatalog({required this.roles, required this.permissions});

  factory RbacRoleCatalog.fromMap(Map<Object?, Object?> map) {
    final rawRoles = map['roles'];
    final rawPermissions = map['permissions'];
    return RbacRoleCatalog(
      roles: rawRoles is List
          ? rawRoles
                .whereType<Map>()
                .map(
                  (role) => RbacRoleDefinition.fromMap(
                    Map<Object?, Object?>.from(role),
                  ),
                )
                .toList()
          : const <RbacRoleDefinition>[],
      permissions: rawPermissions is List
          ? rawPermissions
                .whereType<Map>()
                .map(
                  (permission) => RbacPermissionDefinition.fromMap(
                    Map<Object?, Object?>.from(permission),
                  ),
                )
                .toList()
          : RbacCatalog.permissions,
    );
  }
}

class RbacCatalog {
  static const List<RbacPermissionDefinition> permissions = [
    RbacPermissionDefinition(
      key: 'dashboard.view',
      label: 'View dashboard',
      group: 'Portal',
    ),
    RbacPermissionDefinition(
      key: 'patients.view',
      label: 'View patients',
      group: 'Patients',
    ),
    RbacPermissionDefinition(
      key: 'patients.create',
      label: 'Register patients',
      group: 'Patients',
    ),
    RbacPermissionDefinition(
      key: 'patients.edit',
      label: 'Edit patient records',
      group: 'Patients',
    ),
    RbacPermissionDefinition(
      key: 'checkups.view',
      label: 'View check-ups',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'checkups.create',
      label: 'Record check-ups',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'checkups.edit',
      label: 'Edit check-ups',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'prenatal.view',
      label: 'View prenatal records',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'prenatal.create',
      label: 'Record prenatal visits',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'prenatal.edit',
      label: 'Edit prenatal records',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'immunization.view',
      label: 'View immunization records',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'immunization.create',
      label: 'Record immunizations',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'immunization.edit',
      label: 'Edit immunization records',
      group: 'Clinical records',
    ),
    RbacPermissionDefinition(
      key: 'surveillance.view',
      label: 'View disease surveillance',
      group: 'Surveillance',
    ),
    RbacPermissionDefinition(
      key: 'surveillance.create',
      label: 'Record surveillance data',
      group: 'Surveillance',
    ),
    RbacPermissionDefinition(
      key: 'surveillance.edit',
      label: 'Edit surveillance data',
      group: 'Surveillance',
    ),
    RbacPermissionDefinition(
      key: 'referrals.view',
      label: 'View referrals',
      group: 'Referrals',
    ),
    RbacPermissionDefinition(
      key: 'referrals.assigned.view',
      label: 'View assigned doctor referrals',
      group: 'Referrals',
    ),
    RbacPermissionDefinition(
      key: 'referrals.create',
      label: 'Submit referrals',
      group: 'Referrals',
    ),
    RbacPermissionDefinition(
      key: 'referrals.status.update',
      label: 'Update referral follow-up status',
      group: 'Referrals',
    ),
    RbacPermissionDefinition(
      key: 'referrals.reassign',
      label: 'Reassign referrals',
      group: 'Referrals',
    ),
    RbacPermissionDefinition(
      key: 'immunization.vaccine_master.view',
      label: 'View vaccine master',
      group: 'Immunization',
    ),
    RbacPermissionDefinition(
      key: 'reports.view',
      label: 'View reports and analytics',
      group: 'Reports',
    ),
    RbacPermissionDefinition(
      key: 'reports.export',
      label: 'Export reports',
      group: 'Reports',
    ),
    RbacPermissionDefinition(
      key: 'bhw.requests.view',
      label: 'View BHW registrations',
      group: 'BHW management',
    ),
    RbacPermissionDefinition(
      key: 'bhw.approve',
      label: 'Approve BHW registrations',
      group: 'BHW management',
    ),
    RbacPermissionDefinition(
      key: 'bhw.reject',
      label: 'Reject BHW registrations',
      group: 'BHW management',
    ),
    RbacPermissionDefinition(
      key: 'bhw.access.manage',
      label: 'Enable or disable BHW access',
      group: 'BHW management',
    ),
    RbacPermissionDefinition(
      key: 'cho.users.view',
      label: 'View CHO users',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'cho.users.create',
      label: 'Create CHO and doctor accounts',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'cho.users.edit',
      label: 'Update CHO and doctor access',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'cho.users.disable',
      label: 'Enable or disable managed accounts',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'doctors.view',
      label: 'View doctors and workload',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'doctors.manage',
      label: 'Manage doctor eligibility',
      group: 'CHO access',
    ),
    RbacPermissionDefinition(
      key: 'rbac.view',
      label: 'View roles and permissions',
      group: 'RBAC',
    ),
    RbacPermissionDefinition(
      key: 'rbac.manage',
      label: 'Create and edit roles',
      group: 'RBAC',
    ),
    RbacPermissionDefinition(
      key: 'rbac.users.assign',
      label: 'Assign access roles',
      group: 'RBAC',
    ),
    RbacPermissionDefinition(
      key: 'data_quality.view',
      label: 'View data quality',
      group: 'Governance',
    ),
    RbacPermissionDefinition(
      key: 'audit.view',
      label: 'View audit logs',
      group: 'Governance',
    ),
    RbacPermissionDefinition(
      key: 'notifications.view',
      label: 'View notifications',
      group: 'Portal',
    ),
    RbacPermissionDefinition(
      key: 'profile.view',
      label: 'View profile',
      group: 'Portal',
    ),
  ];

  static const List<String> bhwPermissions = [
    'dashboard.view',
    'patients.view',
    'patients.create',
    'patients.edit',
    'checkups.view',
    'checkups.create',
    'checkups.edit',
    'prenatal.view',
    'prenatal.create',
    'prenatal.edit',
    'immunization.view',
    'immunization.create',
    'immunization.edit',
    'immunization.vaccine_master.view',
    'surveillance.view',
    'surveillance.create',
    'surveillance.edit',
    'referrals.view',
    'referrals.create',
    'referrals.status.update',
    'reports.view',
    'reports.export',
    'notifications.view',
    'profile.view',
  ];

  static const List<String> choPermissions = [
    'dashboard.view',
    'patients.view',
    'patients.create',
    'patients.edit',
    'checkups.view',
    'checkups.create',
    'checkups.edit',
    'prenatal.view',
    'prenatal.create',
    'prenatal.edit',
    'immunization.view',
    'immunization.create',
    'immunization.edit',
    'immunization.vaccine_master.view',
    'surveillance.view',
    'surveillance.create',
    'surveillance.edit',
    'referrals.view',
    'referrals.status.update',
    'reports.view',
    'reports.export',
    'data_quality.view',
    'audit.view',
    'notifications.view',
    'profile.view',
  ];

  static const List<String> doctorPermissions = [
    'dashboard.view',
    'patients.view',
    'checkups.view',
    'prenatal.view',
    'immunization.view',
    'surveillance.view',
    'referrals.view',
    'referrals.assigned.view',
    'notifications.view',
    'profile.view',
  ];

  static const Set<String> adminRoles = {'cho_admin', 'cho_super_admin'};

  static List<String> defaultPermissionsForRole(String role) {
    switch (role.trim().toLowerCase()) {
      case 'bhw':
        return bhwPermissions;
      case 'cho':
        return choPermissions;
      case 'doctor':
        return doctorPermissions;
      default:
        return const <String>[];
    }
  }

  static bool hasPermission({
    required String role,
    required String accessRoleKey,
    required Iterable<String> assignedPermissions,
    required String permission,
  }) {
    if (adminRoles.contains(role.trim().toLowerCase())) return true;
    final assigned = assignedPermissions.toSet();
    if (accessRoleKey.trim().toUpperCase().startsWith('CUSTOM_')) {
      return assigned.contains(permission);
    }
    return assigned.isEmpty
        ? defaultPermissionsForRole(role).contains(permission)
        : assigned.contains(permission);
  }
}
