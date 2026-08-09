import 'package:flutter/material.dart';

/// Prenatal page color constants
const Color primaryAqua = Color(0xFF2F80ED);
const Color secondaryIceBlue = Color(0xFF163B66);
const Color darkDeepTeal = Color(0xFF0D274D);
const Color mutedCoolGray = Color(0xFFB8C9DB);
const Color lightOffWhite = Color(0xFFF5F5F5);
const Color sidebarDark = Color(0xFF0D274D);

/// Prenatal status filter options
const List<String> statusFilterOptions = [
  'All Cases',
  'Active',
  'High Risk',
  'Follow Up',
  'Completed',
];

/// AI severity color mappings
Color getAISeverityColor(String severity) {
  switch (severity) {
    case 'Critical':
      return Colors.red;
    case 'High':
      return Colors.deepOrange;
    case 'Medium':
      return Colors.amber;
    case 'Low':
      return Colors.greenAccent;
    default:
      return Colors.white70;
  }
}

/// AI category color mappings
Color getAICategoryColor(String category) {
  switch (category) {
    case 'Communicable Disease':
      return Colors.orangeAccent;
    case 'Non-Communicable Disease':
      return Colors.purpleAccent;
    case 'Emergency':
      return Colors.redAccent;
    case 'Prenatal Care':
      return Colors.pinkAccent;
    case 'Pediatric Care':
      return Colors.cyanAccent;
    case 'Routine Checkup':
      return Colors.greenAccent;
    default:
      return primaryAqua;
  }
}
