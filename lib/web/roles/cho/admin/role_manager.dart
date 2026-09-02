import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/cho/admin/cho_rbac_center.dart';

/// Dedicated CHO access route. BHW approvals remain in the separate BHW
/// Management destination.
class RoleManager extends StatelessWidget {
  const RoleManager({super.key});

  @override
  Widget build(BuildContext context) => const ChoRbacCenter();
}
