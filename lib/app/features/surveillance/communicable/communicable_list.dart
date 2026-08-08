import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/surveillance/communicable/communicable.dart';

/// Dedicated records-list entry point for communicable disease cases.
class CommunicableListPage extends StatelessWidget {
  const CommunicableListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommunicablePage(listOnly: true);
  }
}
