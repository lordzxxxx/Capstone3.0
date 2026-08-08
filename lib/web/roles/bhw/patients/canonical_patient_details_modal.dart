import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';

class CanonicalPatientDetailsModal extends StatelessWidget {
  const CanonicalPatientDetailsModal({
    super.key,
    required this.patient,
    this.onAction,
  });

  final Map<String, dynamic> patient;
  final void Function(String action, Map<String, dynamic> patient)? onAction;

  static const _accent = Color(0xFF00A8B5);
  static const _background = Color(0xFF081D22);
  static const _surface = Color(0xFF0E2F34);
  static const _field = Color(0xFF061920);
  static const _text = Color(0xFFF5F7FA);

  String _value(dynamic value, {String fallback = 'Not provided'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _fallbackValue(
    String primaryKey,
    String fallbackKey, {
    String fallback = 'Not provided',
  }) {
    final primary = patient[primaryKey]?.toString().trim() ?? '';
    return primary.isNotEmpty
        ? primary
        : _value(patient[fallbackKey], fallback: fallback);
  }

  String get _fullName {
    final canonical = patient['fullName']?.toString().trim() ?? '';
    if (canonical.isNotEmpty) return canonical;
    final legacy = [patient['firstName'], patient['surname']]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
    return legacy.isEmpty ? 'Unknown Patient' : legacy;
  }

  ({String firstName, String surname}) get _nameParts {
    var legacyFirstName = '';
    var legacySurname = '';
    final fullName = patient['fullName']?.toString().trim() ?? '';
    final normalized = fullName.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.contains(',')) {
      final parts = normalized.split(',');
      legacySurname = parts.first.trim();
      legacyFirstName = parts.skip(1).join(' ').trim();
    } else if (normalized.isNotEmpty) {
      final parts = normalized.split(' ');
      legacyFirstName = parts.length == 1
          ? parts.first
          : parts.sublist(0, parts.length - 1).join(' ');
      legacySurname = parts.length == 1 ? '' : parts.last;
    }

    return (
      firstName: _value(
        patient['firstName'],
        fallback: legacyFirstName.isEmpty ? 'Not provided' : legacyFirstName,
      ),
      surname: _value(
        patient['surname'],
        fallback: legacySurname.isEmpty ? 'Not provided' : legacySurname,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientId = _fallbackValue('patientId', 'id');
    final status = _value(patient['status'], fallback: 'Active');
    final name = _nameParts;
    return Dialog.fullscreen(
      backgroundColor: _background,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: _text,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient Details',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Canonical patient registration record',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _text,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Close'),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityBanner(patientId, status),
                const SizedBox(height: 20),
                _section(
                  title: 'Patient Identity',
                  subtitle:
                      'The shared identity used by every health-service record.',
                  items: [
                    (
                      'First Name',
                      name.firstName,
                      Icons.person_outline_rounded,
                    ),
                    ('Surname', name.surname, Icons.badge_outlined),
                    (
                      'Date of Birth',
                      _value(patient['dateOfBirth']),
                      Icons.cake_outlined,
                    ),
                    ('Age', _value(patient['age']), Icons.numbers_rounded),
                    ('Sex', _fallbackValue('sex', 'gender'), Icons.wc_rounded),
                  ],
                ),
                const SizedBox(height: 18),
                _section(
                  title: 'Address and Contact',
                  subtitle:
                      'Barangay assignment, household, and care-coordination information.',
                  items: [
                    (
                      'Address',
                      _fallbackValue('address', 'street'),
                      Icons.home_outlined,
                    ),
                    (
                      'Barangay',
                      _value(patient['barangay']),
                      Icons.location_city_outlined,
                    ),
                    (
                      'Household ID',
                      _value(patient['householdId']),
                      Icons.home_work_outlined,
                    ),
                    (
                      'Contact Number',
                      _fallbackValue('contactNumber', 'phoneNumber'),
                      Icons.phone_outlined,
                    ),
                    (
                      'Emergency Contact',
                      _fallbackValue(
                        'emergencyContact',
                        'emergencyContactName',
                      ),
                      Icons.contact_emergency_outlined,
                    ),
                    (
                      'Emergency Contact Number',
                      _fallbackValue(
                        'emergencyContactNumber',
                        'emergencyContactPhone',
                      ),
                      Icons.phone_in_talk_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _section(
                  title: 'Baseline Health Information',
                  subtitle:
                      'Health information supplied during patient registration.',
                  items: [
                    (
                      'Medical History',
                      _fallbackValue('medicalHistory', 'pastMedicalHistory'),
                      Icons.history_rounded,
                    ),
                    (
                      'Allergies',
                      _value(patient['allergies'], fallback: 'None reported'),
                      Icons.health_and_safety_outlined,
                    ),
                    (
                      'Blood Type',
                      _value(patient['bloodType']),
                      Icons.bloodtype_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _healthTimeline(),
                const SizedBox(height: 18),
                _quickActions(context),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _healthTimeline() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Health Timeline',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Linked records using this Patient ID.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          FutureBuilder<PatientModuleHistorySnapshot>(
            future: PatientCenteredHistoryService().loadPatientHistory(patient),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: _accent),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const Text(
                  'Linked health records could not be loaded.',
                  style: TextStyle(color: Colors.white60),
                );
              }
              final history = snapshot.data;
              if (history == null || history.totalRecords == 0) {
                return const Text(
                  'No linked health-service records yet.',
                  style: TextStyle(color: Colors.white60),
                );
              }
              final counts = <(String, int)>[
                ('Check-ups', history.checkUpHistory.length),
                ('Prenatal', history.prenatalHistory.length),
                ('Immunization', history.immunizationHistory.length),
                ('Morbidity', history.morbidityHistory.length),
                ('Mortality', history.mortalityHistory.length),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: counts
                        .map(
                          (entry) => Chip(
                            backgroundColor: _field,
                            side: BorderSide(
                              color: _accent.withValues(alpha: 0.22),
                            ),
                            label: Text(
                              '${entry.$1}: ${entry.$2}',
                              style: const TextStyle(color: _text),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 14),
                  ...history.timeline
                      .take(8)
                      .map(
                        (event) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.radio_button_checked,
                            color: _accent,
                            size: 18,
                          ),
                          title: Text(
                            '${event.module}: ${event.title}',
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            event.subtitle,
                            style: const TextStyle(color: Colors.white60),
                          ),
                          trailing: Text(
                            _formatDate(event.eventDate),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    const actions = <(String, String, IconData)>[
      ('checkup', 'Record Check-up', Icons.medical_services_outlined),
      ('prenatal', 'Record Prenatal Visit', Icons.pregnant_woman),
      ('immunization', 'Record Immunization', Icons.vaccines_outlined),
      ('morbidity', 'Record Morbidity', Icons.monitor_heart_outlined),
      ('mortality', 'Record Mortality', Icons.assignment_outlined),
      ('referral', 'Create Referral', Icons.outbound_outlined),
      ('followup', 'Schedule Follow-up', Icons.event_repeat_rounded),
      ('print', 'Print Patient Summary', Icons.print_outlined),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions
                .map(
                  (action) => OutlinedButton.icon(
                    onPressed: onAction == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            onAction!(action.$1, patient);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                    icon: Icon(action.$3, color: _accent, size: 18),
                    label: Text(action.$2),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.month)}/${two(date.day)}/${date.year}';
  }

  Widget _identityBanner(String patientId, String status) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF103D44), Color(0xFF0E2F34)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.badge_outlined, color: _accent, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient ID: $patientId',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<(String, String, IconData)> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1200
                  ? 3
                  : constraints.maxWidth >= 700
                  ? 2
                  : 1;
              final itemWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (14 * (columns - 1))) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: itemWidth,
                        child: _detailTile(
                          label: item.$1,
                          value: item.$2,
                          icon: item.$3,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _accent, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
