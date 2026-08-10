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
      value.trim().isEmpty ||
      confidence < OcrExtraction.manualReviewThreshold;

  OcrFieldValue copyWith({String? value, double? confidence}) =>
      OcrFieldValue(
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
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final values = <String, OcrFieldValue>{};

    void addField(
      String key,
      String value,
      double confidence,
      String source,
    ) {
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

    for (final line in lines) {
      final confidence = (lineConfidence[line] ?? 0.78).clamp(0.0, 1.0);
      _extractLabelValue(
        line,
        confidence.toDouble(),
        addField,
      );
    }

    final allText = lines.join('\n');
    void addGlobal(String key, RegExp pattern, {double confidence = 0.62}) {
      final match = pattern.firstMatch(allText);
      if (match != null) {
        addField(key, match.group(1) ?? match.group(0) ?? '', confidence, 'content match');
      }
    }

    if (!values.containsKey('email')) {
      addGlobal(
        'email',
        RegExp(r'([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})', caseSensitive: false),
      );
    }
    if (!values.containsKey('contactNumber')) {
      addGlobal(
        'contactNumber',
        RegExp(r'((?:\+63|0)\s?\d[\d\s-]{7,13}\d)'),
      );
    }
    if (!values.containsKey('dateOfBirth')) {
      addGlobal(
        'dateOfBirth',
        RegExp(r'\b(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b'),
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
    return OcrExtraction.fromText(
      result.text,
      lineConfidence: lineConfidence,
    );
  }

  static void _extractLabelValue(
    String line,
    double confidence,
    void Function(String key, String value, double confidence, String source)
        addField,
  ) {
    final patterns = <String, RegExp>{
      'firstName': RegExp(r'^\s*first\s*name\s*[:#-]\s*(.+)$', caseSensitive: false),
      'surname': RegExp(r'^\s*(?:surname|last\s*name)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'fullName': RegExp(r'^\s*(?:full\s*name|patient\s*name|name)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'dateOfBirth': RegExp(r'^\s*(?:date\s*of\s*birth|birth\s*date|dob)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'address': RegExp(r'^\s*(?:residential\s*)?address\s*[:#-]\s*(.+)$', caseSensitive: false),
      'patientId': RegExp(r'^\s*(?:patient|record|identification|id)\s*(?:id|no|number|#)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'contactNumber': RegExp(r'^\s*(?:contact|phone|mobile|telephone)(?:\s*(?:number|no))?\s*[:#-]\s*(.+)$', caseSensitive: false),
      'email': RegExp(r'^\s*(?:email|e-mail)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'age': RegExp(r'^\s*age\s*[:#-]\s*(.+)$', caseSensitive: false),
      'gender': RegExp(r'^\s*(?:sex|gender)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'symptoms': RegExp(r'^\s*(?:symptoms?|chief\s*complaint)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'disease': RegExp(r'^\s*(?:disease|diagnosis|condition)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'bloodPressure': RegExp(r'^\s*(?:blood\s*pressure|bp)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'temperature': RegExp(r'^\s*(?:temperature|temp)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'heartRate': RegExp(r'^\s*(?:heart\s*rate|pulse|hr)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'respiratoryRate': RegExp(r'^\s*(?:respiratory\s*rate|rr)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'oxygenSaturation': RegExp(r'^\s*(?:oxygen\s*saturation|spo2|o2)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'weight': RegExp(r'^\s*weight\s*[:#-]\s*(.+)$', caseSensitive: false),
      'height': RegExp(r'^\s*height\s*[:#-]\s*(.+)$', caseSensitive: false),
      'vaccine': RegExp(r'^\s*(?:vaccine|immunization)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'cause': RegExp(r'^\s*(?:cause(?:\s*of\s*death)?|death\s*cause)\s*[:#-]\s*(.+)$', caseSensitive: false),
      'place': RegExp(r'^\s*(?:place|location)\s*[:#-]\s*(.+)$', caseSensitive: false),
    };
    for (final entry in patterns.entries) {
      final match = entry.value.firstMatch(line);
      if (match != null) {
        addField(entry.key, match.group(1)!, confidence, 'label: ${entry.key}');
        return;
      }
    }
  }

  static String _normalizeValue(String key, String value) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (key == 'contactNumber') {
      normalized = normalized.replaceAll(RegExp(r'[^+\d]'), '');
      if (normalized.startsWith('+63')) {
        normalized = '0${normalized.substring(3)}';
      }
    }
    if (key == 'dateOfBirth') {
      normalized = _normalizeDate(normalized);
    }
    return normalized;
  }

  static String _normalizeDate(String value) {
    final match = RegExp(r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})$').firstMatch(value);
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
    if (date == null || date.year != year || date.month != month || date.day != day) {
      return value;
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static bool _validateField(String key, String value) {
    switch (key) {
      case 'firstName':
      case 'surname':
      case 'fullName':
        return RegExp(r"^[\p{L}][\p{L} .'-]{1,100}$", unicode: true).hasMatch(value);
      case 'email':
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
      case 'contactNumber':
        return RegExp(r'^0\d{9,10}$').hasMatch(value);
      case 'age':
        final age = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
        return age != null && age >= 0 && age <= 130;
      case 'dateOfBirth':
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
      editedFields[field.key] = field.copyWith(value: edited);
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
