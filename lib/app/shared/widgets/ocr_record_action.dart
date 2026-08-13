import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

typedef OcrRecordCallback = Future<void> Function(OcrExtraction extraction);

/// A normalized OCR field with an explicit confidence value.
///
/// Google ML Kit exposes line/element confidence on Android and may return
/// null on iOS. The parser therefore combines the ML Kit value with content
/// validation. Values below [OcrExtraction.manualReviewThreshold] are never
/// silently treated as trusted form data.
class OcrFieldValue {
  const OcrFieldValue({
    required this.key,
    required this.value,
    required this.confidence,
    this.source = '',
  });

  final String key;
  final String value;
  final double confidence;
  final String source;

  bool get requiresManualReview =>
      value.trim().isEmpty || confidence < OcrExtraction.manualReviewThreshold;

  OcrFieldValue copyWith({String? value, double? confidence}) => OcrFieldValue(
    key: key,
    value: value ?? this.value,
    confidence: confidence ?? this.confidence,
    source: source,
  );
}

/// Structured, reviewable OCR output passed into the mobile forms.
class OcrExtraction {
  const OcrExtraction({
    required this.rawText,
    required this.fields,
    required this.overallConfidence,
  });

  static const double manualReviewThreshold = 0.75;

  final String rawText;
  final Map<String, OcrFieldValue> fields;
  final double overallConfidence;

  Iterable<OcrFieldValue> get manualReviewFields =>
      fields.values.where((field) => field.requiresManualReview);

  /// Only validated/high-confidence fields are sent as initial form values.
  /// Low-confidence values remain visible in the OCR review dialog and must
  /// be entered or corrected manually in the form.
  Map<String, dynamic> toFormSeed() {
    final seed = <String, dynamic>{
      '_ocrRawText': rawText,
      '_ocrNeedsManualReview': manualReviewFields
          .map((field) => field.key)
          .toList(growable: false),
    };
    for (final field in fields.values) {
      if (!field.requiresManualReview && field.value.trim().isNotEmpty) {
        seed[field.key] = field.value.trim();
      }
    }
    final fullName = seed['fullName']?.toString();
    if (fullName != null && fullName.isNotEmpty) {
      seed['patientName'] = fullName;
    }
    return seed;
  }

  OcrExtraction copyWithFields(Map<String, OcrFieldValue> nextFields) {
    final valid = nextFields.values
        .where((field) => !field.requiresManualReview)
        .map((field) => field.confidence)
        .toList(growable: false);
    final confidence = valid.isEmpty
        ? overallConfidence
        : valid.reduce((a, b) => a + b) / valid.length;
    return OcrExtraction(
      rawText: rawText,
      fields: Map.unmodifiable(nextFields),
      overallConfidence: confidence,
    );
  }

  /// Parses labels and values by semantic content, never by image position.
  /// This is also used by tests and by iOS, where ML Kit confidence can be
  /// unavailable.
  factory OcrExtraction.fromText(
    String text, {
    Map<String, double> lineConfidence = const <String, double>{},
  }) {
    final rawLines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final lines = rawLines
        .map(_normalizeOcrLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final values = <String, OcrFieldValue>{};

    void addField(String key, String value, double confidence, String source) {
      final normalized = _normalizeValue(key, value);
      if (normalized.isEmpty) return;
      final validated = _validateField(key, normalized);
      final adjusted = validated ? confidence : confidence * 0.45;
      final current = values[key];
      if (current == null || adjusted > current.confidence) {
        values[key] = OcrFieldValue(
          key: key,
          value: normalized,
          confidence: adjusted.clamp(0.0, 1.0).toDouble(),
          source: source,
        );
      }
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final rawLine = index < rawLines.length ? rawLines[index] : line;
      final confidence =
          (lineConfidence[rawLine] ?? lineConfidence[line] ?? 0.78).clamp(
            0.0,
            1.0,
          );
      _extractLabelValue(line, confidence.toDouble(), addField);
      // Forms frequently place a label on one line and its value on the next.
      // Join only when the current line is a known label without a value, so
      // ordinary multi-line addresses and notes are not guessed together.
      if (_isLabelOnlyLine(line) && index + 1 < lines.length) {
        final nextLine = lines[index + 1];
        if (!_looksLikeLabel(nextLine)) {
          _extractLabelValue(
            '$line: $nextLine',
            (confidence * 0.9).clamp(0.0, 1.0).toDouble(),
            addField,
          );
        }
      }
    }

    final allText = lines.join('\n');
    void addGlobal(String key, RegExp pattern, {double confidence = 0.62}) {
      final match = pattern.firstMatch(allText);
      if (match != null) {
        addField(
          key,
          match.group(1) ?? match.group(0) ?? '',
          confidence,
          'content match',
        );
      }
    }

    if (!values.containsKey('email')) {
      addGlobal(
        'email',
        RegExp(
          r'([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})',
          caseSensitive: false,
        ),
      );
    }
    if (!values.containsKey('contactNumber')) {
      addGlobal(
        'contactNumber',
        RegExp(r'((?:\+?63|0|9)[\s().-]*\d[\d\s().-]{7,14}\d)'),
      );
    }
    if (!values.containsKey('dateOfBirth')) {
      addGlobal(
        'dateOfBirth',
        RegExp(
          r'\b(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4})\b',
          caseSensitive: false,
        ),
      );
    }

    final confidenceValues = values.values
        .map((field) => field.confidence)
        .toList(growable: false);
    final overall = confidenceValues.isEmpty
        ? 0.0
        : confidenceValues.reduce((a, b) => a + b) / confidenceValues.length;
    return OcrExtraction(
      rawText: text.trim(),
      fields: Map.unmodifiable(values),
      overallConfidence: overall,
    );
  }

  factory OcrExtraction.fromRecognizedText(RecognizedText result) {
    final lineConfidence = <String, double>{};
    for (final block in result.blocks) {
      for (final line in block.lines) {
        if (line.confidence != null) {
          lineConfidence[line.text.trim()] = line.confidence!.clamp(0.0, 1.0);
        }
      }
    }
    return OcrExtraction.fromText(result.text, lineConfidence: lineConfidence);
  }

  static void _extractLabelValue(
    String line,
    double confidence,
    void Function(String key, String value, double confidence, String source)
    addField,
  ) {
    final patterns = <String, RegExp>{
      'firstName': _labelPattern(r'first\s*name'),
      'surname': _labelPattern(r'(?:surname|last\s*name|family\s*name)'),
      'fullName': _labelPattern(r'(?:full\s*name|patient\s*name|name)'),
      'dateOfBirth': _labelPattern(
        r'(?:date\s*of\s*birth|birth\s*date|dob|birthday)',
      ),
      'address': _labelPattern(r'(?:residential\s*)?address'),
      'barangay': _labelPattern(r'(?:barangay|brgy)'),
      'patientId': _labelPattern(
        r'(?:patient\s*(?:id|no|number)|record\s*(?:id|no|number)|identification|id)',
      ),
      'contactNumber': _labelPattern(
        r'(?:contact|phone|mobile|telephone)(?:\s*(?:number|no))?',
      ),
      'email': _labelPattern(r'(?:email|e-mail)'),
      'age': _labelPattern(r'age'),
      'gender': _labelPattern(r'(?:sex|gender)'),
      'symptoms': _labelPattern(r'(?:symptoms?|chief\s*complaint)'),
      'disease': _labelPattern(r'(?:disease|diagnosis|condition)'),
      'bloodPressure': _labelPattern(r'(?:blood\s*pressure|bp)'),
      'temperature': _labelPattern(r'(?:temperature|temp)'),
      'heartRate': _labelPattern(r'(?:heart\s*rate|pulse|hr)'),
      'respiratoryRate': _labelPattern(r'(?:respiratory\s*rate|rr)'),
      'oxygenSaturation': _labelPattern(r'(?:oxygen\s*saturation|spo2|o2)'),
      'weight': _labelPattern(r'weight'),
      'height': _labelPattern(r'height'),
      'vaccine': _labelPattern(r'(?:vaccine|immunization)'),
      'cause': _labelPattern(r'(?:cause(?:\s*of\s*death)?|death\s*cause)'),
      'place': _labelPattern(r'(?:place|location)'),
    };
    for (final entry in patterns.entries) {
      final match = entry.value.firstMatch(line);
      if (match != null) {
        addField(entry.key, match.group(1)!, confidence, 'label: ${entry.key}');
        return;
      }
    }
  }

  static RegExp _labelPattern(String labels) {
    return RegExp(
      r'^\s*(?:' + labels + r')(?:\s*[:#-]\s*|\s+)(.+)$',
      caseSensitive: false,
    );
  }

  static String _normalizeOcrLine(String line) {
    var normalized = line
        .replaceAll('\uFF1A', ':')
        .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    normalized = normalized
        .replaceFirst(RegExp(r'^brgy\.?\s+', caseSensitive: false), 'Barangay ')
        .replaceFirst(
          RegExp(r'^dateofbirth\b', caseSensitive: false),
          'Date of Birth',
        )
        .replaceFirst(
          RegExp(r'^patientname\b', caseSensitive: false),
          'Patient Name',
        )
        .replaceFirst(RegExp(r'^fullname\b', caseSensitive: false), 'Full Name')
        .replaceFirst(
          RegExp(r'^contactnumber\b', caseSensitive: false),
          'Contact Number',
        )
        .replaceFirst(
          RegExp(r'^bloodpressure\b', caseSensitive: false),
          'Blood Pressure',
        )
        .replaceFirst(
          RegExp(r'^heartrate\b', caseSensitive: false),
          'Heart Rate',
        )
        .replaceFirst(
          RegExp(r'^respiratoryrate\b', caseSensitive: false),
          'Respiratory Rate',
        );
    return normalized;
  }

  static bool _isLabelOnlyLine(String line) {
    return RegExp(
      r'^\s*(?:first\s*name|surname|last\s*name|full\s*name|patient\s*name|name|date\s*of\s*birth|birth\s*date|dob|address|barangay|brgy|patient\s*(?:id|no|number)|record\s*(?:id|no|number)|contact|phone|mobile|telephone|email|age|sex|gender|symptoms?|chief\s*complaint|disease|diagnosis|condition|blood\s*pressure|bp|temperature|temp|heart\s*rate|pulse|hr|respiratory\s*rate|rr|oxygen\s*saturation|spo2|o2|weight|height|vaccine|immunization|cause|place|location)\s*[:#-]?\s*$',
      caseSensitive: false,
    ).hasMatch(line);
  }

  static bool _looksLikeLabel(String line) =>
      _isLabelOnlyLine(line) ||
      RegExp(
        r'^\s*(?:first\s*name|surname|last\s*name|full\s*name|patient\s*name|name|date\s*of\s*birth|dob|address|barangay|patient|record|id|contact|phone|mobile|email|age|sex|gender|symptoms?|diagnosis|condition|vaccine)\b',
        caseSensitive: false,
      ).hasMatch(line);

  static String _normalizeValue(String key, String value) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (key == 'contactNumber') {
      normalized = normalized.replaceAll(RegExp(r'[^+\d]'), '');
      if (normalized.startsWith('+63')) {
        normalized = '0${normalized.substring(3)}';
      } else if (normalized.startsWith('63') && normalized.length == 12) {
        normalized = '0${normalized.substring(2)}';
      } else if (normalized.startsWith('9') && normalized.length == 10) {
        normalized = '0$normalized';
      }
    }
    if (key == 'dateOfBirth' || key == 'date') {
      normalized = _normalizeDate(normalized);
    }
    if (key == 'gender') {
      final lower = normalized.toLowerCase();
      if (lower == 'm' || lower == 'male' || lower == 'man') {
        normalized = 'Male';
      } else if (lower == 'f' || lower == 'female' || lower == 'woman') {
        normalized = 'Female';
      } else if (lower == 'o' ||
          lower == 'other' ||
          lower == 'prefer not to say') {
        normalized = 'Other';
      }
    }
    if (key == 'barangay') {
      normalized = normalized
          .replaceFirst(
            RegExp(r'^brgy\.?\s*', caseSensitive: false),
            'Barangay ',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (RegExp(r'^\d{1,2}$').hasMatch(normalized)) {
        normalized = 'Barangay ${normalized.padLeft(2, '0')}';
      }
    }
    return normalized;
  }

  static String _normalizeDate(String value) {
    final namedMonth = RegExp(
      r'^(?:(\d{1,2})\s+([A-Za-z]+)|([A-Za-z]+)\s+(\d{1,2}),?)\s+(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (namedMonth != null) {
      final monthNames = <String, int>{
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'mar': 3,
        'march': 3,
        'apr': 4,
        'april': 4,
        'may': 5,
        'jun': 6,
        'june': 6,
        'jul': 7,
        'july': 7,
        'aug': 8,
        'august': 8,
        'sep': 9,
        'sept': 9,
        'september': 9,
        'oct': 10,
        'october': 10,
        'nov': 11,
        'november': 11,
        'dec': 12,
        'december': 12,
      };
      final firstPart = namedMonth.group(1);
      final firstMonthName = namedMonth.group(2);
      final secondMonthName = namedMonth.group(3);
      final secondPart = namedMonth.group(4);
      final yearPart = int.tryParse(namedMonth.group(5) ?? '');
      final monthName = (firstMonthName ?? secondMonthName ?? '').toLowerCase();
      final month = monthNames[monthName];
      final day = int.tryParse(firstPart ?? secondPart ?? '');
      if (month != null && day != null && yearPart != null) {
        final year = yearPart < 100 ? 2000 + yearPart : yearPart;
        final date = DateTime.tryParse(
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        );
        if (date != null &&
            date.year == year &&
            date.month == month &&
            date.day == day) {
          return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        }
      }
    }

    final match = RegExp(
      r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})$',
    ).firstMatch(value);
    if (match == null) return value;
    var first = int.tryParse(match.group(1)!);
    var second = int.tryParse(match.group(2)!);
    var third = int.tryParse(match.group(3)!);
    if (first == null || second == null || third == null) return value;
    int year;
    int month;
    int day;
    if (first >= 1000) {
      year = first;
      month = second;
      day = third;
    } else {
      year = third < 100 ? 2000 + third : third;
      if (first > 12) {
        day = first;
        month = second;
      } else {
        month = first;
        day = second;
      }
    }
    final date = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (date == null ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      return value;
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static bool _validateField(String key, String value) {
    switch (key) {
      case 'firstName':
      case 'surname':
      case 'fullName':
        return RegExp(
          r"^[\p{L}][\p{L} .'-]{1,100}$",
          unicode: true,
        ).hasMatch(value);
      case 'barangay':
        return RegExp(
          r"^[\p{L}\d][\p{L}\d .'-]{1,100}$",
          unicode: true,
        ).hasMatch(value);
      case 'email':
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
      case 'contactNumber':
        return RegExp(r'^0\d{9,10}$').hasMatch(value);
      case 'age':
        final age = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
        return age != null && age >= 0 && age <= 130;
      case 'dateOfBirth':
      case 'date':
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
      case 'patientId':
        return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_/#.-]{1,80}$').hasMatch(value);
      default:
        return value.trim().length >= 2;
    }
  }
}

/// Shared mobile record actions. OCR is intentionally an assistive workflow;
/// the existing manual forms remain the source of truth for validation.
class RecordCreationFabGroup extends StatelessWidget {
  const RecordCreationFabGroup({
    super.key,
    required this.moduleLabel,
    required this.manualLabel,
    required this.onManualCreate,
    this.onOcrReady,
    this.accentColor = AppDesign.blue,
    this.foregroundColor = Colors.white,
  });

  final String moduleLabel;
  final String manualLabel;
  final VoidCallback onManualCreate;
  final OcrRecordCallback? onOcrReady;
  final Color accentColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'ocr-$moduleLabel',
          onPressed: () => OcrRecordCapture.start(
            context: context,
            moduleLabel: moduleLabel,
            onOcrReady: onOcrReady ?? (_) async => onManualCreate(),
          ),
          backgroundColor: AppDesign.navy,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('OCR'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'manual-$moduleLabel',
          onPressed: onManualCreate,
          backgroundColor: accentColor,
          foregroundColor: foregroundColor,
          icon: const Icon(Icons.add),
          label: Text(manualLabel),
        ),
      ],
    );
  }
}

class OcrRecordButton extends StatelessWidget {
  const OcrRecordButton({
    super.key,
    required this.moduleLabel,
    required this.onOcrReady,
    this.expanded = true,
  });

  final String moduleLabel;
  final OcrRecordCallback onOcrReady;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: () => OcrRecordCapture.start(
        context: context,
        moduleLabel: moduleLabel,
        onOcrReady: onOcrReady,
      ),
      icon: const Icon(Icons.document_scanner_outlined),
      label: const Text('Create with OCR'),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class OcrRecordCapture {
  OcrRecordCapture._();

  static Future<void> start({
    required BuildContext context,
    required String moduleLabel,
    required OcrRecordCallback onOcrReady,
  }) async {
    if (kIsWeb) {
      _message(
        context,
        'On-device OCR is available in the Android and iOS mobile app.',
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppDesign.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$moduleLabel OCR',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Scan a clear printed form or choose an existing image.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppDesign.blue,
                ),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppDesign.blue,
                ),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    var loadingDialogVisible = false;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 92,
      );
      if (image == null || !context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppDesign.blue),
        ),
      );
      loadingDialogVisible = true;

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      late final OcrExtraction extraction;
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        extraction = OcrExtraction.fromRecognizedText(result);
      } finally {
        await recognizer.close();
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingDialogVisible = false;
      if (extraction.rawText.isEmpty) {
        _message(
          context,
          'No readable text was detected. Retake the photo in better lighting.',
        );
        return;
      }
      await _review(
        context: context,
        moduleLabel: moduleLabel,
        extraction: extraction,
        onOcrReady: onOcrReady,
      );
    } catch (_) {
      if (!context.mounted) return;
      if (loadingDialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _message(context, 'OCR could not read this image. Please try again.');
    }
  }

  static Future<void> _review({
    required BuildContext context,
    required String moduleLabel,
    required OcrExtraction extraction,
    required OcrRecordCallback onOcrReady,
  }) async {
    final controller = TextEditingController(text: extraction.rawText);
    final fieldControllers = <String, TextEditingController>{};
    for (final field in extraction.fields.values) {
      fieldControllers[field.key] = TextEditingController(text: field.value);
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: AppDesign.page,
        child: Scaffold(
          backgroundColor: AppDesign.page,
          appBar: AppBar(
            title: Text('Review $moduleLabel OCR'),
            leading: IconButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppDesign.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Verify all extracted text before saving. OCR assists data entry and does not validate clinical information.',
                      style: TextStyle(color: AppDesign.muted, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (extraction.fields.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Detected fields',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...extraction.fields.values.map(
                      (field) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: fieldControllers[field.key],
                          decoration: InputDecoration(
                            labelText: _fieldLabel(field.key),
                            helperText: field.requiresManualReview
                                ? 'Manual verification required (confidence ${(field.confidence * 100).round()}%)'
                                : 'Confidence ${(field.confidence * 100).round()}%',
                            helperStyle: TextStyle(
                              color: field.requiresManualReview
                                  ? Colors.orange.shade700
                                  : AppDesign.muted,
                            ),
                            prefixIcon: Icon(
                              field.requiresManualReview
                                  ? Icons.warning_amber_outlined
                                  : Icons.check_circle_outline,
                              color: field.requiresManualReview
                                  ? Colors.orange.shade700
                                  : AppDesign.blue,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Expanded(
                    child: TextField(
                      controller: controller,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(color: AppDesign.ink),
                      decoration: const InputDecoration(
                        labelText: 'Recognized text',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Continue to new record'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final editedText = controller.text.trim();
    final editedFields = <String, OcrFieldValue>{};
    for (final field in extraction.fields.values) {
      final edited = fieldControllers[field.key]?.text.trim() ?? field.value;
      final wasChanged = edited != field.value.trim();
      editedFields[field.key] = field.copyWith(
        value: edited,
        // A user correction is an explicit verification event. Keep
        // unchanged low-confidence values gated, but allow corrected values
        // to flow into the existing form validation path.
        confidence: wasChanged ? 0.95 : field.confidence,
      );
    }
    controller.dispose();
    for (final fieldController in fieldControllers.values) {
      fieldController.dispose();
    }
    if (accepted != true || editedText.isEmpty || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: editedText));
    final reviewedExtraction = extraction.copyWithFields(editedFields);
    await onOcrReady(reviewedExtraction);
    if (context.mounted) {
      final reviewFields = reviewedExtraction.manualReviewFields
          .map((field) => _fieldLabel(field.key))
          .join(', ');
      _message(
        context,
        reviewFields.isEmpty
            ? 'OCR fields populated. Review them before saving the record.'
            : 'Manual verification required for: $reviewFields.',
      );
    }
  }

  static String _fieldLabel(String key) {
    final spaced = key.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppDesign.navy),
    );
  }
}
