import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';
import 'package:intl/intl.dart';

Future<List<int>> buildMorbidityPdfBytes(Map<String, dynamic> record) {
  final patientName = pdfText(
    record['patientName'] ?? record['patient'] ?? record['name'],
    fallback: 'Unknown Patient',
  );

  return buildRecordPdfBytes(
    title: 'Morbidity Record',
    barangayName: pdfText(record['barangay']),
    subtitle: '',
    footerText: 'Generated from the Morbidity records module.',
    summaryFields: [],
    signatureSectionOnNewPage: true,
    signatureSectionAtPageBottom: true,
    sections: [
      RecordPdfSection(
        title: 'Patient Information',
        fields: [
          pdfField('Patient Name', patientName),
          pdfField('Patient ID', record['patientId'] ?? record['id']),
          pdfField('Age', record['age']),
          pdfField('Gender', record['gender'] ?? record['sex']),
          pdfField('Address', record['address']),
          pdfField('Contact Number', record['contactNumber']),
        ],
      ),
      RecordPdfSection(
        title: 'Clinical & Disease Information',
        fields: [
          pdfField('Disease / Condition', record['disease']),
          pdfField(
            'Classification / Type',
            record['diseaseType'],
            fallback: 'Morbidity',
          ),
          pdfField('Severity Level', record['severity']),
          pdfField('Symptoms / Chief Complaint', record['symptoms']),
          pdfField('Diagnosis Details', record['diagnosis']),
          pdfField('Treatment Plan', record['plan'] ?? record['treatment']),
        ],
      ),
      RecordPdfSection(
        title: 'Surveillance & Record Details',
        fields: [
          pdfField('Status', record['status'], fallback: 'Active'),
          pdfField(
            'Date Reported',
            _formatMorbidityTimestamp(
              record['reportedDate'] ??
                  record['dateReported'] ??
                  record['date'],
            ),
          ),
          pdfField('Reported By', record['reportedBy']),
          pdfField('Remarks / Notes', record['remarks'] ?? record['notes']),
        ],
      ),
    ],
  );
}

String buildMorbidityPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'morbidity',
    subject: pdfText(
      record['patientName'] ?? record['patient'] ?? record['name'],
      fallback: 'patient',
    ),
    rawDate: record['reportedDate'] ?? record['dateReported'] ?? record['date'],
  );
}

String _formatMorbidityTimestamp(dynamic value) {
  final dateTime = _parseMorbidityDateTime(value);
  if (dateTime == null) {
    return pdfText(value, fallback: '');
  }

  final datePart = DateFormat('MMMM d yyyy h:mm').format(dateTime);
  final meridiem = DateFormat('a').format(dateTime).toLowerCase();
  return '$datePart$meridiem';
}

DateTime? _parseMorbidityDateTime(dynamic value) {
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
          (seconds * 1000) +
          ((nanoseconds is int ? nanoseconds : 0) ~/ 1000000);
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
