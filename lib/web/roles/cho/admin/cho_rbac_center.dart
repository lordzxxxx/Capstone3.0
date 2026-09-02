import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/rbac_policy.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// CHO Access is deliberately separate from BHW Management. The latter owns
/// BHW registration and approval; this page owns the reusable user, role, and
/// permission model for managed CHO accounts.
class ChoRbacCenter extends StatefulWidget {
  const ChoRbacCenter({super.key});

  @override
  State<ChoRbacCenter> createState() => _ChoRbacCenterState();
}

class _ChoRbacCenterState extends State<ChoRbacCenter> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final AccountPolicyService _accountPolicy = AccountPolicyService.instance;
  RbacRoleCatalog _catalog = RbacRoleCatalog(
    roles: const <RbacRoleDefinition>[],
    permissions: RbacCatalog.permissions,
  );
  bool _loadingRoles = true;
  int _tabIndex = 0;

  static const Set<String> _choAccountRoles = <String>{
    'CHO',
    'CHO_ADMIN',
    'CHO_SUPER_ADMIN',
    'SUPER_ADMIN',
    'ADMIN',
  };

  bool _isChoAccountRole(Object? value) {
    return _choAccountRoles.contains(value.toString().trim().toUpperCase());
  }

  bool _isManagedAccountRole(Object? value) {
    final role = value.toString().trim().toUpperCase();
    return _isChoAccountRole(role) || role == 'DOCTOR' || role == 'BHW';
  }

  bool _isProtectedAdminRole(String role) {
    return RbacCatalog.adminRoles.contains(role.trim().toLowerCase());
  }

  bool _isChoAccessRole(RbacRoleDefinition role) {
    return role.active &&
        (role.baseRole == 'CHO' ||
            RbacCatalog.adminRoles.contains(role.roleKey.toLowerCase()));
  }

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final catalog = await _accountPolicy.listAccessRoles();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loadingRoles = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
      Get.snackbar(
        'Access roles unavailable',
        'The role catalog could not be loaded. Please try again.',
        backgroundColor: ChoColors.aqua,
        colorText: Colors.white,
      );
    }
  }

  List<RbacRoleDefinition> _rolesForBase(String role) {
    final normalized = role.trim().toUpperCase();
    return _catalog.roles
        .where((item) => item.baseRole == normalized && item.active)
        .toList();
  }

  Future<void> _showRoleEditor({RbacRoleDefinition? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    var baseRole = 'CHO';
    var selected = <String>{
      ...(existing?.permissions ??
          RbacCatalog.defaultPermissionsForRole(baseRole)),
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final grouped = <String, List<RbacPermissionDefinition>>{};
          for (final permission in _catalog.permissions) {
            grouped.putIfAbsent(permission.group, () => []).add(permission);
          }
          final allowed = RbacCatalog.defaultPermissionsForRole(
            baseRole,
          ).toSet();
          return AlertDialog(
            backgroundColor: AppColors.surfaceLight,
            title: Text(
              existing == null ? 'Create access role' : 'Edit access role',
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Role name'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: baseRole,
                      decoration: const InputDecoration(labelText: 'Base role'),
                      items: const ['CHO']
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(),
                      onChanged: existing != null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                baseRole = value;
                                selected = selected.intersection(
                                  RbacCatalog.defaultPermissionsForRole(
                                    value,
                                  ).toSet(),
                                );
                              });
                            },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Permissions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Only capabilities supported by the selected base role can be assigned.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...grouped.entries.map(
                      (entry) => Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: 0,
                              children: entry.value.map((permission) {
                                final enabled = allowed.contains(
                                  permission.key,
                                );
                                return SizedBox(
                                  width: 300,
                                  child: CheckboxListTile(
                                    dense: true,
                                    value:
                                        enabled &&
                                        selected.contains(permission.key),
                                    onChanged: enabled
                                        ? (value) {
                                            setDialogState(() {
                                              if (value == true) {
                                                selected.add(permission.key);
                                              } else {
                                                selected.remove(permission.key);
                                              }
                                            });
                                          }
                                        : null,
                                    title: Text(permission.label),
                                    subtitle: Text(permission.key),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.length < 2) {
                    Get.snackbar(
                      'Role name required',
                      'Enter a role name first.',
                    );
                    return;
                  }
                  try {
                    await _accountPolicy.saveAccessRole(
                      roleKey: existing?.roleKey,
                      name: name,
                      description: descriptionController.text,
                      baseRole: baseRole,
                      permissions: selected.toList(),
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    await _loadRoles();
                    Get.snackbar(
                      'Saved',
                      'The access role and its permissions were saved.',
                      backgroundColor: ChoColors.aqua,
                      colorText: Colors.white,
                    );
                  } catch (error) {
                    Get.snackbar(
                      'Could not save role',
                      error.toString(),
                      backgroundColor: ChoColors.aqua,
                      colorText: Colors.white,
                    );
                  }
                },
                child: Text(existing == null ? 'Create role' : 'Save changes'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _deleteRole(RbacRoleDefinition role) async {
    if (role.isProtected || role.assignedUsers > 0) return;
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete access role?'),
        content: Text('Delete “${role.name}”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _accountPolicy.deleteAccessRole(role.roleKey);
      await _loadRoles();
      Get.snackbar('Deleted', 'The access role was removed.');
    } catch (error) {
      Get.snackbar('Could not delete role', error.toString());
    }
  }

  Future<void> _assignRole(
    QueryDocumentSnapshot<Map<String, dynamic>> user,
    RbacRoleDefinition role,
  ) async {
    final data = user.data();
    final baseRole = role.baseRole;
    if (!_isChoAccountRole(data['role']) || baseRole != 'CHO') return;
    if (_isProtectedAdminRole((data['role'] ?? '').toString())) {
      return;
    }
    try {
      await _accountPolicy.updateChoAccount(
        uid: user.id,
        role: baseRole,
        accessRoleKey: role.roleKey,
      );
      Get.snackbar(
        'Access updated',
        '${data['email'] ?? 'User'} now uses ${role.name}.',
        backgroundColor: ChoColors.aqua,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar('Could not update access', error.toString());
    }
  }

  Future<void> _toggleChoAccountStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> user,
  ) async {
    final data = user.data();
    final currentRole = (data['role'] ?? '').toString().trim().toUpperCase();
    if (!_isChoAccountRole(currentRole) || _isProtectedAdminRole(currentRole)) {
      return;
    }
    final currentStatus = (data['accountStatus'] ?? 'active')
        .toString()
        .trim()
        .toLowerCase();
    final nextStatus = currentStatus == 'disabled' ? 'active' : 'disabled';
    try {
      await _accountPolicy.updateChoAccount(
        uid: user.id,
        role: 'CHO',
        accountStatus: nextStatus,
        accessRoleKey: (data['accessRoleKey'] ?? 'CHO').toString(),
      );
      Get.snackbar(
        nextStatus == 'active' ? 'Account enabled' : 'Account disabled',
        '${data['email'] ?? 'The CHO account'} is now $nextStatus.',
        backgroundColor: ChoColors.aqua,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar('Could not update account status', error.toString());
    }
  }

  RbacRoleDefinition? _roleForUser({
    required String baseRole,
    required String accessRoleKey,
  }) {
    for (final role in _catalog.roles) {
      if (role.active && role.roleKey == accessRoleKey) return role;
    }
    for (final role in _rolesForBase(baseRole)) {
      if (role.roleKey == accessRoleKey) return role;
    }
    return null;
  }

  List<RbacPermissionDefinition> _permissionsForUser({
    required String baseRole,
    required RbacRoleDefinition? role,
  }) {
    final keys = role == null
        ? RbacCatalog.defaultPermissionsForRole(baseRole)
        : role.permissions;
    final catalog = <String, RbacPermissionDefinition>{
      for (final permission in RbacCatalog.permissions)
        permission.key: permission,
      for (final permission in _catalog.permissions) permission.key: permission,
    };
    return [
      for (final key in keys)
        if (catalog[key] != null) catalog[key]!,
    ];
  }

  Future<void> _showUserAccessDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> user,
  ) async {
    final data = user.data();
    final baseRole = (data['role'] ?? 'CHO').toString().trim().toUpperCase();
    final accessRoleKey = (data['accessRoleKey'] ?? baseRole)
        .toString()
        .trim()
        .toUpperCase();
    final role = _roleForUser(baseRole: baseRole, accessRoleKey: accessRoleKey);
    final permissions = _permissionsForUser(baseRole: baseRole, role: role);
    final grouped = <String, List<RbacPermissionDefinition>>{};
    for (final permission in permissions) {
      grouped.putIfAbsent(permission.group, () => []).add(permission);
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('CHO access permissions'),
        content: SizedBox(
          width: 620,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AccessLabel(
                    label: 'User',
                    value:
                        (data['fullName'] ?? data['username'] ?? 'Unnamed user')
                            .toString(),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    (data['email'] ?? 'No email').toString(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _AccessLabel(
                    label: 'Access role',
                    value:
                        role?.name ??
                        (_isProtectedAdminRole(baseRole)
                            ? 'Protected CHO Admin'
                            : accessRoleKey),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '${permissions.length} permissions',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (grouped.isEmpty)
                    const Text(
                      'No permissions are assigned to this account.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    ...grouped.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: entry.value
                                  .map(
                                    (permission) =>
                                        Chip(label: Text(permission.label)),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateAccountDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    var accessRoleKey = 'CHO';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          const baseRole = 'CHO';
          final compatible = _rolesForBase(baseRole);
          if (!compatible.any((role) => role.roleKey == accessRoleKey)) {
            accessRoleKey = baseRole;
          }
          return AlertDialog(
            title: const Text('Create CHO account'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Registered email',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        compatible.any((role) => role.roleKey == accessRoleKey)
                        ? accessRoleKey
                        : null,
                    decoration: const InputDecoration(labelText: 'Access role'),
                    items: compatible
                        .map(
                          (role) => DropdownMenuItem(
                            value: role.roleKey,
                            child: Text(role.name),
                          ),
                        )
                        .toList(),
                    onChanged: compatible.isEmpty
                        ? null
                        : (value) => setDialogState(
                            () => accessRoleKey = value ?? accessRoleKey,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'CHO accounts are created by the CHO Admin. The secure onboarding email is sent automatically after the account and access role are saved.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'No permanent password or manual email step is required.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty ||
                      emailController.text.trim().isEmpty) {
                    Get.snackbar(
                      'Incomplete',
                      'Full name and email are required.',
                    );
                    return;
                  }
                  try {
                    final result = await _accountPolicy.createChoAccount(
                      fullName: nameController.text,
                      email: emailController.text,
                      role: 'CHO',
                      accessRoleKey: accessRoleKey,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    Get.snackbar(
                      result.activationEmailSent
                          ? 'Account created'
                          : 'Account created; email pending',
                      result.activationEmailSent
                          ? 'The secure onboarding email was sent automatically.'
                          : 'The account was saved, but the system mailer needs configuration.',
                      backgroundColor: ChoColors.aqua,
                      colorText: Colors.white,
                    );
                  } catch (error) {
                    Get.snackbar('Could not create account', error.toString());
                  }
                },
                child: const Text('Create account'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    emailController.dispose();
  }

  Widget _buildUsers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ChoErrorState(
            message: 'User access data could not be loaded.',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) return const ChoLoadingSkeleton();
        final docs =
            snapshot.data!.docs
                .where((doc) => _isManagedAccountRole(doc.data()['role']))
                .toList()
              ..sort(
                (a, b) => (a.data()['email'] ?? '').toString().compareTo(
                  (b.data()['email'] ?? '').toString(),
                ),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Managed accounts',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showCreateAccountDialog,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Create account'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'CHO roles and permissions are managed here. Existing doctor and BHW accounts remain visible for continuity; their operational workflows stay in Referrals and BHW Management.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (docs.isEmpty)
              const ChoEmptyState(
                title: 'No managed accounts found',
                message:
                    'Create a CHO account or open the dedicated BHW/doctor workflow.',
              )
            else
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    return Column(
                      children: [
                        if (wide) const _AccessTableHeader(),
                        for (var index = 0; index < docs.length; index++)
                          _buildUserRow(
                            docs[index],
                            wide: wide,
                            showDivider: index < docs.length - 1,
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUserRow(
    QueryDocumentSnapshot<Map<String, dynamic>> user, {
    required bool wide,
    required bool showDivider,
  }) {
    final data = user.data();
    final baseRole = (data['role'] ?? '').toString().trim().toUpperCase();
    final currentKey = (data['accessRoleKey'] ?? baseRole)
        .toString()
        .toUpperCase();
    final isProtected = _isProtectedAdminRole(baseRole);
    final options = _rolesForBase(baseRole);
    final selected = options.any((role) => role.roleKey == currentKey)
        ? currentKey
        : (options.any((role) => role.roleKey == baseRole) ? baseRole : null);
    final role = _roleForUser(
      baseRole: baseRole,
      accessRoleKey: selected ?? currentKey,
    );
    final permissionCount = _permissionsForUser(
      baseRole: baseRole,
      role: role,
    ).length;
    final identity = _AccessIdentity(
      name: (data['fullName'] ?? data['username'] ?? 'Unnamed user').toString(),
      email: (data['email'] ?? 'No email').toString(),
    );
    final canEditAccess =
        baseRole == 'CHO' && !isProtected && options.isNotEmpty;
    final accessField = SizedBox(
      width: wide ? null : double.infinity,
      child: isProtected
          ? const _AccessLabel(label: 'Access role', value: 'Protected admin')
          : canEditAccess
          ? DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Access role'),
              items: options
                  .map(
                    (role) => DropdownMenuItem(
                      value: role.roleKey,
                      child: Text(role.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                final role = options.firstWhere(
                  (item) => item.roleKey == value,
                );
                _assignRole(user, role);
              },
            )
          : _AccessLabel(label: 'Access role', value: role?.name ?? currentKey),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: wide ? AppSpacing.sm : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: AppSpacing.md),
                const SizedBox(
                  width: 110,
                  child: _AccessHeaderLabel('Account role'),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 260, child: accessField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 125,
                  child: TextButton.icon(
                    onPressed: () => _showUserAccessDialog(user),
                    icon: const Icon(Icons.list_alt_outlined, size: 16),
                    label: Text('$permissionCount access'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 90,
                  child: _AccessLabel(
                    label: 'Status',
                    value: (data['accountStatus'] ?? 'active').toString(),
                  ),
                ),
                if (baseRole == 'CHO')
                  IconButton(
                    tooltip: isProtected
                        ? 'Protected account'
                        : (data['accountStatus'] ?? 'active').toString() ==
                              'disabled'
                        ? 'Enable CHO account'
                        : 'Disable CHO account',
                    onPressed: isProtected
                        ? null
                        : () => _toggleChoAccountStatus(user),
                    icon: Icon(
                      (data['accountStatus'] ?? 'active').toString() ==
                              'disabled'
                          ? Icons.lock_open_outlined
                          : Icons.block_outlined,
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: AppSpacing.md),
                    _AccessLabel(
                      label: 'Status',
                      value: (data['accountStatus'] ?? 'active').toString(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _AccessLabel(
                        label: 'Account role',
                        value: baseRole,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: accessField),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _showUserAccessDialog(user),
                      icon: const Icon(Icons.list_alt_outlined, size: 16),
                      label: Text('View access ($permissionCount)'),
                    ),
                    const Spacer(),
                    if (baseRole == 'CHO')
                      IconButton(
                        tooltip: isProtected
                            ? 'Protected account'
                            : (data['accountStatus'] ?? 'active').toString() ==
                                  'disabled'
                            ? 'Enable CHO account'
                            : 'Disable CHO account',
                        onPressed: isProtected
                            ? null
                            : () => _toggleChoAccountStatus(user),
                        icon: Icon(
                          (data['accountStatus'] ?? 'active').toString() ==
                                  'disabled'
                              ? Icons.lock_open_outlined
                              : Icons.block_outlined,
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildRoles() {
    if (_loadingRoles) return const ChoLoadingSkeleton();
    final roles = _catalog.roles.where(_isChoAccessRole).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Roles and permissions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showRoleEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Create role'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Only CHO roles are managed here. Each role is a named set of portal permissions that can be assigned to CHO users; protected administrator roles remain locked.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        ...roles.map(
          (role) => Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        role.description,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${role.baseRole} • ${role.permissions.length} permissions • ${role.assignedUsers} assigned user${role.assignedUsers == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (role.isProtected)
                  const Chip(label: Text('Protected'))
                else ...[
                  IconButton(
                    tooltip: 'Edit role',
                    onPressed: () => _showRoleEditor(existing: role),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: role.assignedUsers > 0
                        ? 'Reassign users first'
                        : 'Delete role',
                    onPressed: role.assignedUsers > 0
                        ? null
                        : () => _deleteRole(role),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChoColors.background,
      body: WebResponsiveBody(
        sidebar: const ChoNavigationDrawer(
          current: ChoDestination.manageChoAccess,
        ),
        title: 'Manage CHO Access',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage CHO Access',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Control users, roles, and permissions from one secure access center.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Users'),
                    icon: Icon(Icons.people_outline),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Roles & permissions'),
                    icon: Icon(Icons.rule_outlined),
                  ),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (selection) {
                  setState(() => _tabIndex = selection.first);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _tabIndex == 0 ? _buildUsers() : _buildRoles(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessLabel extends StatelessWidget {
  const _AccessLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _AccessIdentity extends StatelessWidget {
  const _AccessIdentity({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AccessTableHeader extends StatelessWidget {
  const _AccessTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.surfaceSubtle,
      child: const Row(
        children: [
          Expanded(flex: 5, child: _AccessHeaderLabel('User')),
          SizedBox(width: AppSpacing.md),
          SizedBox(width: 110, child: _AccessHeaderLabel('Account role')),
          SizedBox(width: AppSpacing.md),
          SizedBox(width: 260, child: _AccessHeaderLabel('Access role')),
          SizedBox(width: AppSpacing.md),
          SizedBox(width: 125, child: _AccessHeaderLabel('Permissions')),
          SizedBox(width: AppSpacing.sm),
          SizedBox(width: 90, child: _AccessHeaderLabel('Status')),
          SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _AccessHeaderLabel extends StatelessWidget {
  const _AccessHeaderLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
