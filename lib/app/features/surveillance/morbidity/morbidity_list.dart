import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity.dart';

/// Dedicated entry page for the full morbidity records list and its
/// management actions. Analytics navigation uses [MorbidityPage] directly
/// with analytics-only mode enabled.
class MorbidityListPage extends StatelessWidget {
  const MorbidityListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MorbidityPage(analyticsOnly: false, listOnly: true);
  }
}
