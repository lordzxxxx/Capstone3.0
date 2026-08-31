import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/cho/admin/cho_super_admin_center.dart';

/// Legacy route kept as a compatibility alias. All governance writes now go
/// through the CHO Admin center and its server-side callable functions.
class RoleManager extends StatelessWidget {
  const RoleManager({super.key});

  @override
  Widget build(BuildContext context) => const ChoSuperAdminCenter();
}
