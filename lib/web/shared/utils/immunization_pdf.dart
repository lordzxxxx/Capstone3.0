import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/shared/immunization_record_utils.dart';

Future<List<int>> buildImmunizationPdfBytes(Map<String, dynamic> record) {
  final isPediatric = immunizationPatientIsPediatric(record);
  return buildRecordPdfBytes(
    title: 'Immunization Record',
    barangayName: pdfText(record['barangay']),
    subtitle: '',
    footerText: 'Generated from the Immunization records module.',
    summaryFields: [],
    singlePage: true,
    signatureSectionOnNewPage: false,
    signatureSectionAtPageBottom: false,
    sections: [
      RecordPdfSection(
        title: 'Patient Information',
        fields: [
          pdfField('Patient Name', record['patientName']),
          pdfField('Patient ID', record['patientId']),
          pdfField('Middle Name', record['middleName']),
          pdfField('Date of Birth', record['dateOfBirth'] ?? record['dob']),
          pdfField('Age', record['age']),
          pdfField('Sex', record['sex'] ?? record['gender']),
          pdfField('Blood Type', record['bloodType']),
          pdfField('Contact Number', record['contactNumber']),
          pdfField('Address', record['address'] ?? record['street']),
          pdfField('Barangay', record['barangay'] ?? record['barangayName']),
          if (isPediatric)
            pdfField(
              'Parent/Guardian Name',
              record['parentGuardianName'] ?? record['guardian'],
            ),
        ],
      ),
      RecordPdfSection(
        title: 'Vaccine Information',
        fields: [
          pdfField('Vaccine Type', record['vaccine']),
          pdfField('Vaccine Brand', record['vaccineBrand']),
          pdfField('Batch/Lot Number', record['batchNumber']),
          pdfField(
            'Expiration Date',
            _formatImmunizationTimestamp(record['expirationDate']),
          ),
        ],
      ),
      RecordPdfSection(
        title: 'Administration Details',
        fields: [
          pdfField(
            'Administration Date',
            _formatImmunizationTimestamp(record['administrationDate']),
          ),
          pdfField('Administration Time', record['administrationTime']),
          pdfField('Dose Number', record['doseNumber']),
          pdfField('Route of Administration', record['routeOfAdministration']),
          pdfField('Injection Site', record['injectionSite']),
          pdfField('Administered By', record['administeredBy']),
        ],
      ),
      RecordPdfSection(
        title: 'Additional Information',
        fields: [
          pdfField(
            'Adverse Events Following Immunization (AEFI)',
            record['adverseEvents'],
            fallback: 'None reported',
          ),
          pdfField(
            'Next Dose Due Date',
            _formatImmunizationTimestamp(record['nextDoseDueDate']),
          ),
          pdfField('Status', record['status']),
        ],
      ),
    ],
  );
}

String buildImmunizationPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'immunization',
    subject: pdfText(record['patientName'], fallback: 'patient'),
    rawDate: record['administrationDate'],
  );
}

String _formatImmunizationTimestamp(dynamic value) {
  final dateTime = _parseImmunizationDateTime(value);
  if (dateTime == null) {
    return pdfText(value, fallback: '');
  }

  final datePart = DateFormat('MMMM d yyyy h:mm').format(dateTime);
  final meridiem = DateFormat('a').format(dateTime).toLowerCase();
  return '$datePart$meridiem';
}

DateTime? _parseImmunizationDateTime(dynamic value) {
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
