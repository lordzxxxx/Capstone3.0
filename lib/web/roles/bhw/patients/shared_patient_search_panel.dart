import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';

class SharedPatientSearchPanel extends StatelessWidget {
  const SharedPatientSearchPanel({
    super.key,
    required this.query,
    required this.results,
    required this.isLoading,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String query;
  final List<Map<String, dynamic>> results;
  final bool isLoading;
  final String primaryActionLabel;
  final void Function(Map<String, dynamic> patient) onPrimaryAction;
  final String? secondaryActionLabel;
  final void Function(Map<String, dynamic> patient)? onSecondaryAction;

  static const Color _accent = Color(0xFF2F80ED);
  static const Color _surface = Color(0xFF0D274D);
  static const Color _surfaceAlt = Color(0xFF10343C);
  static const Color _text = Color(0xFFF5F5F5);
  static const Color _muted = Color(0xFF8BA3A8);

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();
    final uniqueResults = _dedupePatients(results);
    if (trimmedQuery.isEmpty && !isLoading) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people_alt_outlined,
                  color: _accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared Patient Matches',
                      style: TextStyle(
                        color: _text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Searching across patient, check-up, prenatal, immunization, mortality, and morbidity records.',
                      style: TextStyle(
                        color: _muted.withValues(alpha: 0.92),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.1,
                    color: _accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!isLoading && uniqueResults.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceAlt.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                'No shared patient match was found for "$trimmedQuery".',
                style: TextStyle(
                  color: _muted.withValues(alpha: 0.95),
                  fontSize: 12.5,
                ),
              ),
            )
          else
            ...uniqueResults.take(4).map(_buildPatientCard),
          if (!isLoading && uniqueResults.length > 4) ...[
            const SizedBox(height: 10),
            Text(
              '${uniqueResults.length - 4} more shared patient match${uniqueResults.length - 4 == 1 ? '' : 'es'} found. Refine the search text to narrow the list.',
              style: TextStyle(
                color: _muted.withValues(alpha: 0.95),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final patientName = patientDisplayName(patient);
    final patientId = _textValue(
      patient['patientId'],
      fallback: _textValue(patient['linkedPatientId']),
    );
    final age = _textValue(patient['age']);
    final address = _textValue(
      patient['address'],
      fallback: _textValue(patient['barangay']),
    );
    final sourceModules = List<String>.from(
      patient['sourceModules'] as List? ?? const <String>[],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildMetaLine(
                        patientId: patientId,
                        age: age,
                        address: address,
                      ),
                      style: TextStyle(
                        color: _muted.withValues(alpha: 0.96),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sourceModules.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sourceModules
                  .map(
                    (module) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        module,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () => onPrimaryAction(patient),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(primaryActionLabel),
              ),
              if (secondaryActionLabel != null && onSecondaryAction != null)
                OutlinedButton.icon(
                  onPressed: () => onSecondaryAction!(patient),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: BorderSide(color: _accent.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(secondaryActionLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildMetaLine({
    required String patientId,
    required String age,
    required String address,
  }) {
    final parts = <String>[];
    if (patientId.isNotEmpty) {
      parts.add('Patient ID: $patientId');
    }
    if (age.isNotEmpty) {
      parts.add('Age: $age');
    }
    if (address.isNotEmpty) {
      parts.add(address);
    }
    return parts.isEmpty
        ? 'Patient details from shared records'
        : parts.join('  |  ');
  }

  String _textValue(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> _dedupePatients(
    List<Map<String, dynamic>> patients,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];

    for (final patient in patients) {
      final patientId = _textValue(
        patient['patientId'],
        fallback: _textValue(
          patient['linkedPatientId'],
          fallback: _textValue(patient['patientCode']),
        ),
      ).toLowerCase();
      final patientName = _textValue(
        patient['patientName'],
        fallback: _textValue(patient['name']),
      ).toLowerCase();
      final address = _textValue(patient['address']).toLowerCase();
      final age = _textValue(patient['age']).toLowerCase();

      final key = patientId.isNotEmpty
          ? 'id:$patientId'
          : 'name:$patientName|address:$address|age:$age';

      if (seen.add(key)) {
        deduped.add(patient);
      }
    }

    return deduped;
  }
}
