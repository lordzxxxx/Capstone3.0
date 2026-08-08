import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';

class PatientHistoryDialogs {
  static const Color _primaryAqua = Color(0xFF00A8B5);
  static const Color _secondaryIceBlue = Color(0xFF1E5A7A);
  static const Color _darkDeepTeal = Color(0xFF0A1F24);
  static const Color _lightOffWhite = Color(0xFFF5F5F5);
  static const Color _mutedCoolGray = Color(0xFF546E7A);

  static List<Map<String, dynamic>> collectHistory({
    required Map<String, dynamic> seedRecord,
    required List<Map<String, dynamic>> records,
    List<String> idKeys = const ['linkedPatientId', 'patientId'],
    List<String> nameKeys = const ['patientName', 'patient', 'name'],
    List<String> sortDateKeys = const ['dateReported', 'registrationDate', 'datetime', 'date'],
  }) {
    final seedIdentifiers = <String>{
      for (final key in idKeys) _normalize(seedRecord[key]),
    }..removeWhere((value) => value.isEmpty);

    final seedNames = <String>{
      for (final key in nameKeys) _normalize(seedRecord[key]),
    }..removeWhere((value) => value.isEmpty);

    final history = records.where((record) {
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
    }).map((record) => Map<String, dynamic>.from(record)).toList();

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
    List<String> dateKeys = const ['dateReported', 'registrationDate', 'datetime', 'date'],
    VoidCallback? onAddAnother,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    void Function(Map<String, dynamic> record)? onOpenRecord,
    bool fullScreen = false,
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
          insetPadding: fullScreen
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: fullScreen ? double.infinity : 760,
              maxHeight: fullScreen
                  ? MediaQuery.of(dialogContext).size.height
                  : MediaQuery.of(dialogContext).size.height * 0.84,
            ),
            width: fullScreen ? double.infinity : null,
            height: fullScreen ? double.infinity : null,
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(fullScreen ? 0 : 24),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.14)),
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
                    gradient: const LinearGradient(
                      colors: [_darkDeepTeal, _secondaryIceBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: fullScreen
                        ? BorderRadius.zero
                        : const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: _lightOffWhite,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
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
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description ??
                                  'Review previous records first, then add the next visit for the same patient.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
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
                          color: Colors.white.withValues(alpha: 0.84),
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
                        value: latestDate == null ? 'No date' : _formatDate(latestDate),
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
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: history.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final record = history[index];
                              final title = titleBuilder?.call(record) ?? _patientName(record);
                              final subtitle = subtitleBuilder?.call(record) ?? 'Record ${index + 1}';
                              final meta = metaBuilder?.call(record) ?? '';
                              final date = _firstDate(record, dateKeys);
                              return InkWell(
                                onTap: onOpenRecord == null ? null : () => onOpenRecord(record),
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: _lightOffWhite.withValues(alpha: 0.08),
                                    ),
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
                                                  title,
                                                  style: const TextStyle(
                                                    color: _lightOffWhite,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  subtitle,
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.76),
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
                                              color: _primaryAqua.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              date == null ? 'No date' : _formatDate(date),
                                              style: const TextStyle(
                                                color: _primaryAqua,
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
                                            color: Colors.white.withValues(alpha: 0.66),
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
                      final actionCount =
                          1 +
                          (onSecondaryAction == null ? 0 : 1) +
                          (onAddAnother == null ? 0 : 1);
                      final isStacked = constraints.maxWidth < 620;
                      final buttonWidth = isStacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - (12 * (actionCount - 1))) /
                                actionCount;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          if (onAddAnother != null)
                            SizedBox(
                              width: buttonWidth,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  onAddAnother();
                                },
                                icon: const Icon(Icons.add_rounded),
                                label: Text(
                                  addButtonLabel ?? 'Add Another Record',
                                  textAlign: TextAlign.center,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryAqua,
                                  foregroundColor: _darkDeepTeal,
                                  minimumSize: const Size.fromHeight(50),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          if (onSecondaryAction != null)
                            SizedBox(
                              width: buttonWidth,
                              child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onSecondaryAction();
                            },
                            icon: const Icon(Icons.timeline_rounded),
                            label: Text(
                              secondaryActionLabel ?? 'Open Medical History',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryAqua,
                              side: BorderSide(
                                color: _primaryAqua.withValues(alpha: 0.35),
                              ),
                                  minimumSize: const Size.fromHeight(50),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                            ),
                          ),
                            ),
                          SizedBox(
                            width: buttonWidth,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Close'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _lightOffWhite,
                                side: BorderSide(
                                  color: _lightOffWhite.withValues(alpha: 0.2),
                                ),
                                minimumSize: const Size.fromHeight(50),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
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
    final patientName = _buildPatientName(patient);
    final patientId = _safeText(patient['patientId']);
    final groupedTimeline = _groupTimelineByModule(snapshot.timeline);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_darkDeepTeal, _secondaryIceBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.timeline_rounded,
                          color: _lightOffWhite,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patient Health History',
                              style: TextStyle(
                                color: _lightOffWhite,
                              fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              patientName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.94),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              patientId.isEmpty
                                  ? 'Cross-module history overview'
                                  : 'Patient ID: $patientId',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildCountTile('Total Records', '${snapshot.totalRecords}'),
                            _buildCountTile('Check Up', '${snapshot.checkUpHistory.length}'),
                            _buildCountTile('Prenatal', '${snapshot.prenatalHistory.length}'),
                            _buildCountTile('Immunization', '${snapshot.immunizationHistory.length}'),
                            _buildCountTile('Communicable', '${snapshot.communicableHistory.length}'),
                            _buildCountTile('Non-Communicable', '${snapshot.nonCommunicableHistory.length}'),
                            _buildCountTile('Mortality', '${snapshot.mortalityHistory.length}'),
                            _buildCountTile('Morbidity', '${snapshot.morbidityHistory.length}'),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Timeline by Category',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'History is grouped by category. Tap a timeline entry to open the complete record details for that visit.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (snapshot.timeline.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
                            ),
                            child: Text(
                              'No linked module history was found for this patient yet.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          Column(
                            children: groupedTimeline
                                .map(
                                  (group) => _buildTimelineCategorySection(
                                    dialogContext,
                                    group.key,
                                    group.value,
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _lightOffWhite,
                        side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
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
        final accentColor = _primaryAqua;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_darkDeepTeal, _secondaryIceBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: _lightOffWhite,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${event.module} Details',
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              event.title,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (patientName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                patientName,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildSummaryChip(
                              icon: Icons.category_outlined,
                              label: 'Module',
                              value: event.module,
                            ),
                            _buildSummaryChip(
                              icon: Icons.event_outlined,
                              label: 'Event Timestamp',
                              value: event.eventDate == null
                                  ? 'No timestamp'
                                  : _formatTimestamp(event.eventDate!),
                            ),
                            _buildSummaryChip(
                              icon: Icons.badge_outlined,
                              label: 'Record ID',
                              value: recordId,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (resolvedEntries.isEmpty)
                          _buildEmptyState(
                            'No additional details were stored for this timeline record.',
                          )
                        else
                          _buildDetailTable(
                            resolvedEntries,
                            accentColor: accentColor,
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _lightOffWhite,
                        side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
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
      if (!record.containsKey(key) || _hiddenDetailKeys.contains(key)) {
        return;
      }

      final label = _labelForKey(key);
      final normalizedLabel = label.toLowerCase();
      if (!usedLabels.add(normalizedLabel)) {
        return;
      }

      final value = _formatDetailValue(record[key]);
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
          'plan',
          'remarks',
          'followup',
          'ai_category',
          'ai_severity',
          'ai_confidence',
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
      _safeText(record['vitalsigns'], fallback: _safeText(record['vitalSigns'])),
    );
    addEntry('Plan', _safeText(record['plan']));

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
      'ai_confidence': 'AI Confidence',
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

  static String _formatDetailValue(dynamic value) {
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

  static Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryAqua, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _lightOffWhite,
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

  static Widget _buildCountTile(String label, String value) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _primaryAqua.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.64),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 13,
        ),
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
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
          ),
          child: Table(
            columnWidths: isCompact
                ? const {
                    0: FixedColumnWidth(140),
                    1: FlexColumnWidth(),
                  }
                : const {
                    0: FixedColumnWidth(240),
                    1: FlexColumnWidth(),
                  },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(
              horizontalInside: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            children: entries
                .map(
                  (entry) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                        padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 13,
                            height: 1.45,
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

  static List<MapEntry<String, List<PatientTimelineEvent>>> _groupTimelineByModule(
    List<PatientTimelineEvent> timeline,
  ) {
    const orderedModules = <String>[
      'Check Up',
      'Prenatal',
      'Immunization',
      'Communicable',
      'Non-Communicable',
      'Mortality',
      'Morbidity',
    ];

    final grouped = <String, List<PatientTimelineEvent>>{};

    for (final module in orderedModules) {
      final events = timeline.where((event) => event.module == module).toList();
      if (events.isNotEmpty) {
        grouped[module] = events;
      }
    }

    for (final event in timeline) {
      if (grouped.containsKey(event.module)) {
        continue;
      }
      grouped[event.module] = timeline
          .where((timelineEvent) => timelineEvent.module == event.module)
          .toList();
    }

    return grouped.entries.toList();
  }

  static Widget _buildTimelineCategorySection(
    BuildContext dialogContext,
    String module,
    List<PatientTimelineEvent> events,
  ) {
    final accentColor = _primaryAqua;
    final moduleIcon = _timelineModuleIcon(module);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(moduleIcon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$module History',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${events.length} ${events.length == 1 ? 'record' : 'records'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...events.map(
            (event) => _buildTimelineEventCard(
              dialogContext,
              event,
              accentColor: accentColor,
              moduleIcon: moduleIcon,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTimelineEventCard(
    BuildContext dialogContext,
    PatientTimelineEvent event, {
    required Color accentColor,
    required IconData moduleIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
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
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
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
                                color: _lightOffWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            event.eventDate == null
                                ? 'No date'
                                : _formatDate(event.eventDate!),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
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
                            color: Colors.white.withValues(alpha: 0.55),
                            size: 16,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.74),
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
      final value = _safeText(record[key]);
      if (value.isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static String _patientName(Map<String, dynamic> record) {
    return _safeText(
      record['patientName'],
      fallback: _safeText(record['patient'], fallback: _safeText(record['name'], fallback: 'Unknown Patient')),
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
