import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';
import 'package:intl/intl.dart';

Future<List<int>> buildMortalityPdfBytes(Map<String, dynamic> record) {
  final dateOfDeath = pdfText(
    record['dateTimeOfDeath'],
    fallback: pdfText(record['date'], fallback: 'Unknown date'),
  );

  return buildRecordPdfBytes(
    title: 'Mortality Record',
    subtitle: '',
    footerText: 'Generated from the Mortality records module.',
    summaryFields: [],
    signatureSectionOnNewPage: true,
    signatureSectionAtPageBottom: true,
    sections: [
      RecordPdfSection(
        title: 'Basic Details',
        fields: [
          pdfField('Patient ID', record['patientId']),
          pdfField('Record ID', record['id']),
          pdfField('Name', record['name']),
          pdfField('Date and Time of Death', dateOfDeath),
          pdfField('Age', record['age']),
          pdfField('Gender', record['gender']),
          pdfField('Age Range', record['ageRange']),
        ],
      ),
      RecordPdfSection(
        title: 'Mortality Details',
        fields: [
          pdfField('Cause Category', record['causeCategory']),
          pdfField('Cause of Death', record['causeOfDeath']),
          pdfField('Reason', record['reason']),
          pdfField('Explanation', record['explanation']),
          pdfField('Purok', record['purok']),
          pdfField('Place', record['place']),
          pdfField('Time of Death', record['timeOfDeath']),
          pdfField('Reported By', record['reportedBy']),
          pdfField('Verification Status', record['verification']),
          pdfField(
            'Date Reported',
            _formatMortalityTimestamp(record['dateReported']),
          ),
          pdfField(
            'Month',
            _formatMortalityMonth(
              record['month'],
              fallbackDateSource: record['dateReported'],
            ),
          ),
        ],
      ),
    ],
  );
}

String buildMortalityPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'mortality',
    subject: pdfText(record['name'], fallback: 'record'),
    rawDate: record['dateTimeOfDeath'] ?? record['date'],
  );
}

String _formatMortalityTimestamp(dynamic value) {
  final dateTime = _parseMortalityDateTime(value);
  if (dateTime == null) {
    return pdfText(value, fallback: '');
  }

  final datePart = DateFormat('MMMM d yyyy h:mm').format(dateTime);
  final meridiem = DateFormat('a').format(dateTime).toLowerCase();
  return '$datePart$meridiem';
}

String _formatMortalityMonth(
  dynamic value, {
  dynamic fallbackDateSource,
}) {
  final rawMonth = pdfText(value, fallback: '');

  if (rawMonth.isNotEmpty) {
    final numericMonth = int.tryParse(rawMonth);
    if (numericMonth != null && numericMonth >= 1 && numericMonth <= 12) {
      return DateFormat('MMMM').format(DateTime(2000, numericMonth));
    }

    try {
      return DateFormat('MMMM').format(DateFormat('MMMM').parse(rawMonth));
    } catch (_) {
      try {
        return DateFormat('MMMM').format(DateFormat('MMM').parse(rawMonth));
      } catch (_) {
        // Keep original value if it cannot be normalized.
        return rawMonth;
      }
    }
  }

  final fallbackDate = _parseMortalityDateTime(fallbackDateSource);
  if (fallbackDate != null) {
    return DateFormat('MMMM').format(fallbackDate);
  }

  return '';
}

DateTime? _parseMortalityDateTime(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value.trim());
  }

  if (value is int) {
    if (value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is Map) {
    final seconds = value['seconds'];
    final nanoseconds = value['nanoseconds'];
    if (seconds is int) {
      final millis =
          (seconds * 1000) + ((nanoseconds is int ? nanoseconds : 0) ~/ 1000000);
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
  }

  try {
    final dynamic maybeDateTime = value.toDate();
    if (maybeDateTime is DateTime) {
      return maybeDateTime;
    }
  } catch (_) {
    // Ignore values that cannot be converted via toDate().
  }

  return null;
}
