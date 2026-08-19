import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycapstone_project/app/shared/services/ocr_document_scanner_service.dart';
import 'package:mycapstone_project/app/shared/utils/ocr_fuzzy_matcher.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

typedef OcrRecordCallback = Future<void> Function(OcrExtraction extraction);

/// Platform-independent permission copy used by the contextual OCR flow and
/// unit tests. The OS prompt itself remains owned by image_picker.
class OcrPermissionPolicy {
  OcrPermissionPolicy._();

  static String rationale(ImageSource source, String moduleLabel) {
    if (source == ImageSource.camera) {
      return 'Allow camera access only for this $moduleLabel scan. The image '
          'is used to read the document for OCR; the app does not use the '
          'camera in the background.';
    }
    return 'Allow access to the photo you choose for this $moduleLabel OCR '
        'task. AI-DSUHIS does not browse your gallery or access photos in the '
        'background.';
  }

  static String deniedMessage(
    ImageSource source, {
    String code = '',
    String message = '',
  }) {
    final details = '$code $message'.toLowerCase();
    final permissionWasDenied =
        details.contains('denied') ||
        details.contains('permission') ||
        details.contains('restricted') ||
        details.contains('access_denied');
    if (!permissionWasDenied) {
      return 'OCR could not read this image. Please try again.';
    }
    final sourceName = source == ImageSource.camera ? 'Camera' : 'Photos';
    return '$sourceName access was declined. OCR from this source is '
        'unavailable until you enable it in device Settings. You can still '
        'use manual entry or another available feature.';
  }
}

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
    this.hasExplicitSeparator = false,
  });

  final String key;
  final String value;
  final double confidence;
  final String source;

  /// Whether this value came from a line with an explicit label separator
  /// (":", "#", "-"), as opposed to a bare-whitespace label match. A line
  /// like "Barangay: Barangay 03" is unambiguous; a heading like "Barangay
  /// Health Intake Form" can otherwise be misread as a labeled field because
  /// it happens to start with a field keyword. Explicit-separator matches
  /// always win over bare-whitespace ones for the same field.
  final bool hasExplicitSeparator;

  bool get requiresManualReview =>
      value.trim().isEmpty || confidence < OcrExtraction.manualReviewThreshold;

  OcrFieldValue copyWith({String? value, double? confidence}) => OcrFieldValue(
    key: key,
    value: value ?? this.value,
    confidence: confidence ?? this.confidence,
    source: source,
    hasExplicitSeparator: hasExplicitSeparator,
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
    final fullName = seed['fullName']?.toString().trim() ?? '';
    final firstName = seed['firstName']?.toString().trim() ?? '';
    final surname = seed['surname']?.toString().trim() ?? '';
    final derivedName = fullName.isNotEmpty
        ? fullName
        : [firstName, surname].where((part) => part.isNotEmpty).join(' ');
    if (derivedName.isNotEmpty) {
      seed['patientName'] = derivedName;
      seed['patient'] = derivedName;
      seed['name'] = derivedName;
      seed['fullName'] = derivedName;
      seed['childName'] = derivedName;
    }
    if (seed.containsKey('gender')) {
      seed['sex'] = seed['gender'];
    } else if (seed.containsKey('sex')) {
      seed['gender'] = seed['sex'];
    }
    if (seed.containsKey('bloodPressure')) {
      seed['bp'] = seed['bloodPressure'];
    }
    if (seed.containsKey('temperature')) {
      seed['temp'] = seed['temperature'];
      seed['bodyTemp'] = seed['temperature'];
    }
    if (seed.containsKey('heartRate')) {
      seed['hr'] = seed['heartRate'];
      seed['pulse'] = seed['heartRate'];
    }
    if (seed.containsKey('respiratoryRate')) {
      seed['rr'] = seed['respiratoryRate'];
    }
    if (seed.containsKey('oxygenSaturation')) {
      seed['spo2'] = seed['oxygenSaturation'];
    }
    if (seed.containsKey('weight')) {
      seed['wt'] = seed['weight'];
    }
    if (seed.containsKey('height')) {
      seed['ht'] = seed['height'];
    }
    if (seed.containsKey('symptoms')) {
      seed['chiefComplaint'] = seed['symptoms'];
      seed['complaint'] = seed['symptoms'];
    }
    if (seed.containsKey('disease')) {
      seed['diagnosis'] = seed['disease'];
      seed['condition'] = seed['disease'];
    }
    if (seed.containsKey('treatment')) {
      seed['plan'] = seed['treatment'];
      seed['treatmentPlan'] = seed['treatment'];
      seed['medication'] = seed['treatment'];
      seed['prescriptions'] = seed['treatment'];
    }
    if (seed.containsKey('symptoms') && !seed.containsKey('disease')) {
      seed['disease'] = seed['symptoms'];
      seed['diagnosis'] = seed['symptoms'];
    }
    if (seed.containsKey('disease') && !seed.containsKey('symptoms')) {
      seed['symptoms'] = seed['disease'];
      seed['chiefComplaint'] = seed['disease'];
    }
    if (seed.containsKey('cause')) {
      seed['causeOfDeath'] = seed['cause'];
    }
    if (seed.containsKey('place')) {
      seed['placeOfDeath'] = seed['place'];
    }
    if (seed.containsKey('philhealthNumber')) {
      seed['philhealth'] = seed['philhealthNumber'];
    }
    if (seed.containsKey('guardianName')) {
      seed['parentName'] = seed['guardianName'];
      seed['motherName'] = seed['guardianName'];
    }
    if (seed.containsKey('batchNumber')) {
      seed['lotNumber'] = seed['batchNumber'];
      seed['batch'] = seed['batchNumber'];
    }
    if (seed.containsKey('expirationDate')) {
      seed['expiryDate'] = seed['expirationDate'];
    }
    if (seed.containsKey('lmp')) {
      seed['lmpDate'] = seed['lmp'];
    }
    if (seed.containsKey('edd')) {
      seed['eddDate'] = seed['edd'];
      seed['dueDate'] = seed['edd'];
    }
    if (seed.containsKey('aog')) {
      seed['gestationalAge'] = seed['aog'];
    }
    if (seed.containsKey('fundalHeight')) {
      seed['fh'] = seed['fundalHeight'];
    }
    if (seed.containsKey('fetalHeartBeat')) {
      seed['dhb'] = seed['fetalHeartBeat'];
      seed['fhb'] = seed['fetalHeartBeat'];
    }
    if (seed.containsKey('tetanusToxoid')) {
      seed['tcb'] = seed['tetanusToxoid'];
      seed['tt'] = seed['tetanusToxoid'];
    }
    if (seed.containsKey('vaccine')) {
      seed['antigen'] = seed['vaccine'];
    }
    if (seed.containsKey('dose')) {
      seed['doseNumber'] = seed['dose'];
    }
    if (seed.containsKey('reportedBy')) {
      seed['registeredBy'] = seed['reportedBy'];
      seed['administeredBy'] = seed['reportedBy'];
    }
    if (seed.containsKey('time')) {
      seed['timeOfDeath'] = seed['time'];
      seed['timeAdministered'] = seed['time'];
    }
    if (seed.containsKey('nextVisitDate')) {
      seed['followUpDate'] = seed['nextVisitDate'];
      seed['followup'] = seed['nextVisitDate'];
    }
    if (seed.containsKey('dateOfOnset')) {
      seed['onsetDate'] = seed['dateOfOnset'];
    }
    if (seed.containsKey('date')) {
      seed['datetime'] = seed['date'];
      seed['visitDate'] = seed['date'];
      seed['administrationDate'] = seed['date'];
      seed['registrationDate'] = seed['date'];
      seed['reportedDate'] = seed['date'];
      seed['dateReported'] = seed['date'];
      seed['dateTimeOfDeath'] = seed['date'];
      seed['dateOfDeath'] = seed['date'];
      if (!seed.containsKey('dateOfOnset')) {
        seed['dateOfOnset'] = seed['date'];
      }
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

    void addField(
      String key,
      String value,
      double confidence,
      String source,
      bool hasExplicitSeparator,
    ) {
      final normalized = _normalizeValue(key, value);
      if (normalized.isEmpty) return;
      final validated = _validateField(key, normalized);
      final adjusted = validated ? confidence : confidence * 0.45;
      final current = values[key];
      final currentValidated =
          current != null && _validateField(key, current.value);
      final shouldReplace =
          current == null ||
          (!currentValidated && validated) ||
          (hasExplicitSeparator && !current.hasExplicitSeparator) ||
          (hasExplicitSeparator == current.hasExplicitSeparator &&
              adjusted >= current.confidence);
      if (shouldReplace) {
        values[key] = OcrFieldValue(
          key: key,
          value: normalized,
          confidence: adjusted.clamp(0.0, 1.0).toDouble(),
          source: source,
          hasExplicitSeparator: hasExplicitSeparator,
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

      // Skip lines that are only instruction hints or section headers
      if (_isHintOrInstructionLine(line)) {
        continue;
      }

      _extractLabelValue(line, confidence.toDouble(), addField);

      // Forms frequently place a label on one line and its value on subsequent lines
      if (_isLabelOnlyLine(line)) {
        // Look ahead for the value line, skipping any hint/instruction lines
        var lookAhead = index + 1;
        while (lookAhead < lines.length &&
            _isHintOrInstructionLine(lines[lookAhead])) {
          lookAhead++;
        }
        if (lookAhead < lines.length && !_looksLikeLabel(lines[lookAhead])) {
          // For narrative fields (Chief Complaint, Symptoms, Treatment, Plan, Diagnosis, Address),
          // gather consecutive non-label, non-hint lines
          final isNarrativeLabel = RegExp(
            r'(?:chief\s*complaint|symptoms|clinical\s*diagnosis|diagnosis|disease|treatment|plan|rx|address|tirahan)',
            caseSensitive: false,
          ).hasMatch(line);

          if (isNarrativeLabel) {
            final valueParts = <String>[lines[lookAhead]];
            var next = lookAhead + 1;
            while (next < lines.length &&
                !_isHintOrInstructionLine(lines[next]) &&
                !_looksLikeLabel(lines[next])) {
              valueParts.add(lines[next]);
              next++;
            }
            final combinedValue = valueParts.join(' ').trim();
            _extractLabelValue(
              '$line: $combinedValue',
              confidence.toDouble(),
              addField,
            );
          } else {
            _extractLabelValue(
              '$line: ${lines[lookAhead]}',
              confidence.toDouble(),
              addField,
            );
          }
        }
      }
    }

    final allText = lines.join('\n');

    // Parse horizontal Vital Signs table rows (e.g. "120/80 36.5 78 18 98 65 168")
    for (final line in lines) {
      if (_isHintOrInstructionLine(line)) continue;
      final tableRowMatch = RegExp(
        r'\b(\d{2,3}\s*[\/\\]\s*\d{2,3})\s+(3[5-9]\.\d|4[0-2]\.\d)\s+(\d{2,3})\s+(\d{1,2})\s+([89]\d|100)\s+(\d{2,3}(?:\.\d)?)\s+(\d{2,3}(?:\.\d)?)\b',
      ).firstMatch(line);
      if (tableRowMatch != null) {
        addField('bloodPressure', tableRowMatch.group(1)!, 0.95, 'vital table', true);
        addField('temperature', tableRowMatch.group(2)!, 0.95, 'vital table', true);
        addField('heartRate', tableRowMatch.group(3)!, 0.95, 'vital table', true);
        addField('respiratoryRate', tableRowMatch.group(4)!, 0.95, 'vital table', true);
        addField('oxygenSaturation', tableRowMatch.group(5)!, 0.95, 'vital table', true);
        addField('weight', tableRowMatch.group(6)!, 0.95, 'vital table', true);
        addField('height', tableRowMatch.group(7)!, 0.95, 'vital table', true);
        break;
      }
    }

    // Fallback individual vital sign extractors
    if (!values.containsKey('bloodPressure')) {
      final bpMatch = RegExp(r'\b(\d{2,3}\s*[\/\\]\s*\d{2,3})\b').firstMatch(allText);
      if (bpMatch != null) {
        addField('bloodPressure', bpMatch.group(1)!, 0.85, 'vital pattern', false);
      }
    }
    if (!values.containsKey('temperature')) {
      final tempMatch = RegExp(r'\b(3[5-9]\.\d|4[0-2]\.\d)\b').firstMatch(allText);
      if (tempMatch != null) {
        addField('temperature', tempMatch.group(1)!, 0.85, 'vital pattern', false);
      }
    }
    if (!values.containsKey('heartRate')) {
      final hrMatch = RegExp(
        r'(?:(?:hr|pulse|heart\s*rate)\s*[:=]?\s*|\b)([4-9]\d|1[0-9]\d)\s*(?:bpm)?\b',
        caseSensitive: false,
      ).firstMatch(allText);
      if (hrMatch != null) {
        addField('heartRate', hrMatch.group(1)!, 0.75, 'vital pattern', false);
      }
    }
    if (!values.containsKey('respiratoryRate')) {
      final rrMatch = RegExp(
        r'(?:(?:rr|resp)\s*[:=]?\s*|\b)(1[0-9]|2[0-9]|3[0-9]|40)\s*(?:cpm|brpm)?\b',
        caseSensitive: false,
      ).firstMatch(allText);
      if (rrMatch != null) {
        addField('respiratoryRate', rrMatch.group(1)!, 0.75, 'vital pattern', false);
      }
    }
    if (!values.containsKey('oxygenSaturation')) {
      final spo2Match = RegExp(
        r'(?:(?:spo2|o2|sat)\s*[:=]?\s*|\b)(8[5-9]|9\d|100)\s*%?',
        caseSensitive: false,
      ).firstMatch(allText);
      if (spo2Match != null) {
        addField('oxygenSaturation', spo2Match.group(1)!, 0.75, 'vital pattern', false);
      }
    }
    if (!values.containsKey('weight')) {
      final wtMatch = RegExp(
        r'(?:(?:wt|weight)\s*[:=]?\s*|\b)(\d{2,3}(?:\.\d)?)\s*(?:kg|kilos)?\b',
        caseSensitive: false,
      ).firstMatch(allText);
      if (wtMatch != null) {
        addField('weight', wtMatch.group(1)!, 0.75, 'vital pattern', false);
      }
    }
    if (!values.containsKey('height')) {
      final htMatch = RegExp(
        r'(?:(?:ht|height)\s*[:=]?\s*|\b)(1\d{2}(?:\.\d)?|2[01]\d(?:\.\d)?)\s*(?:cm)?\b',
        caseSensitive: false,
      ).firstMatch(allText);
      if (htMatch != null) {
        addField('height', htMatch.group(1)!, 0.75, 'vital pattern', false);
      }
    }

    void addGlobal(String key, RegExp pattern, {double confidence = 0.62}) {
      final match = pattern.firstMatch(allText);
      if (match != null) {
        addField(
          key,
          match.group(1) ?? match.group(0) ?? '',
          confidence,
          'content match',
          false,
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
    if (!values.containsKey('dateOfBirth') && !values.containsKey('date')) {
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
    void Function(
      String key,
      String value,
      double confidence,
      String source,
      bool hasExplicitSeparator,
    )
    addField,
  ) {
    if (_isLabelOnlyLine(line)) {
      return;
    }

    final rawPatterns = <String, String>{
      'patientId':
          r'(?:patient\s*(?:id|no|number|#)|record\s*(?:id|no|number|#)|patient\s*/\s*record\s*id|identification|id\s*(?:no|number|#)?)',
      'dateOfBirth':
          r'(?:date\s*of\s*birth|birth\s*date|dob|b-?day|birthday|kapanganakan)',
      'firstName':
          r'(?:first\s*name|given\s*name|fn|f\.name|unang\s*pangalan)',
      'surname':
          r'(?:surname|last\s*name|family\s*name|ln|l\.name|apelyido)',
      'fullName':
          r'(?:maternal\s*full\s*name|full\s*name\s*of\s*deceased|name\s*of\s*deceased|patient\s*/\s*child\s*full\s*name|child\s*full\s*name|patient\s*full\s*name|full\s*name|patient\s*name|name\s*of\s*patient|pt\.?\s*name|p\.?\s*name|client\s*name|pangalan|patient(?![\s_]*(?:id|no|number|#))|name|pt(?![\s_]*(?:id|no|number|#)))',
      'dateOfOnset':
          r'(?:date\s*of\s*onset(?:\s*of\s*symptoms)?|onset\s*date|petsa\s*ng\s*simula)',
      'date':
          r'(?:date\s*of\s*visit|visit\s*date|checkup\s*date|registration\s*date|date\s*administered|date\s*reported|date\s*of\s*death|record\s*date|date|petsa)',
      'time':
          r'(?:time\s*of\s*death|time\s*administered|time\s*of\s*visit|time|oras)',
      'address':
          r'(?:residential\s*address|residence\s*address|usual\s*residence\s*address|residential|residence|usual\s*residence|home\s*address|address|tirahan|addr)',
      'barangay': r'(?:barangay|brgy\.?|bgy\.?)',
      'contactNumber':
          r'(?:contact(?:\s*number)?|phone(?:\s*number)?|mobile(?:\s*number)?|cell|cel|cp|tel|telephone)(?:\s*(?:number|no|#))?',
      'philhealthNumber':
          r'(?:philhealth\s*(?:id|no\.?|number|#)?(?:\s*/\s*no\.?)?|philhealth\s*id|philhealth)',
      'guardianName':
          r'(?:mother\s*/\s*father\s*/\s*guardian(?:\s*full\s*name)?|mother\s*/\s*father\s*/\s*guardian|guardian\s*full\s*name|guardian\s*name|guardian|parent\s*name|parent|caregiver)',
      'email': r'(?:email|e-mail)',
      'age': r'(?:age\s*at\s*death|age|edad|y/?o|yrs?\.?\s*old)',
      'gender': r'(?:sex|gender|kasarian|m/?f|f/?m)',
      'civilStatus':
          r'(?:civil\s*status|marital\s*status|status|cs)',
      'occupation': r'(?:occupation|trabaho|work|hanapbuhay)',
      'symptoms':
          r'(?:chief\s*complaint(?:\s*/\s*reason\s*for\s*visit\s*/\s*symptoms)?|symptoms\s*/\s*chief\s*complaints\s*/\s*diagnostic\s*lab\s*findings|symptoms\s*/\s*chief\s*complaints|chief\s*complaint|reason\s*for\s*visit|symptoms?|c/?c|complaint|reklamo)',
      'disease':
          r'(?:clinical\s*diagnosis(?:\s*/\s*disease\s*condition\s*\(dx\))?|clinical\s*diagnosis\s*/\s*disease\s*condition|disease\s*/\s*diagnosis\s*\(dx\)|disease\s*/\s*diagnosis|disease|diagnosis|dx\.?|condition|impression|imp\.?|findings|karamdaman)',
      'bloodPressure':
          r'(?:blood\s*pressure(?:\s*\(bp\))?|b\.?p\.?|presyon)',
      'temperature':
          r'(?:body\s*temp(?:erature)?(?:\s*\(t\))?|temp\.?|t\.?|temperature|init)',
      'heartRate':
          r'(?:pulse(?:\s*rate)?(?:\s*\(hr\))?|heart\s*rate(?:\s*\(hr\))?|h\.?r\.?|p\.?r\.?|tibo)',
      'respiratoryRate':
          r'(?:resp(?:\.|\s*rate)?(?:\s*\(rr\))?|respiratory\s*rate(?:\s*\(rr\))?|r\.?r\.?)',
      'oxygenSaturation':
          r'(?:oxygen(?:\s*sat(?:uration)?)?(?:\s*\(spo2\))?|spo2|o2\s*sat|o2)',
      'weight': r'(?:weight(?:\s*\(wt\))?|wt\.?|timbang|kilos?)',
      'height': r'(?:height(?:\s*\(ht\))?|ht\.?|taas)',
      'treatment':
          r'(?:treatment\s*plan(?:\s*/\s*prescribed\s*medications\s*\(rx\)\s*/\s*home\s*care\s*advice)?|treatment\s*plan(?:\s*/\s*prescribed\s*medications\s*\(rx\))?|treatment\s*plan(?:\s*/\s*prescribed\s*medications)?|treatment\s*plan|prescribed\s*medications|treatment|plan|rx|medication|reseta)',
      'vaccine':
          r'(?:vaccine\s*/\s*antigen\s*type|vaccine\s*type|antigen\s*type|vaccine|bakuna|immunization|antigen)',
      'dose': r'(?:dose\s*number|dose)',
      'batchNumber':
          r'(?:batch\s*/\s*lot\s*number|batch\s*/\s*lot|batch\s*number|lot\s*number|batch\s*no\.?|lot\s*no\.?|batch|lot)',
      'expirationDate':
          r'(?:expiration\s*date|expiry\s*date|exp\s*date|exp\.?)',
      'gravida': r'(?:gravida\s*\(g\)|gravida|\bg\b)',
      'para': r'(?:para\s*\(p\)|para|\bp\b)',
      'fullTerm': r'(?:full\s*term\s*\(ft\)|full\s*term|\bft\b)',
      'premature': r'(?:premature\s*\(pt\)|premature|\bpt\b)',
      'abortion': r'(?:abortion\s*\(ab\)|abortion|\bab\b)',
      'livingChildren':
          r'(?:living\s*children\s*\(lc\)|living\s*children|\blc\b)',
      'lmp': r'(?:last\s*menstrual\s*period|lmp)',
      'edd': r'(?:expected\s*delivery\s*date|edd|due\s*date)',
      'aog':
          r'(?:gestation\s*wks|age\s*of\s*gestation|gestational\s*age|aog)',
      'bloodType': r'(?:blood\s*type|blood\s*group|abo|rh)',
      'riskLevel':
          r'(?:pregnancy\s*risk\s*assessment\s*level|pregnancy\s*risk\s*level|risk\s*level|risk\s*assessment|risk)',
      'fundalHeight':
          r'(?:fundal\s*height\s*\(fh\)|fundal\s*height|fh)',
      'fetalHeartBeat':
          r'(?:fetal\s*heart\s*beat\s*\(fhb\)|fetal\s*heart\s*beat|fhb|dhb)',
      'tetanusToxoid':
          r'(?:tetanus\s*toxoid\s*\(tt\)\s*dose|tetanus\s*toxoid\s*\(tt\)|tetanus\s*toxoid|tt|tcb)',
      'cause':
          r'(?:immediate\s*cause(?:\s*of\s*death)?|cause(?:\s*of\s*death)?|c\.?o\.?d\.?|death\s*cause|sanhi)',
      'place':
          r'(?:place\s*of\s*death|place\s*of\s*delivery\s*planned|place|location|lugar)',
      'nextVisitDate':
          r'(?:next\s*visit\s*date|next\s*prenatal\s*visit\s*due\s*date|next\s*dose\s*due\s*date|follow-?up\s*date|next\s*visit)',
      'reportedBy':
          r'(?:reported\s*by|recorded\s*by|vaccinator\s*name\s*&\s*title|vaccinator\s*name|vaccinator|attending\s*health\s*worker|attending\s*midwife\s*/\s*bhw|attending\s*midwife|attending\s*bhw)',
    };

    // First pass: Explicit separators (":", "#", "-", "=")
    for (final entry in rawPatterns.entries) {
      final pattern = RegExp(
        r'^\s*(?:' + entry.value + r')\s*[:#\-=\uFF1A]\s*(.+)$',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(line);
      if (match != null) {
        final rawValue = match.group(1)!.trim();
        final value = _valueBeforeNextLabel(rawValue);
        addField(
          entry.key,
          value,
          confidence,
          'label: ${entry.key}',
          true,
        );
        final remainder = rawValue.substring(value.length).trim();
        if (remainder.isNotEmpty) {
          _extractLabelValue(remainder, confidence, addField);
        }
        return;
      }
    }

    // Second pass: Whitespace separators
    for (final entry in rawPatterns.entries) {
      final pattern = RegExp(
        r'^\s*(?:' + entry.value + r')\s+(.+)$',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(line);
      if (match != null) {
        final rawValue = match.group(1)!.trim();
        final value = _valueBeforeNextLabel(rawValue);
        addField(
          entry.key,
          value,
          confidence,
          'label: ${entry.key}',
          false,
        );
        final remainder = rawValue.substring(value.length).trim();
        if (remainder.isNotEmpty) {
          _extractLabelValue(remainder, confidence, addField);
        }
        return;
      }
    }
  }

  static String _stripFormHints(String text) {
    return text
        .replaceAll(
          RegExp(
            r'\((?:Last Name|First Name|Middle Name|PAT-YYYY|YYYY-MM-DD|yrs/mos|yrs|mos|09XX-XXX-XXXX|House\s*/\s*Street|e\.g\.\s*Barangay|Describe onset|Primary diagnosis|Drug name|mmHg\s*\(e\.g\.|°C\s*\(e\.g\.|kg\b|cm\b|bpm\b|cpm\b|Primary\s*diagnosis|ICD-10|Drug\s*name)[^)]*\)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isHintOrInstructionLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;
    final withoutHints = _stripFormHints(trimmed);
    if (withoutHints.isEmpty) return true;
    if (RegExp(
      r'^\s*(?:republic\s*of\s*the\s*philippines|province\s*of|barangay\s*health\s*center|barangay\s*health\s*check-?up|form:\s*[A-Z0-9\-]+)',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(
      r'^\s*\d+\.\s*(?:Patient Demographic|Vital Signs|Chief Complaint|Clinical Assessment|Treatment Plan|Encounter Metadata|Verification|Maternal Health|Immunization Record|Mortality Notification|Morbidity Details)',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(
      r'^\s*(?:mmHg|°C|bpm|cpm|%|kg|cm)(?:\s+(?:mmHg|°C|bpm|cpm|%|kg|cm))*\s*$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  static String _normalizeOcrLine(String line) {
    var normalized = line
        .replaceAll('\uFF1A', ':')
        .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
        .replaceAll(RegExp(r'[\u2022\u25E6\u2023\u25AA]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    normalized = _stripFormHints(normalized);
    normalized = normalized
        .replaceFirst(RegExp(r'^brgy\.?\s+', caseSensitive: false), 'Barangay ')
        .replaceFirst(
          RegExp(r'^dateofbirth\b', caseSensitive: false),
          'Date of Birth',
        )
        .replaceFirst(
          RegExp(r'^(?:d\.?\s*o\.?\s*b\.?)\b', caseSensitive: false),
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
    final cleaned = _stripFormHints(line);
    return RegExp(
      r'^\s*(?:'
      r'chief\s*complaint(?:\s*/\s*reason\s*for\s*visit\s*/\s*symptoms)?|'
      r'symptoms\s*/\s*chief\s*complaints(?:\s*/\s*diagnostic\s*lab\s*findings)?|'
      r'symptoms\s*/\s*known\s*conditions|'
      r'symptoms?|chief\s*complaint|c/?c|complaint|reklamo|reason\s*for\s*visit|'
      r'clinical\s*diagnosis(?:\s*/\s*disease\s*condition\s*\(dx\))?|'
      r'disease\s*/\s*diagnosis\s*\(dx\)|'
      r'disease\s*/\s*diagnosis|'
      r'diagnosis(?:\s*\(dx\))?|disease|dx|condition|impression|imp\.?|findings|karamdaman|'
      r'treatment\s*plan(?:\s*/\s*prescribed\s*medications\s*\(rx\)\s*/\s*home\s*care\s*advice)?|'
      r'treatment\s*plan(?:\s*/\s*prescribed\s*medications\s*\(rx\))?|'
      r'treatment\s*plan(?:\s*/\s*prescribed\s*medications)?|'
      r'treatment\s*plan|prescribed\s*medications|treatment|plan|rx|medication|reseta|'
      r'maternal\s*full\s*name|full\s*name\s*of\s*deceased|name\s*of\s*deceased|'
      r'patient\s*/\s*child\s*full\s*name|child\s*full\s*name|patient\s*full\s*name|'
      r'full\s*name|patient\s*name|name\s*of\s*patient|pt\.?\s*name|p\.?\s*name|client\s*name|pangalan|patient|name|pt|'
      r'first\s*name|given\s*name|fn|unang\s*pangalan|'
      r'surname|last\s*name|family\s*name|ln|apelyido|'
      r'patient\s*(?:id|no|number|#)|record\s*(?:id|no|number|#)|patient\s*/\s*record\s*id|identification|id|'
      r'date\s*of\s*birth|birth\s*date|dob|b-?day|birthday|kapanganakan|'
      r'age\s*at\s*death|age|edad|'
      r'sex|gender|kasarian|'
      r'civil\s*status|marital\s*status|status|cs|'
      r'contact(?:\s*number)?|phone(?:\s*number)?|mobile(?:\s*number)?|cell|cel|cp|tel|telephone|'
      r'philhealth(?:\s*(?:id|no\.?|number|#))?|'
      r'residential\s*address|residence\s*address|usual\s*residence\s*address|residential|residence|usual\s*residence|home\s*address|address|tirahan|addr|'
      r'barangay|brgy\.?|bgy\.?|'
      r'blood\s*pressure(?:\s*\(bp\))?|b\.?p\.?|presyon|'
      r'body\s*temp(?:erature)?(?:\s*\(t\))?|temp\.?|t\.?|temperature|init|'
      r'pulse(?:\s*rate)?(?:\s*\(hr\))?|heart\s*rate(?:\s*\(hr\))?|h\.?r\.?|p\.?r\.?|tibo|'
      r'resp(?:\.|\s*rate)?(?:\s*\(rr\))?|respiratory\s*rate(?:\s*\(rr\))?|r\.?r\.?|'
      r'oxygen(?:\s*sat(?:uration)?)?(?:\s*\(spo2\))?|spo2|o2\s*sat|o2|'
      r'weight(?:\s*\(wt\))?|wt\.?|timbang|kilos?|'
      r'height(?:\s*\(ht\))?|ht\.?|taas|'
      r'date\s*of\s*visit|visit\s*date|checkup\s*date|registration\s*date|date\s*administered|date\s*reported|date\s*of\s*death|record\s*date|date|petsa|'
      r'date\s*of\s*onset(?:\s*of\s*symptoms)?|onset\s*date|'
      r'next\s*visit\s*date|next\s*prenatal\s*visit\s*due\s*date|next\s*dose\s*due\s*date|follow-?up\s*date|'
      r'encounter\s*status|case\s*status|severity\s*level|classification|'
      r'vaccine(?:\s*/\s*antigen\s*type)?|dose(?:\s*number)?|batch(?:\s*/\s*lot\s*number)?|expiration\s*date|'
      r'gravida(?:\s*\(g\))?|para(?:\s*\(p\))?|full\s*term(?:\s*\(ft\))?|premature(?:\s*\(pt\))?|abortion(?:\s*\(ab\))?|living\s*children(?:\s*\(lc\))?|'
      r'lmp|edd|aog|blood\s*type|pregnancy\s*risk\s*assessment\s*level|fundal\s*height(?:\s*\(fh\))?|fetal\s*heart\s*beat(?:\s*\(fhb\))?|tetanus\s*toxoid(?:\s*\(tt\))?|'
      r'immediate\s*cause(?:\s*of\s*death)?|cause(?:\s*of\s*death)?|place(?:\s*of\s*death)?|reported\s*by|vaccinator(?:\s*name)?'
      r')\s*[:#\-=\uFF1A]?\s*$',
      caseSensitive: false,
    ).hasMatch(cleaned);
  }

  static bool _looksLikeLabel(String line) {
    if (_isLabelOnlyLine(line)) return true;
    final cleaned = _stripFormHints(line);
    // If it's a barangay value like "Barangay 01" or "Barangay San Antonio" without colon, it's a value, not a label
    if (RegExp(
          r'^\s*(?:barangay|brgy\.?|bgy\.?)\s+(?:\d+|[A-Za-z]+)',
          caseSensitive: false,
        ).hasMatch(cleaned) &&
        !cleaned.contains(':')) {
      return false;
    }
    return RegExp(
      r'^\s*(?:'
      r'chief\s*complaint|symptoms|clinical\s*diagnosis|disease|treatment\s*plan|prescribed|'
      r'full\s*name|patient\s*name|first\s*name|surname|last\s*name|name|patient\b|'
      r'patient\s*id|record\s*id|date\s*of\s*birth|dob|age\b|sex\b|gender\b|civil\s*status|'
      r'contact|phone|mobile|philhealth|residential|residence|address|barangay|brgy|'
      r'blood\s*pressure|body\s*temp|pulse\s*rate|heart\s*rate|resp|oxygen|weight|height|'
      r'bp\b|temp\b|hr\b|rr\b|spo2\b|wt\b|ht\b|'
      r'date\s*of\s*visit|visit\s*date|next\s*visit|follow-?up|date\b|'
      r'vaccine|dose|batch|gravida|para|lmp|edd|aog|cause|place|reported\s*by'
      r')\b',
      caseSensitive: false,
    ).hasMatch(cleaned);
  }

  static String _cleanHandwrittenDigits(String s) {
    return s
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[lIi|!]'), '1')
        .replaceAll(RegExp(r'[Zz]'), '2')
        .replaceAll(RegExp(r'[Ss$]'), '5')
        .replaceAll(RegExp(r'[B&]'), '8')
        .replaceAll(RegExp(r'[Gb]'), '6');
  }

  static String _normalizeValue(String key, String value) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceFirst(RegExp(r'^[:#\-=./\uFF1A]+\s*'), '');

    if (key == 'symptoms' ||
        key == 'disease' ||
        key == 'treatment' ||
        key == 'address' ||
        key == 'fullName' ||
        key == 'guardianName') {
      normalized = _stripFormHints(normalized);
    }
    if (key == 'symptoms' || key == 'disease') {
      normalized = OcrFuzzyMatcher.snapClinicalTerm(normalized);
    }

    if (key == 'contactNumber') {
      normalized = _cleanHandwrittenDigits(normalized);
      normalized = normalized.replaceAll(RegExp(r'[^+\d]'), '');
      if (normalized.startsWith('+63')) {
        normalized = '0${normalized.substring(3)}';
      } else if (normalized.startsWith('63') && normalized.length == 12) {
        normalized = '0${normalized.substring(2)}';
      } else if (normalized.startsWith('9') && normalized.length == 10) {
        normalized = '0$normalized';
      }
    } else if (key == 'dateOfBirth' ||
        key == 'date' ||
        key == 'dateOfOnset' ||
        key == 'nextVisitDate' ||
        key == 'expirationDate') {
      normalized = _normalizeDate(normalized);
    } else if (key == 'age') {
      normalized = _normalizeAge(normalized);
    } else if (key == 'gender') {
      normalized = _normalizeGender(normalized);
    } else if (key == 'civilStatus') {
      normalized = _normalizeCivilStatus(normalized);
    } else if (key == 'bloodPressure') {
      normalized = _normalizeBloodPressure(normalized);
    } else if (key == 'temperature') {
      normalized = _normalizeTemperature(normalized);
    } else if (key == 'heartRate' ||
        key == 'respiratoryRate' ||
        key == 'oxygenSaturation' ||
        key == 'weight' ||
        key == 'height') {
      normalized = _normalizeMeasurement(normalized);
    } else if (key == 'fullName' || key == 'firstName' || key == 'surname') {
      normalized = _normalizeName(normalized);
    } else if (key == 'barangay') {
      normalized = _normalizeBarangay(normalized);
    }

    return normalized;
  }

  static String _normalizeName(String value) {
    var cleaned = value
        .replaceAll(RegExp(r"""^[\s_.,~`\-|\'"#]+|[\s_~`\-|\'"#]+$"""), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.endsWith('.') &&
        !RegExp(r'\b[A-Za-z]\.$').hasMatch(cleaned) &&
        !RegExp(r'\b(?:Jr|Sr)\.$', caseSensitive: false).hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    if (cleaned.isEmpty) return value;
    final parts = cleaned.split(' ');
    final titleCased = parts.map((part) {
      if (part.isEmpty) return '';
      final lower = part.toLowerCase();
      if (lower == 'de' ||
          lower == 'del' ||
          lower == 'dela' ||
          lower == 'delos' ||
          lower == 'ng' ||
          lower == 'y') {
        return lower.length > 2
            ? '${lower[0].toUpperCase()}${lower.substring(1)}'
            : lower;
      }
      if (lower == 'jr.' ||
          lower == 'jr' ||
          lower == 'sr.' ||
          lower == 'sr' ||
          lower == 'ii' ||
          lower == 'iii' ||
          lower == 'iv') {
        return part.toUpperCase();
      }
      if (lower.startsWith('ma.') && lower.length > 3) {
        return 'Ma. ${part.substring(3, 4).toUpperCase()}${part.substring(4).toLowerCase()}';
      }
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join(' ');
    return titleCased;
  }

  static String _normalizeAge(String value) {
    var cleaned = _cleanHandwrittenDigits(value);
    final match = RegExp(r'(\d{1,3})').firstMatch(cleaned);
    return match?.group(1) ?? value.trim();
  }

  static String _normalizeGender(String value) {
    final lower = value.toLowerCase().trim();
    // Check for checkbox marks first e.g. "[x] Female" or "[✓] Male"
    final checkedMatch = RegExp(
      r'(?:\[[xXvV✓✔\*\-\/]\]|\([xXvV✓✔\*\-\/]\))\s*(male|female|other)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (checkedMatch != null) {
      final opt = checkedMatch.group(1)!.toLowerCase();
      if (opt == 'female') return 'Female';
      if (opt == 'male') return 'Male';
      return 'Other';
    }
    final reverseCheckedMatch = RegExp(
      r'(male|female|other)\s*(?:\[[xXvV✓✔\*\-\/]\]|\([xXvV✓✔\*\-\/]\))',
      caseSensitive: false,
    ).firstMatch(lower);
    if (reverseCheckedMatch != null) {
      final opt = reverseCheckedMatch.group(1)!.toLowerCase();
      if (opt == 'female') return 'Female';
      if (opt == 'male') return 'Male';
      return 'Other';
    }

    if (lower == 'female' ||
        lower == 'babae' ||
        lower == 'f' ||
        lower.startsWith('f ') ||
        lower.startsWith('female')) {
      return 'Female';
    }
    if (lower == 'male' ||
        lower == 'lalaki' ||
        lower == 'm' ||
        lower.startsWith('m ') ||
        lower.startsWith('male')) {
      return 'Male';
    }
    if (lower.contains('other') || lower.contains('prefer not to say')) {
      return 'Other';
    }
    return value.trim();
  }

  static String _normalizeCivilStatus(String value) {
    final lower = value.toLowerCase().trim();
    // Check for checkbox marks first
    final checkedMatch = RegExp(
      r'(?:\[[xXvV✓✔\*\-\/]\]|\([xXvV✓✔\*\-\/]\))\s*(single|married|widowed|separated|divorced)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (checkedMatch != null) {
      final opt = checkedMatch.group(1)!.toLowerCase();
      if (opt == 'single') return 'Single';
      if (opt == 'married') return 'Married';
      if (opt.startsWith('widow')) return 'Widowed';
      if (opt.startsWith('separat') || opt.startsWith('divorc')) return 'Separated';
    }
    final reverseCheckedMatch = RegExp(
      r'(single|married|widowed|separated|divorced)\s*(?:\[[xXvV✓✔\*\-\/]\]|\([xXvV✓✔\*\-\/]\))',
      caseSensitive: false,
    ).firstMatch(lower);
    if (reverseCheckedMatch != null) {
      final opt = reverseCheckedMatch.group(1)!.toLowerCase();
      if (opt == 'single') return 'Single';
      if (opt == 'married') return 'Married';
      if (opt.startsWith('widow')) return 'Widowed';
      if (opt.startsWith('separat') || opt.startsWith('divorc')) return 'Separated';
    }

    if (lower == 'single' ||
        lower == 'binata' ||
        lower == 'dalaga' ||
        lower == 's') {
      return 'Single';
    }
    if (lower == 'married' || lower == 'kasado' || lower == 'm') {
      return 'Married';
    }
    if (lower.startsWith('widow') || lower == 'balo' || lower == 'w') {
      return 'Widowed';
    }
    if (lower.startsWith('separat') ||
        lower == 'hiwalay' ||
        lower.startsWith('divorc') ||
        lower == 'sep') {
      return 'Separated';
    }
    return value.trim();
  }

  static String _normalizeBloodPressure(String value) {
    var cleaned = _cleanHandwrittenDigits(value);
    cleaned = cleaned
        .replaceAll(RegExp(r'\s*[\/\\]\s*'), '/')
        .replaceAll(RegExp(r'\s*\|\s*'), '/')
        .replaceAll(RegExp(r'\s+over\s+', caseSensitive: false), '/')
        .replaceAll(RegExp(r'over', caseSensitive: false), '/');
    final match = RegExp(r'(\d{2,3})\s*[\/\- ]\s*(\d{2,3})').firstMatch(cleaned);
    if (match != null) {
      final sys = int.tryParse(match.group(1)!);
      final dia = int.tryParse(match.group(2)!);
      if (sys != null && dia != null && sys >= 50 && sys <= 260 && dia >= 30 && dia <= 160) {
        return '$sys/$dia';
      }
    }
    return value.trim();
  }

  static String _normalizeTemperature(String value) {
    var cleaned = _cleanHandwrittenDigits(value);
    cleaned = cleaned
        .replaceAll(RegExp(r'[,°]'), '.')
        .replaceAll(RegExp(r'[CcFf°\s]+$'), '')
        .trim();
    final match = RegExp(r'(\d{2}(?:\.\d{1,2})?)').firstMatch(cleaned);
    if (match != null) {
      final temp = double.tryParse(match.group(1)!);
      if (temp != null) {
        if (temp > 80 && temp < 115) {
          // Fahrenheit to Celsius conversion
          final c = (temp - 32) * 5 / 9;
          return c.toStringAsFixed(1);
        }
        if (temp >= 30.0 && temp <= 45.0) {
          return temp.toStringAsFixed(1);
        }
      }
    }
    return value.trim();
  }

  static String _normalizeMeasurement(String value) {
    var cleaned = _cleanHandwrittenDigits(value);
    cleaned = cleaned
        .replaceAll(
          RegExp(
            r'[a-zA-Z%]+$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(',', '.')
        .trim();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
    return match?.group(1) ?? value.trim();
  }

  static String _normalizeBarangay(String value) {
    var normalized = value
        .replaceFirst(
          RegExp(r'^(?:brgy|bgy)\.?\s*', caseSensitive: false),
          'Barangay ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final numMatch = RegExp(
      r'^Barangay\s+(\d{1,2})$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (numMatch != null) {
      normalized = 'Barangay ${numMatch.group(1)!.padLeft(2, '0')}';
    } else if (RegExp(r'^\d{1,2}$').hasMatch(normalized)) {
      normalized = 'Barangay ${normalized.padLeft(2, '0')}';
    }
    return OcrFuzzyMatcher.snapBarangay(normalized);
  }

  static String _normalizeDate(String value) {
    var cleaned = _cleanHandwrittenDigits(value);
    final namedMonth = RegExp(
      r'^(?:(\d{1,2})\s+([A-Za-z]+)|([A-Za-z]+)\s+(\d{1,2}),?)\s+(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(cleaned.trim());
    if (namedMonth != null) {
      final monthNames = <String, int>{
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'febuary': 2,
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
        final year = yearPart < 100 ? (yearPart > 50 ? 1900 + yearPart : 2000 + yearPart) : yearPart;
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
      r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})$',
    ).firstMatch(cleaned.trim());
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
      year = third < 100 ? (third > 50 ? 1900 + third : 2000 + third) : third;
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
      case 'guardianName':
        return RegExp(
          r"^[\p{L}][\p{L} .,'-]{1,100}$",
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
      case 'dateOfOnset':
      case 'nextVisitDate':
      case 'expirationDate':
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
      case 'patientId':
        return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_/#.-]{1,80}$').hasMatch(value);
      case 'gender':
        return value == 'Male' || value == 'Female' || value == 'Other';
      case 'civilStatus':
        return value == 'Single' ||
            value == 'Married' ||
            value == 'Widowed' ||
            value == 'Separated';
      case 'bloodPressure':
        return RegExp(r'^\d{2,3}/\d{2,3}$').hasMatch(value);
      case 'temperature':
        final temp = double.tryParse(value);
        return temp != null && temp >= 30.0 && temp <= 45.0;
      case 'heartRate':
      case 'respiratoryRate':
      case 'oxygenSaturation':
      case 'weight':
      case 'height':
        final numVal = double.tryParse(value);
        return numVal != null && numVal > 0 && numVal < 500;
      case 'gravida':
      case 'para':
      case 'fullTerm':
      case 'premature':
      case 'abortion':
      case 'livingChildren':
      case 'aog':
      case 'fundalHeight':
      case 'fetalHeartBeat':
      case 'dose':
        final numVal = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
        return numVal != null || value.trim().isNotEmpty;
      case 'bloodType':
      case 'tetanusToxoid':
      case 'riskLevel':
        return value.trim().isNotEmpty;
      case 'philhealthNumber':
        return value.replaceAll(RegExp(r'[\s-]'), '').length >= 4;
      default:
        return value.trim().length >= 2;
    }
  }

  /// Stops a value at the next explicit field label when OCR places several
  /// fields on one physical line (for example, "Name: Ana DOB: 01/02/1990").
  /// Only labels followed by punctuation are boundaries so normal address
  /// text such as "Barangay 3" is not truncated.
  static String _valueBeforeNextLabel(String value) {
    final boundary = RegExp(
      r'\s+(?=(?:first\s*name|given\s*name|surname|last\s*name|family\s*name|full\s*name|patient\s*name|name\s*of\s*patient|pt\.?\s*name|p\.?\s*name|name|pangalan|patient|pt|date|visit\s*date|date\s*of\s*visit|checkup\s*date|record\s*date|date\s*of\s*birth|birth\s*date|dob|b-?day|birthday|kapanganakan|address|tirahan|barangay|patient\s*(?:id|no|number|#)|record\s*(?:id|no|number|#)|identification|id|contact|phone|mobile|cell|cp|telephone|email|age|edad|sex|gender|kasarian|civil\s*status|marital\s*status|status|cs|symptoms?|chief\s*complaint|c/?c|complaint|reklamo|disease|diagnosis|dx|condition|impression|findings|blood\s*pressure|b\.?p\.?|presyon|temperature|temp|init|heart\s*rate|pulse|hr|pr|respiratory\s*rate|rr|oxygen\s*saturation|spo2|o2|weight|wt|timbang|height|ht|taas|vaccine|bakuna|immunization|cause|place|location|lugar)\s*[:#\-\uFF1A])',
      caseSensitive: false,
    );
    return value.split(boundary).first.trim();
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
        _CompactActionButton(
          key: ValueKey('ocr-$moduleLabel'),
          backgroundColor: AppDesign.navy,
          foregroundColor: Colors.white,
          icon: Icons.document_scanner_outlined,
          label: 'OCR',
          onPressed: () => OcrRecordCapture.start(
            context: context,
            moduleLabel: moduleLabel,
            onOcrReady: onOcrReady ?? (_) async => onManualCreate(),
          ),
        ),
        const SizedBox(height: 8),
        _CompactActionButton(
          key: ValueKey('manual-$moduleLabel'),
          backgroundColor: accentColor,
          foregroundColor: foregroundColor,
          icon: Icons.add_rounded,
          label: manualLabel,
          onPressed: onManualCreate,
        ),
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    super.key,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 156),
      child: SizedBox(
        height: 44,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
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
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
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
                'Scan a handwritten or printed health form.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppDesign.blueSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note, color: AppDesign.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Keep the camera steady and parallel to the handwritten sheet with good lighting.',
                        style: TextStyle(
                          color: AppDesign.ink.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
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

    // image_picker delegates the actual OS prompt to the platform. This
    // rationale is shown immediately before that request so the user knows
    // why the selected source is needed. No camera/photo access is requested
    // when the app opens, and this path never requests location access.
    final continueToPermission = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          source == ImageSource.camera
              ? 'Camera access for OCR'
              : 'Photos access for OCR',
        ),
        content: Text(_permissionRationale(source, moduleLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (continueToPermission != true || !context.mounted) return;

    var loadingDialogVisible = false;
    try {
      final image = await OcrDocumentScannerService.scanDocument(source: source);
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
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      if (loadingDialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _message(context, _permissionDeniedMessage(source, error));
    } catch (_) {
      if (!context.mounted) return;
      if (loadingDialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _message(context, 'OCR could not read this image. Please try again.');
    }
  }

  static String _permissionRationale(ImageSource source, String moduleLabel) {
    return OcrPermissionPolicy.rationale(source, moduleLabel);
  }

  static String _permissionDeniedMessage(
    ImageSource source,
    PlatformException error,
  ) {
    return OcrPermissionPolicy.deniedMessage(
      source,
      code: error.code,
      message: error.message ?? '',
    );
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
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(dialogContext, false);
              },
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
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
                      SizedBox(
                        height: 220,
                        child: TextField(
                          controller: controller,
                          minLines: 8,
                          maxLines: 12,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(color: AppDesign.ink),
                          decoration: const InputDecoration(
                            labelText: 'Recognized text',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext, true);
                      },
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Continue to new record'),
                    ),
                  ),
                ),
              ],
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
    // showDialog's Future resolves as soon as the route is popped, before
    // its exit transition finishes animating the still-mounted TextFields.
    // Disposing these controllers immediately races that transition and
    // throws "A TextEditingController was used after being disposed."
    // Deferring past the transition avoids the race while still releasing
    // the controllers.
    Future.delayed(const Duration(milliseconds: 300), () {
      controller.dispose();
      for (final fieldController in fieldControllers.values) {
        fieldController.dispose();
      }
    });
    if (accepted != true || editedText.isEmpty || !context.mounted) return;
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
