import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

class PatientHistoryDialogs {
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _secondaryIceBlue = AppDesign.blueSoft;
  static const Color _darkDeepTeal = AppDesign.surface;
  static const Color _lightOffWhite = AppDesign.ink;
  static const Color _mutedCoolGray = AppDesign.muted;

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

  // ─── Design tokens for the light-mode Check Up History screen ───────────
  static const Color _histBg        = Color(0xFFF8FAFC); // page background
  static const Color _histSurface   = Color(0xFFFFFFFF); // card surface
  static const Color _histAccent    = Color(0xFF2563EB); // primary blue
  static const Color _histText      = Color(0xFF0F172A); // navy dark
  static const Color _histMuted     = Color(0xFF64748B); // slate muted
  static const Color _histBorder    = Color(0xFFE2E8F0); // card border
  static const Color _histGreenBg   = Color(0xFFD1FAE5); // completed badge bg
  static const Color _histGreenFg   = Color(0xFF065F46); // completed badge text
  static const Color _histBlueBg    = Color(0xFFDBEAFE); // scheduled badge bg
  static const Color _histBlueFg    = Color(0xFF1D4ED8); // scheduled badge text

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
    final patientName  = _patientName(latestRecord);
    final patientId    = _patientId(latestRecord);
    final latestDate   = _firstDate(latestRecord, dateKeys);
    final initials     = _buildInitials(patientName);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: fullScreen
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: fullScreen ? double.infinity : 480,
              maxHeight: fullScreen
                  ? MediaQuery.of(dialogContext).size.height
                  : MediaQuery.of(dialogContext).size.height * 0.92,
            ),
            width:  fullScreen ? double.infinity : null,
            height: fullScreen ? double.infinity : null,
            decoration: BoxDecoration(
              color: _histBg,
              borderRadius: BorderRadius.circular(fullScreen ? 0 : 20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Zone 1 · Header bar ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: _histSurface,
                    border: Border(bottom: BorderSide(color: _histBorder)),
                    borderRadius: fullScreen
                        ? BorderRadius.zero
                        : const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Accent top strip
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                          ),
                          borderRadius: fullScreen
                              ? BorderRadius.zero
                              : const BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: _histText,
                                size: 22,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '$moduleTitle History',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _histText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            // Spacer to balance the back button
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable body ──────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Zone 2 · Patient profile header ─────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          color: _histSurface,
                          child: Row(
                            children: [
                              // Avatar circle
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: _histAccent,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patientName,
                                      style: const TextStyle(
                                        color: _histText,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    // Patient ID pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _histBlueBg,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        patientId.isEmpty
                                            ? 'Patient ID: —'
                                            : 'Patient ID: #$patientId',
                                        style: const TextStyle(
                                          color: _histBlueFg,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ── Zone 3 · Summary banner ──────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _histSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _histBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  _buildMetricCell(
                                    label: 'Total Visits',
                                    value: '${history.length}',
                                    icon: Icons.favorite_border_rounded,
                                    iconColor: _histAccent,
                                  ),
                                  VerticalDivider(
                                    color: _histBorder,
                                    width: 1,
                                    thickness: 1,
                                  ),
                                  _buildMetricCell(
                                    label: 'Last Update',
                                    value: latestDate == null
                                        ? 'No date'
                                        : _formatHumanDate(latestDate),
                                    icon: Icons.calendar_today_rounded,
                                    iconColor: const Color(0xFF7C3AED),
                                  ),
                                  VerticalDivider(
                                    color: _histBorder,
                                    width: 1,
                                    thickness: 1,
                                  ),
                                  _buildMetricCell(
                                    label: 'Status',
                                    value: 'Active Patient',
                                    icon: Icons.verified_rounded,
                                    iconColor: const Color(0xFF059669),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Zone 4 · Timeline feed ───────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Visit Timeline',
                            style: TextStyle(
                              color: _histText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (history.isEmpty)
                          _buildLightEmptyState(
                            emptyMessage ??
                                'No previous records were found for this patient.',
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: List.generate(history.length, (index) {
                                final record = history[index];
                                final title    = titleBuilder?.call(record) ?? _patientName(record);
                                final subtitle = subtitleBuilder?.call(record) ?? 'Visit ${index + 1}';
                                final date     = _firstDate(record, dateKeys);
                                final isLast   = index == history.length - 1;
                                final statusRaw = (record['status'] ?? record['ai_category'] ?? '').toString().toLowerCase();
                                final isCompleted = statusRaw.contains('complete');
                                final rawSymptoms = record['symptoms']?.toString() ?? '';

                                return IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [

                                      // Timeline spine
                                      SizedBox(
                                        width: 24,
                                        child: Column(
                                          children: [
                                            // Status dot
                                            Container(
                                              width: 14,
                                              height: 14,
                                              margin: const EdgeInsets.only(top: 18),
                                              decoration: BoxDecoration(
                                                color: isCompleted
                                                    ? const Color(0xFF059669)
                                                    : _histAccent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: (isCompleted
                                                            ? const Color(0xFF059669)
                                                            : _histAccent)
                                                        .withValues(alpha: 0.35),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Connector line
                                            if (!isLast)
                                              Expanded(
                                                child: Container(
                                                  width: 2,
                                                  margin: const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        _histBorder,
                                                        _histBorder.withValues(alpha: 0.3),
                                                      ],
                                                      begin: Alignment.topCenter,
                                                      end: Alignment.bottomCenter,
                                                    ),
                                                    borderRadius: BorderRadius.circular(1),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(width: 10),

                                      // Visit card
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: onOpenRecord == null
                                              ? null
                                              : () => onOpenRecord(record),
                                          child: Container(
                                            margin: EdgeInsets.only(
                                              bottom: isLast ? 0 : 10,
                                            ),
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: _histSurface,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: _histBorder),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.04),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [

                                                // Top row: timestamp + status badge
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        date == null
                                                            ? 'No date'
                                                            : _formatHumanTimestamp(date),
                                                        style: TextStyle(
                                                          color: _histMuted,
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    // Status badge
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isCompleted
                                                            ? _histGreenBg
                                                            : _histBlueBg,
                                                        borderRadius:
                                                            BorderRadius.circular(999),
                                                      ),
                                                      child: Text(
                                                        isCompleted
                                                            ? 'Completed'
                                                            : 'Scheduled',
                                                        style: TextStyle(
                                                          color: isCompleted
                                                              ? _histGreenFg
                                                              : _histBlueFg,
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                const SizedBox(height: 8),

                                                // Visit title (ai_category / status)
                                                Text(
                                                  title,
                                                  style: const TextStyle(
                                                    color: _histText,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),

                                                const SizedBox(height: 4),

                                                // Subtitle (symptoms label)
                                                Text(
                                                  subtitle,
                                                  style: TextStyle(
                                                    color: _histMuted,
                                                    fontSize: 12,
                                                    height: 1.4,
                                                  ),
                                                ),

                                                // Symptom chips
                                                if (rawSymptoms.isNotEmpty) ...[
                                                  const SizedBox(height: 10),
                                                  _buildSymptomChips(rawSymptoms),
                                                ],

                                                // View Details link
                                                if (onOpenRecord != null) ...[
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        'View Details',
                                                        style: const TextStyle(
                                                          color: _histAccent,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 2),
                                                      const Icon(
                                                        Icons.chevron_right_rounded,
                                                        color: _histAccent,
                                                        size: 16,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ── Zone 5 · Sticky bottom action bar ───────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: _histSurface,
                    border: Border(top: BorderSide(color: _histBorder)),
                    borderRadius: fullScreen
                        ? BorderRadius.zero
                        : const BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary CTA
                      if (onAddAnother != null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onAddAnother();
                            },
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: Text(
                              addButtonLabel ?? 'Add Another Record',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _histAccent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),

                      if (onAddAnother != null && onSecondaryAction != null)
                        const SizedBox(height: 10),

                      // Secondary outlined CTA
                      if (onSecondaryAction != null)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onSecondaryAction();
                            },
                            icon: const Icon(Icons.timeline_rounded, size: 18),
                            label: Text(
                              secondaryActionLabel ?? 'Medical History Records',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _histAccent,
                              side: const BorderSide(
                                color: Color(0xFF2563EB),
                                width: 1.5,
                              ),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A single metric cell for the summary banner.
  static Widget _buildMetricCell({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _histText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _histMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Light-mode empty state for the timeline.
  static Widget _buildLightEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _histSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _histBorder),
        ),
        child: Column(
          children: [
            Icon(
              Icons.inbox_rounded,
              color: _histMuted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _histMuted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
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
                          color: AppDesign.ink.withValues(alpha: 0.12),
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
                                color: AppDesign.ink.withValues(alpha: 0.94),
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
                                color: AppDesign.ink.withValues(alpha: 0.72),
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
                          color: AppDesign.ink.withValues(alpha: 0.84),
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
                            color: AppDesign.ink.withValues(alpha: 0.68),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (snapshot.timeline.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppDesign.blueSoft,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
                            ),
                            child: Text(
                              'No linked module history was found for this patient yet.',
                              style: TextStyle(
                                color: AppDesign.ink.withValues(alpha: 0.72),
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
                          color: AppDesign.ink.withValues(alpha: 0.12),
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
                                color: AppDesign.ink.withValues(alpha: 0.92),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (patientName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                patientName,
                                style: TextStyle(
                                  color: AppDesign.ink.withValues(alpha: 0.72),
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
                          color: AppDesign.ink.withValues(alpha: 0.84),
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
        color: AppDesign.blueSoft,
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
                  color: AppDesign.ink.withValues(alpha: 0.62),
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
              color: AppDesign.ink.withValues(alpha: 0.64),
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
        color: AppDesign.blueSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppDesign.ink.withValues(alpha: 0.72),
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
            color: AppDesign.blueSoft.withValues(alpha: 0.65),
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
                color: AppDesign.blueSoft,
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
                            color: AppDesign.ink.withValues(alpha: 0.86),
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
        color: AppDesign.blueSoft,
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
                        color: AppDesign.ink.withValues(alpha: 0.66),
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
              color: AppDesign.blueSoft.withValues(alpha: 0.65),
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
                              color: AppDesign.ink.withValues(alpha: 0.68),
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
                            color: AppDesign.ink.withValues(alpha: 0.55),
                            size: 16,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.subtitle,
                        style: TextStyle(
                          color: AppDesign.ink.withValues(alpha: 0.74),
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

  /// Returns a human-readable date string, e.g. "Aug 6, 2026".
  static String _formatHumanDate(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  /// Returns a human-readable timestamp, e.g. "Aug 6, 2026 • 5:00 PM".
  static String _formatHumanTimestamp(DateTime value) {
    final datePart = _formatHumanDate(value);
    final hour12   = value.hour == 0
        ? 12
        : value.hour > 12
            ? value.hour - 12
            : value.hour;
    final ampm   = value.hour < 12 ? 'AM' : 'PM';
    final minute = value.minute.toString().padLeft(2, '0');
    return '$datePart \u2022 $hour12:$minute $ampm';
  }

  /// Derives 1-2 uppercase initials from a patient name.
  static String _buildInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Renders symptom tokens as soft pill chips.
  static Widget _buildSymptomChips(String rawSymptoms) {
    final tokens = rawSymptoms
        .split(RegExp(r'[,;|]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(6)
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tokens.map((token) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Text(
            token,
            style: const TextStyle(
              color: Color(0xFF1D4ED8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
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
