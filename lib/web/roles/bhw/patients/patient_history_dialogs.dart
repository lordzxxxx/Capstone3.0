import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/shared/widgets/doctor_notes_section.dart';

class PatientHistoryDialogs {
  static const Color _primaryAqua = Color(0xFF2F80ED);
  static const Color _lightOffWhite = Color(0xFF0B1F3A);
  static const Color _historyText = _lightOffWhite;
  static const Color _historySurface = Colors.white;
  static const Color _historyBackground = Color(0xFFF4F7FB);
  static const Color _historyDetailBlue = Color(0xFF2563EB);
  static const Color _historyMuted = Color(0xFF4B6075);
  static const Color _historyBorder = Color(0xFFE2E8F0);
  static const Color _historySoftBlue = Color(0xFFEAF2FF);

  static List<Map<String, dynamic>> collectHistory({
    required Map<String, dynamic> seedRecord,
    required List<Map<String, dynamic>> records,
    List<String> idKeys = const ['linkedPatientId', 'patientId'],
    List<String> nameKeys = const ['patientName', 'patient', 'name'],
    List<String> sortDateKeys = const [
      'dateReported',
      'registrationDate',
      'datetime',
      'date',
    ],
  }) {
    final seedIdentifiers = <String>{
      for (final key in idKeys) _normalize(seedRecord[key]),
    }..removeWhere((value) => value.isEmpty);

    final seedNames = <String>{
      for (final key in nameKeys) _normalize(seedRecord[key]),
    }..removeWhere((value) => value.isEmpty);

    final history = records
        .where((record) {
          final hasIdMatch = idKeys.any((key) {
            final value = _normalize(record[key]);
            return value.isNotEmpty && seedIdentifiers.contains(value);
          });
          if (hasIdMatch) {
            return true;
          }

          return nameKeys.any((key) {
            final value = _normalize(record[key]);
            return value.isNotEmpty && seedNames.contains(value);
          });
        })
        .map((record) => Map<String, dynamic>.from(record))
        .toList();

    history.sort((left, right) {
      final leftDate = _firstDate(left, sortDateKeys);
      final rightDate = _firstDate(right, sortDateKeys);
      if (leftDate == null && rightDate == null) {
        return 0;
      }
      if (leftDate == null) {
        return 1;
      }
      if (rightDate == null) {
        return -1;
      }
      return rightDate.compareTo(leftDate);
    });

    return history;
  }

  static Future<void> showModuleHistoryDialog({
    required BuildContext context,
    required String moduleTitle,
    required Map<String, dynamic> seedRecord,
    required List<Map<String, dynamic>> history,
    String? description,
    String? addButtonLabel,
    String? emptyMessage,
    String Function(Map<String, dynamic> record)? titleBuilder,
    String Function(Map<String, dynamic> record)? subtitleBuilder,
    String Function(Map<String, dynamic> record)? metaBuilder,
    List<String> dateKeys = const [
      'dateReported',
      'registrationDate',
      'datetime',
      'date',
    ],
    VoidCallback? onAddAnother,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    void Function(Map<String, dynamic> record)? onOpenRecord,
  }) async {
    final latestRecord = history.isNotEmpty ? history.first : seedRecord;
    final patientName = _patientName(latestRecord);
    final patientId = _patientId(latestRecord);
    final latestDate = _firstDate(latestRecord, dateKeys);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
            ),
            decoration: BoxDecoration(
              color: _historySurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _historyBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _historySurface,
                    border: Border(bottom: BorderSide(color: _historyBorder)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$moduleTitle History',
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              patientName,
                              style: TextStyle(
                                color: _historyDetailBlue,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description ??
                                  'Review previous records first, then add the next visit for the same patient.',
                              style: TextStyle(
                                color: _historyMuted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: _historyDetailBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildSummaryChip(
                        icon: Icons.badge_outlined,
                        label: 'Patient ID',
                        value: patientId.isEmpty ? 'Not linked' : patientId,
                      ),
                      _buildSummaryChip(
                        icon: Icons.library_books_outlined,
                        label: 'History Entries',
                        value: '${history.length}',
                      ),
                      _buildSummaryChip(
                        icon: Icons.event_outlined,
                        label: 'Latest Update',
                        value: latestDate == null
                            ? 'No date'
                            : _formatDate(latestDate),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: history.isEmpty
                        ? Center(
                            child: Text(
                              emptyMessage ??
                                  'No previous records were found for this patient in this module.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _historyMuted,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: history.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final record = history[index];
                              final title =
                                  titleBuilder?.call(record) ??
                                  _patientName(record);
                              final subtitle =
                                  subtitleBuilder?.call(record) ??
                                  'Record ${index + 1}';
                              final meta = metaBuilder?.call(record) ?? '';
                              final date = _firstDate(record, dateKeys);
                              return InkWell(
                                onTap: onOpenRecord == null
                                    ? null
                                    : () => onOpenRecord(record),
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _historySurface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: _historyBorder),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: const TextStyle(
                                                    color: _historyText,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  subtitle,
                                                  style: TextStyle(
                                                    color: _historyDetailBlue,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _primaryAqua.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              date == null
                                                  ? 'No date'
                                                  : _formatDate(date),
                                              style: const TextStyle(
                                                color: _historyDetailBlue,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (meta.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          meta,
                                          style: TextStyle(
                                            color: _historyDetailBlue,
                                            fontSize: 12.5,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final actions = <Widget>[
                        OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: _historyOutlinedButtonStyle(),
                          child: const Text('Close'),
                        ),
                        if (onSecondaryAction != null)
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onSecondaryAction();
                            },
                            icon: const Icon(Icons.timeline_rounded),
                            label: Text(
                              secondaryActionLabel ?? 'Open Medical History',
                            ),
                            style: _historyOutlinedButtonStyle(),
                          ),
                        if (onAddAnother != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onAddAnother();
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text(addButtonLabel ?? 'Add Another Record'),
                            style: _historyPrimaryButtonStyle(),
                          ),
                      ];
                      final compact = constraints.maxWidth < 640;
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < actions.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 10),
                              SizedBox(height: 48, child: actions[index]),
                            ],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          for (
                            var index = 0;
                            index < actions.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: actions[index],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> showPatientTimelineDialog({
    required BuildContext context,
    required Map<String, dynamic> patient,
    required PatientModuleHistorySnapshot snapshot,
  }) async {
    final effectivePatient = <String, dynamic>{...snapshot.patient, ...patient};
    final patientName = _buildPatientName(effectivePatient);
    final patientId = _safeText(
      effectivePatient['patientId'],
      fallback: _safeText(effectivePatient['id']),
    );
    final timeline = snapshot.timeline;
    final availableModules = <String>{
      for (final event in timeline) event.module,
    }.toList();
    var selectedModule = 'All Records';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final screenSize = MediaQuery.of(dialogContext).size;
            final isCompact = screenSize.width < 760;
            final contentPadding = isCompact ? 16.0 : 28.0;
            final filteredTimeline = selectedModule == 'All Records'
                ? timeline
                : timeline
                      .where((event) => event.module == selectedModule)
                      .toList();
            final lastEncounter = timeline.isEmpty ? null : timeline.first;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: screenSize.width,
                height: screenSize.height,
                child: ColoredBox(
                  color: _historyBackground,
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildHistoryHeader(
                          dialogContext,
                          patientName: patientName,
                          patientId: patientId,
                          isCompact: isCompact,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(contentPadding),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildPatientCareContext(
                                  effectivePatient,
                                  isCompact: isCompact,
                                ),
                                const SizedBox(height: 20),
                                _buildSectionPanel(
                                  title: 'Continuity of Care',
                                  subtitle:
                                      'A synchronized summary of this patient’s linked health-service records. Use it to review prior care before documenting a new service.',
                                  icon: Icons.health_and_safety_outlined,
                                  accentColor: _primaryAqua,
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildHistoryMetric(
                                        label: 'Total Encounters',
                                        value: '${snapshot.totalRecords}',
                                        icon: Icons.folder_copy_outlined,
                                        accentColor: _primaryAqua,
                                      ),
                                      _buildHistoryMetric(
                                        label: 'Services Used',
                                        value: '${availableModules.length}',
                                        icon: Icons.hub_outlined,
                                        accentColor: const Color(0xFF64B5F6),
                                      ),
                                      _buildHistoryMetric(
                                        label: 'Latest Encounter',
                                        value: lastEncounter?.eventDate == null
                                            ? 'No dated record'
                                            : _formatDate(
                                                lastEncounter!.eventDate!,
                                              ),
                                        icon: Icons.event_available_outlined,
                                        accentColor: const Color(0xFF81C784),
                                      ),
                                      _buildHistoryMetric(
                                        label: 'Latest Service',
                                        value: lastEncounter?.module ?? 'None',
                                        icon: Icons.medical_services_outlined,
                                        accentColor: const Color(0xFFFFB74D),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildSectionPanel(
                                  title: 'Service Record Summary',
                                  subtitle:
                                      'Counts come from the patient’s linked Firestore records across each health program.',
                                  icon: Icons.space_dashboard_outlined,
                                  accentColor: const Color(0xFF64B5F6),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildCountTile(
                                        'Check Up',
                                        '${snapshot.checkUpHistory.length}',
                                      ),
                                      _buildCountTile(
                                        'Prenatal',
                                        '${snapshot.prenatalHistory.length}',
                                      ),
                                      _buildCountTile(
                                        'Immunization',
                                        '${snapshot.immunizationHistory.length}',
                                      ),
                                      _buildCountTile(
                                        'Communicable',
                                        '${snapshot.communicableHistory.length}',
                                      ),
                                      _buildCountTile(
                                        'Non-Communicable',
                                        '${snapshot.nonCommunicableHistory.length}',
                                      ),
                                      _buildCountTile(
                                        'Morbidity',
                                        '${snapshot.morbidityHistory.length}',
                                      ),
                                      if (snapshot.mortalityHistory.isNotEmpty)
                                        _buildCountTile(
                                          'Mortality',
                                          '${snapshot.mortalityHistory.length}',
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildSectionPanel(
                                  title: 'Chronological Health Timeline',
                                  subtitle:
                                      'Newest records appear first. Filter by service, then select a record to review its complete documented details.',
                                  icon: Icons.timeline_rounded,
                                  accentColor: _primaryAqua,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children:
                                            [
                                              'All Records',
                                              ...availableModules,
                                            ].map((module) {
                                              return _buildTimelineFilter(
                                                label: module,
                                                selected:
                                                    selectedModule == module,
                                                onSelected: () =>
                                                    setDialogState(
                                                      () => selectedModule =
                                                          module,
                                                    ),
                                              );
                                            }).toList(),
                                      ),
                                      const SizedBox(height: 18),
                                      if (filteredTimeline.isEmpty)
                                        _buildEmptyState(
                                          selectedModule == 'All Records'
                                              ? 'No linked health-service records were found for this patient.'
                                              : 'No $selectedModule records were found for this patient.',
                                        )
                                      else
                                        ...filteredTimeline.indexed.map((item) {
                                          final index = item.$1;
                                          final event = item.$2;
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              bottom:
                                                  index ==
                                                      filteredTimeline.length -
                                                          1
                                                  ? 0
                                                  : 12,
                                            ),
                                            child: _buildTimelineEventCard(
                                              dialogContext,
                                              event,
                                              accentColor: _timelineModuleColor(
                                                event.module,
                                              ),
                                              moduleIcon: _timelineModuleIcon(
                                                event.module,
                                              ),
                                            ),
                                          );
                                        }),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                DoctorNotesSection(
                                  patientId: patientId,
                                  patientName: patientName,
                                  patientBarangayCode: _safeText(
                                    effectivePatient['barangayCode'],
                                  ),
                                  checkupOptions: snapshot.checkUpHistory
                                      .map((record) {
                                        final date = _firstDate(record, const [
                                          'datetime',
                                          'date',
                                          'followup',
                                        ]);
                                        final dateLabel = date == null
                                            ? 'Undated'
                                            : _formatDate(date);
                                        final type = _safeText(
                                          record['type'],
                                          fallback: 'Check-up',
                                        );
                                        return DoctorNoteCheckupOption(
                                          id: _safeText(record['id']),
                                          label: '$dateLabel — $type',
                                        );
                                      })
                                      .where((option) => option.id.isNotEmpty)
                                      .toList(growable: false),
                                ),
                                const SizedBox(height: 24),
                                _buildClinicalDisclaimer(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static ButtonStyle _historyOutlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _historyDetailBlue,
      side: const BorderSide(color: _historyDetailBlue, width: 1.4),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle _historyPrimaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: _historyDetailBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  static Widget _buildHistoryHeader(
    BuildContext dialogContext, {
    required String patientName,
    required String patientId,
    required bool isCompact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 28,
        vertical: isCompact ? 14 : 18,
      ),
      decoration: BoxDecoration(
        color: _historySurface,
        border: Border(bottom: BorderSide(color: _historyBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patient Health History',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontSize: isCompact ? 19 : 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  patientId.isEmpty
                      ? patientName
                      : '$patientName  •  Patient ID: $patientId',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _historyDetailBlue,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!isCompact)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF059669),
                    size: 16,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Linked health records',
                    style: TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            tooltip: 'Close patient health history',
            style: IconButton.styleFrom(
              foregroundColor: _historyDetailBlue,
              backgroundColor: _historySoftBlue,
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  static Widget _buildPatientCareContext(
    Map<String, dynamic> patient, {
    required bool isCompact,
  }) {
    final age = _safeText(patient['age'], fallback: 'Not recorded');
    final sex = _safeText(
      patient['sex'],
      fallback: _safeText(patient['gender'], fallback: 'Not recorded'),
    );
    final dateOfBirth = _safeText(
      patient['dateOfBirth'],
      fallback: 'Not recorded',
    );
    final barangay = _safeText(patient['barangay'], fallback: 'Not assigned');
    final address = _safeText(patient['address'], fallback: 'Not recorded');
    final householdId = _safeText(
      patient['householdId'],
      fallback: 'Not recorded',
    );
    final contact = _safeText(
      patient['contactNumber'],
      fallback: _safeText(patient['phoneNumber'], fallback: 'Not recorded'),
    );
    final emergencyName = _safeText(
      patient['emergencyContact'],
      fallback: _safeText(
        patient['emergencyContactName'],
        fallback: 'Not recorded',
      ),
    );
    final emergencyNumber = _safeText(
      patient['emergencyContactNumber'],
      fallback: _safeText(
        patient['emergencyContactPhone'],
        fallback: 'Not recorded',
      ),
    );
    final medicalHistory = _safeText(
      patient['medicalHistory'],
      fallback: _safeText(
        patient['pastMedicalHistory'],
        fallback: 'No history recorded',
      ),
    );
    final allergies = _safeText(
      patient['allergies'],
      fallback: 'No allergies recorded',
    );

    final cards = <Widget>[
      _buildCareContextCard(
        title: 'Patient Identity',
        icon: Icons.person_outline_rounded,
        accentColor: _primaryAqua,
        entries: [
          MapEntry('Date of birth', dateOfBirth),
          MapEntry('Age / Sex', '$age / $sex'),
          MapEntry('Barangay', barangay),
          MapEntry('Address', address),
        ],
      ),
      _buildCareContextCard(
        title: 'Clinical Safety',
        icon: Icons.health_and_safety_outlined,
        accentColor: const Color(0xFFFFB74D),
        entries: [
          MapEntry('Allergies', allergies),
          MapEntry('Medical history', medicalHistory),
        ],
      ),
      _buildCareContextCard(
        title: 'Care Coordination',
        icon: Icons.contact_phone_outlined,
        accentColor: const Color(0xFF64B5F6),
        entries: [
          MapEntry('Household ID', householdId),
          MapEntry('Patient contact', contact),
          MapEntry('Emergency contact', emergencyName),
          MapEntry('Emergency number', emergencyNumber),
        ],
      ),
    ];

    return _buildSectionPanel(
      title: 'Patient Care Context',
      subtitle:
          'Confirm the patient’s identity, safety information, and contact details before reviewing or recording care.',
      icon: Icons.account_box_outlined,
      accentColor: _primaryAqua,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = isCompact
              ? 1
              : constraints.maxWidth >= 1050
              ? 3
              : 2;
          const spacing = 12.0;
          final width = columns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - (spacing * (columns - 1))) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map((card) => SizedBox(width: width, child: card))
                .toList(),
          );
        },
      ),
    );
  }

  static Widget _buildCareContextCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<MapEntry<String, String>> entries,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 205),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _historyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _historyText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      color: _historyMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.value,
                    style: TextStyle(
                      color: _historyDetailBlue,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildHistoryMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _historyBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _historyMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _historyText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTimelineFilter({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _primaryAqua : _historySoftBlue,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? _primaryAqua : _historyBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _historyDetailBlue,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildClinicalDisclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _historySoftBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _historyBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _historyDetailBlue, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'This history supports continuity of care and record review. It does not replace clinical assessment, diagnosis, prescription, or emergency evaluation.',
              style: TextStyle(
                color: _historyDetailBlue,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showTimelineEventDetailsDialog({
    required BuildContext context,
    required PatientTimelineEvent event,
  }) async {
    final detailEntries = _buildTimelineDetailEntries(event);
    final resolvedEntries = detailEntries.isNotEmpty
        ? detailEntries
        : _buildFallbackTimelineDetailEntries(event);
    final patientName = _patientName(event.rawRecord);
    final recordId = _safeText(event.rawRecord['id'], fallback: 'No record ID');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final accentColor = _timelineModuleColor(event.module);
        final isCompact = screenSize.width < 960;
        final contentPadding = isCompact ? 18.0 : 28.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: Container(
              decoration: const BoxDecoration(color: _historyBackground),
              child: SafeArea(
                minimum: EdgeInsets.all(isCompact ? 12 : 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _historySurface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: _historyBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.34),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(isCompact ? 18 : 22),
                            decoration: BoxDecoration(
                              color: _historySurface,
                              border: Border(
                                bottom: BorderSide(color: _historyBorder),
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(30),
                                topRight: Radius.circular(30),
                              ),
                            ),
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: _historySoftBlue,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: _historyBorder),
                                  ),
                                  child: Icon(
                                    _timelineModuleIcon(event.module),
                                    color: accentColor,
                                    size: 26,
                                  ),
                                ),
                                SizedBox(
                                  width: isCompact
                                      ? screenSize.width - 118
                                      : 520,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${event.module} Details',
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        event.title,
                                        style: TextStyle(
                                          color: _historyDetailBlue,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (patientName.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          patientName,
                                          style: TextStyle(
                                            color: _historyMuted,
                                            fontSize: 12.2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: _historySoftBlue,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: _historyBorder),
                                    ),
                                    child: IconButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: _historyDetailBlue,
                                      ),
                                      tooltip: 'Close',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(contentPadding),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildSummaryChip(
                                        icon: Icons.event_outlined,
                                        label: 'Event Timestamp',
                                        value: event.eventDate == null
                                            ? 'No timestamp'
                                            : _formatTimestamp(
                                                event.eventDate!,
                                              ),
                                        accentColor: accentColor,
                                      ),
                                      _buildSummaryChip(
                                        icon: Icons.badge_outlined,
                                        label: 'Record ID',
                                        value: recordId,
                                        accentColor: accentColor,
                                      ),
                                      if (patientName.isNotEmpty)
                                        _buildSummaryChip(
                                          icon: Icons.person_outline_rounded,
                                          label: 'Patient',
                                          value: patientName,
                                          accentColor: accentColor,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  _buildSectionPanel(
                                    title: 'Complete Details',
                                    subtitle:
                                        'The table below shows the full set of stored values for the selected record, including organized AI recommendations when available.',
                                    icon: Icons.table_rows_outlined,
                                    accentColor: accentColor,
                                    child: resolvedEntries.isEmpty
                                        ? _buildEmptyState(
                                            'No additional details were stored for this timeline record.',
                                          )
                                        : _buildDetailTable(
                                            resolvedEntries,
                                            accentColor: accentColor,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.fromLTRB(
                              contentPadding,
                              0,
                              contentPadding,
                              contentPadding,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: _historyBorder),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Close'),
                                  style: _historyOutlinedButtonStyle(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static List<MapEntry<String, String>> _buildTimelineDetailEntries(
    PatientTimelineEvent event,
  ) {
    final record = event.rawRecord;
    final orderedKeys = _prioritizedDetailKeys(event.module);
    final usedLabels = <String>{};
    final entries = <MapEntry<String, String>>[];

    void addKey(String key) {
      if (!record.containsKey(key) ||
          _hiddenDetailKeys.contains(key) ||
          (event.module == 'Check Up' && key == 'plan')) {
        return;
      }

      final label = _labelForKey(key);
      final normalizedLabel = label.toLowerCase();
      if (!usedLabels.add(normalizedLabel)) {
        return;
      }

      final value = _formatDetailValue(record[key], key: key);
      if (value.isEmpty) {
        return;
      }

      entries.add(MapEntry(label, value));
    }

    for (final key in orderedKeys) {
      addKey(key);
    }

    final remainingKeys = record.keys.map((key) => key.toString()).toList()
      ..sort();
    for (final key in remainingKeys) {
      addKey(key);
    }

    return entries;
  }

  static List<String> _prioritizedDetailKeys(String module) {
    const common = <String>[
      'patientName',
      'patient',
      'name',
      'patientId',
      'linkedPatientId',
      'patientCode',
      'age',
      'gender',
      'address',
      'contactNumber',
      'status',
    ];

    switch (module) {
      case 'Check Up':
        return <String>[
          ...common,
          'datetime',
          'type',
          'diseaseType',
          'vitalsigns',
          'vitalSigns',
          'symptoms',
          'diagnosis',
          'condition',
          'complaint',
          'details',
          'remarks',
          'followup',
          'ai_category',
          'ai_severity',
          'ai_confidence',
          'ai_recovery_plan',
        ];
      case 'Prenatal':
        return <String>[
          ...common,
          'registrationDate',
          'lmpDate',
          'eddDate',
          'dueDate',
          'gestationalAge',
          'aog',
          'gravida',
          'para',
          'riskLevel',
          'bloodType',
          'civilStatus',
          'philhealthNumber',
          'philhealthMember',
          'religion',
          'allergies',
          'preExistingConditions',
          'previousComplications',
          'weight',
          'wt',
          'bloodPressure',
          'bp',
          'temperature',
          'temp',
          'bmi',
          'fundalHeight',
          'fh',
          'fetalHeartBeat',
          'dhb',
          'tcb',
          'registeredBy',
          'additionalNotes',
          'additionalNote',
          'ai_category',
          'ai_severity',
          'ai_confidence',
          'ai_recovery_plan',
        ];
      case 'Immunization':
        return <String>[
          ...common,
          'administrationDate',
          'date',
          'time',
          'vaccine',
          'vaccineBrand',
          'doseNumber',
          'routeOfAdministration',
          'injectionSite',
          'batchNumber',
          'expirationDate',
          'administeredBy',
          'adverseEvents',
          'nextDoseDueDate',
        ];
      case 'Mortality':
        return <String>[
          ...common,
          'dateReported',
          'date',
          'causeOfDeath',
          'place',
          'verification',
          'reportedBy',
          'remarks',
        ];
      case 'Communicable':
      case 'Non-Communicable':
      case 'Morbidity':
        return <String>[
          ...common,
          'datetime',
          'dateReported',
          'date',
          'type',
          'diseaseType',
          'disease',
          'diagnosis',
          'condition',
          'symptoms',
          'details',
          'severity',
          'plan',
          'followup',
          'remarks',
          'ai_category',
          'ai_severity',
        ];
      default:
        return common;
    }
  }

  static const Set<String> _hiddenDetailKeys = <String>{
    'id',
    'ai_confidence',
    'confidence',
    'predictionConfidence',
  };

  static List<MapEntry<String, String>> _buildFallbackTimelineDetailEntries(
    PatientTimelineEvent event,
  ) {
    final record = event.rawRecord;
    final entries = <MapEntry<String, String>>[];

    void addEntry(String label, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty ||
          trimmed.toLowerCase() == 'null' ||
          trimmed.toLowerCase() == 'undefined') {
        return;
      }
      entries.add(MapEntry(label, trimmed));
    }

    addEntry('Patient Name', _patientName(record));
    addEntry('Patient ID', _patientId(record));
    addEntry(
      event.module == 'Check Up' ? 'Assessment Summary' : 'Summary',
      _safeText(
        record['details'],
        fallback: _safeText(
          record['symptoms'],
          fallback: _safeText(record['status'], fallback: event.subtitle),
        ),
      ),
    );
    addEntry('Status', _safeText(record['status']));
    addEntry(
      'Timestamp',
      event.eventDate == null ? '' : _formatTimestamp(event.eventDate!),
    );
    addEntry(
      'Vital Signs',
      _safeText(
        record['vitalsigns'],
        fallback: _safeText(record['vitalSigns']),
      ),
    );
    if (event.module != 'Check Up') {
      addEntry('Plan', _safeText(record['plan']));
    }

    return entries;
  }

  static String _labelForKey(String key) {
    const labels = <String, String>{
      'patientName': 'Patient Name',
      'patient': 'Patient Name',
      'name': 'Patient Name',
      'patientId': 'Patient ID',
      'linkedPatientId': 'Linked Patient ID',
      'patientCode': 'Patient Code',
      'dateReported': 'Date Reported',
      'registrationDate': 'Registration Date',
      'administrationDate': 'Administration Date',
      'datetime': 'Date & Time',
      'date': 'Date',
      'time': 'Time',
      'followup': 'Follow-Up Date',
      'contactNumber': 'Contact Number',
      'civilStatus': 'Civil Status',
      'philhealthNumber': 'PhilHealth Number',
      'philhealthMember': 'PhilHealth Member',
      'lmpDate': 'Last Menstrual Period',
      'eddDate': 'Expected Delivery Date',
      'dueDate': 'Due Date',
      'gestationalAge': 'Gestational Age',
      'aog': 'Age of Gestation',
      'preExistingConditions': 'Pre-Existing Conditions',
      'previousComplications': 'Previous Complications',
      'bloodPressure': 'Blood Pressure',
      'fundalHeight': 'Fundal Height',
      'fetalHeartBeat': 'Fetal Heart Beat',
      'vitalsigns': 'Vital Signs',
      'diseaseType': 'Disease Type',
      'causeOfDeath': 'Cause of Death',
      'reportedBy': 'Reported By',
      'routeOfAdministration': 'Route of Administration',
      'injectionSite': 'Injection Site',
      'batchNumber': 'Batch Number',
      'vaccineBrand': 'Vaccine Brand',
      'doseNumber': 'Dose Number',
      'administeredBy': 'Administered By',
      'adverseEvents': 'Adverse Events',
      'nextDoseDueDate': 'Next Dose Due Date',
      'riskLevel': 'Risk Level',
      'ai_category': 'AI Category',
      'ai_severity': 'AI Severity',
      'ai_recovery_plan': 'AI Recovery Plan',
    };

    final mapped = labels[key];
    if (mapped != null) {
      return mapped;
    }

    final normalized = key
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) {
          return '${match.group(1)} ${match.group(2)}';
        })
        .replaceAll('_', ' ')
        .trim();

    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _formatDetailValue(dynamic value, {String? key}) {
    if (key == 'ai_recovery_plan') {
      return _formatAiRecoveryPlanValue(value);
    }
    if (key != null && _historyDateKeys.contains(key)) {
      final parsed = _tryParseHistoryDate(value);
      if (parsed != null) {
        final format = _historyDateTimeKeys.contains(key)
            ? DateFormat('MMMM d, yyyy • h:mm a')
            : DateFormat('MMMM d, yyyy');
        return format.format(parsed.toLocal());
      }
    }
    if (value == null) {
      return '';
    }
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    if (value is List) {
      final parts = value
          .map((item) => _formatDetailValue(item))
          .where((item) => item.isNotEmpty)
          .toList();
      return parts.join(', ');
    }
    if (value is Map) {
      final parts = value.entries
          .map((entry) {
            final formatted = _formatDetailValue(entry.value);
            if (formatted.isEmpty) {
              return '';
            }
            return '${_labelForKey(entry.key.toString())}: $formatted';
          })
          .where((item) => item.isNotEmpty)
          .toList();
      return parts.join('\n');
    }

    final text = value.toString().trim();
    if (text.isEmpty ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'undefined') {
      return '';
    }
    return text;
  }

  static const Set<String> _historyDateKeys = <String>{
    'datetime',
    'date',
    'time',
    'createdAt',
    'updatedAt',
    'registrationDate',
    'administrationDate',
    'dateReported',
    'followup',
    'lmpDate',
    'eddDate',
    'dueDate',
    'expirationDate',
    'nextDoseDueDate',
  };

  static const Set<String> _historyDateTimeKeys = <String>{
    'datetime',
    'createdAt',
    'updatedAt',
  };

  static Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    Color accentColor = _primaryAqua,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _historyBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: _historyMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _historyDetailBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildCountTile(
    String label,
    String value, {
    IconData? icon,
    Color? accentColor,
  }) {
    final resolvedAccent = accentColor ?? _primaryAqua;
    final resolvedIcon = icon ?? _timelineModuleIcon(label);

    return Container(
      width: 154,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _historyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: resolvedAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(resolvedIcon, color: resolvedAccent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              color: _historyMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _historyDetailBlue,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSectionPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _historyBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _historyText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _historyDetailBlue,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  static Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _historySoftBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _historyBorder),
      ),
      child: Text(
        message,
        style: TextStyle(color: _historyMuted, fontSize: 13),
      ),
    );
  }

  static Widget _buildDetailTable(
    List<MapEntry<String, String>> entries, {
    required Color accentColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _historySurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _historyBorder),
          ),
          child: Table(
            columnWidths: isCompact
                ? const {0: FixedColumnWidth(140), 1: FlexColumnWidth()}
                : const {0: FixedColumnWidth(260), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(
              horizontalInside: BorderSide(color: _historyBorder),
            ),
            children: entries
                .map(
                  (entry) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 18, 16),
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: _historyDetailBlue,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  static Widget _buildTimelineEventCard(
    BuildContext dialogContext,
    PatientTimelineEvent event, {
    required Color accentColor,
    required IconData moduleIcon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showTimelineEventDetailsDialog(
          context: dialogContext,
          event: event,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _historySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _historyBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(moduleIcon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              color: _historyText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor.withValues(alpha: 0.22),
                                accentColor.withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            event.eventDate == null
                                ? 'No date'
                                : _formatDate(event.eventDate!),
                            style: const TextStyle(
                              color: _historyDetailBlue,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.recordId.isEmpty
                                ? event.module
                                : 'Record ID: ${event.recordId}',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.open_in_new_rounded,
                          color: _historyDetailBlue,
                          size: 16,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.subtitle,
                      style: TextStyle(
                        color: _historyDetailBlue,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _timelineModuleColor(String module) {
    switch (module) {
      case 'Check Up':
        return const Color(0xFF4DD0E1);
      case 'Prenatal':
        return const Color(0xFFFFB74D);
      case 'Immunization':
        return const Color(0xFF81C784);
      case 'Communicable':
        return const Color(0xFFE57373);
      case 'Non-Communicable':
        return const Color(0xFFBA68C8);
      case 'Mortality':
        return const Color(0xFF90A4AE);
      case 'Morbidity':
        return const Color(0xFF64B5F6);
      default:
        return _primaryAqua;
    }
  }

  static String _formatAiRecoveryPlanValue(dynamic value) {
    final decodedPlan = _decodeAiRecoveryPlan(value);
    if (decodedPlan != null) {
      final sections = <String>[];

      void addListSection(String title, dynamic source) {
        final items = _detailStringList(source);
        if (items.isEmpty) {
          return;
        }

        sections.add('$title:\n${items.map((item) => '• $item').join('\n')}');
      }

      final estimatedRecovery = _formatDetailValue(
        decodedPlan['estimated_recovery'],
      );
      if (estimatedRecovery.isNotEmpty) {
        sections.add('Estimated Recovery:\n$estimatedRecovery');
      }

      addListSection('Home Care', decodedPlan['home_care']);
      addListSection('Precautions', decodedPlan['precautions']);
      addListSection('General Advice', decodedPlan['general_advice']);

      if (sections.isNotEmpty) {
        return sections.join('\n\n');
      }
    }

    return _normalizeRecoveryPlanText(value?.toString() ?? '');
  }

  static Map<String, dynamic>? _decodeAiRecoveryPlan(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    final text = value.toString().trim();
    if (text.isEmpty ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'undefined') {
      return null;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return null;
  }

  static List<String> _detailStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => _formatDetailValue(item))
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final formatted = _formatDetailValue(value);
    if (formatted.isEmpty) {
      return const [];
    }

    return formatted
        .split(RegExp(r'\r?\n+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _normalizeRecoveryPlanText(String text) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();

    if (normalized.isEmpty ||
        normalized.toLowerCase() == 'null' ||
        normalized.toLowerCase() == 'undefined') {
      return '';
    }

    final lines = normalized
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length > 1) {
      return lines
          .map(
            (line) =>
                line.startsWith('•') || line.contains(':') ? line : '• $line',
          )
          .join('\n');
    }

    final compact = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sentences = compact
        .split(RegExp(r'(?<=[.!?])\s+|;\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (sentences.length > 1) {
      return sentences.map((sentence) => '• $sentence').join('\n');
    }

    return compact;
  }

  static IconData _timelineModuleIcon(String module) {
    switch (module) {
      case 'Check Up':
        return Icons.medical_services_outlined;
      case 'Prenatal':
        return Icons.pregnant_woman_outlined;
      case 'Immunization':
        return Icons.vaccines_outlined;
      case 'Communicable':
        return Icons.coronavirus_outlined;
      case 'Non-Communicable':
        return Icons.monitor_heart_outlined;
      case 'Mortality':
        return Icons.history_toggle_off_rounded;
      case 'Morbidity':
        return Icons.healing_outlined;
      default:
        return Icons.medical_information_outlined;
    }
  }

  static DateTime? _firstDate(Map<String, dynamic> record, List<String> keys) {
    for (final key in keys) {
      final parsed = _tryParseHistoryDate(record[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime? _tryParseHistoryDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;

    try {
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Continue with serialized Firestore timestamp and ISO-date fallbacks.
    }

    if (value is num) {
      final integer = value.toInt();
      return integer.abs() > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(integer)
          : DateTime.fromMillisecondsSinceEpoch(integer * 1000);
    }

    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round() +
              (nanoseconds is num ? (nanoseconds / 1000000).round() : 0),
        );
      }
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;

    final serializedTimestamp = RegExp(
      r'seconds\s*[=:]\s*(-?\d+)(?:.*nanoseconds\s*[=:]\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(text);
    final seconds = int.tryParse(serializedTimestamp?.group(1) ?? '');
    if (seconds == null) return null;
    final nanoseconds = int.tryParse(serializedTimestamp?.group(2) ?? '') ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000) + (nanoseconds ~/ 1000000),
    );
  }

  static String _patientName(Map<String, dynamic> record) {
    return _safeText(
      record['patientName'],
      fallback: _safeText(
        record['patient'],
        fallback: _safeText(record['name'], fallback: 'Unknown Patient'),
      ),
    );
  }

  static String _patientId(Map<String, dynamic> record) {
    return _safeText(
      record['linkedPatientId'],
      fallback: _safeText(record['patientId']),
    );
  }

  static String _buildPatientName(Map<String, dynamic> patient) {
    final firstName = _safeText(patient['firstName']);
    final surname = _safeText(patient['surname']);
    final combined = '$firstName $surname'.trim();
    if (combined.isNotEmpty) {
      return combined;
    }
    return _patientName(patient);
  }

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _formatTimestamp(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute:$second';
  }

  static String _normalize(dynamic value) {
    return _safeText(value).toLowerCase();
  }

  static String _safeText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
