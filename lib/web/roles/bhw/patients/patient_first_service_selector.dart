import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';

class PatientSelectionResult {
  const PatientSelectionResult._({this.patient, this.registerPatient = false});

  const PatientSelectionResult.selected(Map<String, dynamic> patient)
    : this._(patient: patient);

  const PatientSelectionResult.register() : this._(registerPatient: true);

  final Map<String, dynamic>? patient;
  final bool registerPatient;
}

class PatientFirstServiceSelector extends StatefulWidget {
  const PatientFirstServiceSelector({
    super.key,
    required this.serviceLabel,
    required this.patientService,
  });

  final String serviceLabel;
  final PatientCenteredHistoryService patientService;

  static Future<PatientSelectionResult?> show(
    BuildContext context, {
    required String serviceLabel,
    required PatientCenteredHistoryService patientService,
  }) {
    return showDialog<PatientSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PatientFirstServiceSelector(
        serviceLabel: serviceLabel,
        patientService: patientService,
      ),
    );
  }

  static Future<Map<String, dynamic>?> selectRegisteredPatient(
    BuildContext context, {
    required String serviceLabel,
    required PatientCenteredHistoryService patientService,
    required Future<void> Function() onRegisterPatient,
  }) async {
    final result = await show(
      context,
      serviceLabel: serviceLabel,
      patientService: patientService,
    );
    if (result?.registerPatient == true) {
      await onRegisterPatient();
      return null;
    }
    return result?.patient;
  }

  @override
  State<PatientFirstServiceSelector> createState() =>
      _PatientFirstServiceSelectorState();
}

class _PatientFirstServiceSelectorState
    extends State<PatientFirstServiceSelector> {
  static const _accent = Color(0xFF2F80ED);
  static const _background = Colors.white;
  static const _surface = Color(0xFFF5F7FA);
  static const _text = Color(0xFF0B1F3A);
  static const _cardBorder = Color(0xFFE2E8F0);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _isLoading = false;
        _hasSearched = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final results = await widget.patientService.searchRegisteredPatients(
        query,
      );
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasSearched = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Container(
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Search the Patient registry first',
                        style: TextStyle(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'A registered patient must be selected before a ${widget.serviceLabel.toLowerCase()} record can be created.',
                        style: TextStyle(
                          color: _text.withValues(alpha: 0.65),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _scheduleSearch,
                        style: const TextStyle(color: _text),
                        decoration: InputDecoration(
                          hintText:
                              'Search by patient name, record ID, phone, or barangay',
                          hintStyle: TextStyle(
                            color: _text.withValues(alpha: 0.42),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _accent,
                          ),
                          suffixIcon: _isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _accent,
                                    ),
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: _surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_hasSearched && !_isLoading)
                        _instructionState()
                      else if (_hasSearched && _results.isEmpty)
                        _notFoundState(context)
                      else
                        ..._results.take(8).map(_patientCard),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Select Patient for ${widget.serviceLabel}',
              style: const TextStyle(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _text),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _instructionState() {
    return _messageCard(
      icon: Icons.badge_outlined,
      title: 'Patient selection is required',
      message:
          'Enter at least part of the patient name or record ID. Results come only from the registered Patient module.',
    );
  }

  Widget _notFoundState(BuildContext context) {
    return _messageCard(
      icon: Icons.person_add_alt_1_rounded,
      title: 'Patient not found',
      message:
          'Register this person in the Patient module before creating the ${widget.serviceLabel.toLowerCase()} record.',
      action: ElevatedButton.icon(
        onPressed: () =>
            Navigator.pop(context, const PatientSelectionResult.register()),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Register New Patient'),
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: _accent, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _text.withValues(alpha: 0.62), height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }

  Widget _patientCard(Map<String, dynamic> patient) {
    final name = patientDisplayName(patient, fallback: 'Unnamed patient');
    final patientId = _value(
      patient['patientId'],
      fallback: _value(patient['id'], fallback: 'No record ID'),
    );
    final age = _value(patient['age'], fallback: 'Age not recorded');
    final barangay = _value(
      patient['barangay'],
      fallback: _value(patient['address'], fallback: 'Address not recorded'),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _accent.withValues(alpha: 0.15),
            foregroundColor: _accent,
            child: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$patientId  •  $age  •  $barangay',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _text.withValues(alpha: 0.58),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(
              context,
              PatientSelectionResult.selected(patient),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Select'),
          ),
        ],
      ),
    );
  }

  String _value(dynamic value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
