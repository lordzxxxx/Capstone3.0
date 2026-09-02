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
/// registration approval; this page owns the reusable user/role/permission
/// model used by managed CHO, doctor, and BHW access.
class ChoRbacCenter extends StatefulWidget {
  const ChoRbacCenter({super.key, this.initialTab = 0, this.focusBaseRole});

  final int initialTab;
  final String? focusBaseRole;

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

  String? get _focusedBaseRole {
    final value = widget.focusBaseRole?.trim().toUpperCase();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab.clamp(0, 1).toInt();
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
    var baseRole = existing?.baseRole ?? 'BHW';
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
                      items: const ['BHW', 'CHO', 'DOCTOR']
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
    if ([
      'CHO_ADMIN',
      'CHO_SUPER_ADMIN',
      'SUPER_ADMIN',
      'ADMIN',
    ].contains((data['role'] ?? '').toString().toUpperCase())) {
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

  Future<void> _showCreateAccountDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    var baseRole = 'CHO';
    var accessRoleKey = 'CHO';
    var availability = 'available';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final compatible = _rolesForBase(baseRole);
          if (!compatible.any((role) => role.roleKey == accessRoleKey)) {
            accessRoleKey = baseRole;
          }
          return AlertDialog(
            title: const Text('Create CHO or doctor account'),
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
                    initialValue: baseRole,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                    ),
                    items: const ['CHO', 'DOCTOR']
                        .map(
                          (role) =>
                              DropdownMenuItem(value: role, child: Text(role)),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      baseRole = value ?? baseRole;
                      accessRoleKey = baseRole;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: accessRoleKey,
                    decoration: const InputDecoration(labelText: 'Access role'),
                    items: compatible
                        .map(
                          (role) => DropdownMenuItem(
                            value: role.roleKey,
                            child: Text(role.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => accessRoleKey = value ?? accessRoleKey,
                    ),
                  ),
                  if (baseRole == 'DOCTOR') ...[
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: availability,
                      decoration: const InputDecoration(
                        labelText: 'Assignment availability',
                      ),
                      items:
                          const ['available', 'busy', 'limited', 'unavailable']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                      onChanged: (value) => setDialogState(
                        () => availability = value ?? availability,
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
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.medical_services_outlined,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Doctor access: the account receives a secure activation email automatically. After setting a password, the doctor signs in through AI-DSUHIS and sees only referrals assigned to that account.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'The onboarding email is sent automatically after the account is saved. No permanent password or manual email step is required.',
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
                      role: baseRole,
                      availability: availability,
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
        final docs = [...snapshot.data!.docs]
          ..sort(
            (a, b) => (a.data()['email'] ?? '').toString().compareTo(
              (b.data()['email'] ?? '').toString(),
            ),
          );
        final visibleDocs = _focusedBaseRole == null
            ? docs
            : docs
                  .where((doc) {
                    return (doc.data()['role'] ?? '')
                            .toString()
                            .trim()
                            .toUpperCase() ==
                        _focusedBaseRole;
                  })
                  .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Users and access',
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
              'Assign a controlled access role to CHO, doctor, and approved BHW accounts. Core administrator accounts are protected.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
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
                      for (var index = 0; index < visibleDocs.length; index++)
                        _buildUserRow(
                          visibleDocs[index],
                          wide: wide,
                          showDivider: index < visibleDocs.length - 1,
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
    final isProtected = [
      'CHO_ADMIN',
      'CHO_SUPER_ADMIN',
      'SUPER_ADMIN',
      'ADMIN',
    ].contains(baseRole);
    final options = _rolesForBase(baseRole);
    final selected = options.any((role) => role.roleKey == currentKey)
        ? currentKey
        : (options.any((role) => role.roleKey == baseRole) ? baseRole : null);
    final identity = _AccessIdentity(
      name: (data['fullName'] ?? data['username'] ?? 'Unnamed user').toString(),
      email: (data['email'] ?? 'No email').toString(),
    );
    final accessField = SizedBox(
      width: wide ? null : double.infinity,
      child: isProtected
          ? const _AccessLabel(label: 'Access role', value: 'Protected admin')
          : DropdownButtonFormField<String>(
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
            ),
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
                  child: _AccessHeaderLabel('Base role'),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 260, child: accessField),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: 110,
                  child: _AccessLabel(
                    label: 'Status',
                    value: (data['accountStatus'] ?? 'active').toString(),
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
                      child: _AccessLabel(label: 'Base role', value: baseRole),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: accessField),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildRoles() {
    if (_loadingRoles) return const ChoLoadingSkeleton();
    final roles =
        _catalog.roles
            .where(
              (role) =>
                  _focusedBaseRole == null || role.baseRole == _focusedBaseRole,
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _focusedBaseRole == 'BHW'
                    ? 'BHW access and permissions'
                    : 'Roles and permissions',
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
        Text(
          _focusedBaseRole == 'BHW'
              ? 'BHW access is limited to approved, active accounts and their assigned barangay records. Only CHO Admin can change this access model.'
              : 'Permissions come from the actual portal modules and actions. Core roles cannot be edited or deleted, and custom roles cannot grant administrator capabilities.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (_focusedBaseRole == 'BHW') ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.primary, size: 18),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'BHW users cannot approve registrations, manage roles, or grant CHO access. Those capabilities remain in CHO Admin-only workflows.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        sidebar: ChoNavigationDrawer(
          current: _focusedBaseRole == 'BHW'
              ? ChoDestination.bhwAccess
              : ChoDestination.manageChoAccess,
        ),
        title: _focusedBaseRole == 'BHW'
            ? 'BHW Access & Permissions'
            : 'Manage CHO Access',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _focusedBaseRole == 'BHW'
                    ? 'BHW Access & Permissions'
                    : 'Manage CHO Access',
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
          SizedBox(width: 110, child: _AccessHeaderLabel('Base role')),
          SizedBox(width: AppSpacing.md),
          SizedBox(width: 260, child: _AccessHeaderLabel('Access role')),
          SizedBox(width: AppSpacing.lg),
          SizedBox(width: 110, child: _AccessHeaderLabel('Status')),
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
