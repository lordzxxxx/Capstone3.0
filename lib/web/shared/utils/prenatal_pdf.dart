import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';
import 'package:intl/intl.dart';

Future<List<int>> buildPrenatalPdfBytes(Map<String, dynamic> record) {
  return buildRecordPdfBytes(
    title: 'Prenatal Record',
    barangayName: pdfText(record['barangay']),
    subtitle: '',
    footerText: 'Generated from the Prenatal records module.',
    summaryFields: [],
    signatureSectionOnNewPage: true,
    signatureSectionAtPageBottom: true,
    sections: [
      RecordPdfSection(
        title: 'Personal Information',
        fields: [
          pdfField('First Name', record['firstName']),
          pdfField('Surname', record['surname']),
          pdfField('Patient ID', record['patientId']),
          pdfField('Age', record['age']),
          pdfField('Address', record['address']),
          pdfField('Contact Number', record['contactNumber']),
          pdfField('Civil Status', record['civilStatus']),
          pdfField('Religion', record['religion']),
        ],
      ),
      RecordPdfSection(
        title: 'Philhealth Information',
        fields: [
          pdfField('Philhealth Number', record['philhealthNumber']),
          pdfField('Philhealth Member', record['philhealthMember']),
        ],
      ),
      RecordPdfSection(
        title: 'Pregnancy Details',
        fields: [
          pdfField('Gestational Age', record['gestationalAge']),
          pdfField('LMP Date', _formatPrenatalTimestamp(record['lmpDate'])),
          pdfField('EDD Date', _formatPrenatalTimestamp(record['eddDate'])),
          pdfField('Due Date', _formatPrenatalTimestamp(record['dueDate'])),
          pdfField(
            'Last Delivery',
            _formatPrenatalTimestamp(record['lastDeliveryDate']),
          ),
          pdfField('Gravida', record['gravida']),
          pdfField('Para', record['para']),
          pdfField('Risk Level', record['riskLevel']),
        ],
      ),
      RecordPdfSection(
        title: 'Medical History',
        fields: [
          pdfField('Blood Type', record['bloodType']),
          pdfField('Allergies', record['allergies']),
          pdfField('Pre-existing Conditions', record['preExistingConditions']),
          pdfField('Previous Complications', record['previousComplications']),
        ],
      ),
      RecordPdfSection(
        title: 'Vital Signs & Measurements',
        fields: [
          pdfField('Age of Gestation (AOG)', record['aog']),
          pdfField('Weight (WT)', record['wt']),
          pdfField('Abdominal Tenderness (AT)', record['at']),
          pdfField('Temperature', record['temp']),
          pdfField('Blood Pressure (BP)', record['bp']),
          pdfField('BMI', record['bmi']),
          pdfField('Fundal Height (FH)', record['fh']),
          pdfField('Fetal Heart Beat (DHB)', record['dhb']),
          pdfField('Total Bilirubin (TCB)', record['tcb']),
        ],
      ),
      RecordPdfSection(
        title: 'Registration Details',
        fields: [
          pdfField(
            'Registration Date',
            _formatPrenatalTimestamp(record['registrationDate']),
          ),
          pdfField('Registered By', record['registeredBy']),
          pdfField('Status', record['status']),
          pdfField('Additional Note', record['additionalNote']),
        ],
      ),
    ],
  );
}

String buildPrenatalPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'prenatal',
    subject: pdfJoin(
      [record['firstName'], record['surname']],
      separator: ' ',
      fallback: 'patient',
    ),
    rawDate: record['registrationDate'],
  );
}

String _formatPrenatalTimestamp(dynamic value) {
  final dateTime = _parsePrenatalDateTime(value);
  if (dateTime == null) {
    return pdfText(value, fallback: '');
  }

  final datePart = DateFormat('MMMM d yyyy h:mm').format(dateTime);
  final meridiem = DateFormat('a').format(dateTime).toLowerCase();
  return '$datePart$meridiem';
}

DateTime? _parsePrenatalDateTime(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    final parsed = DateTime.tryParse(value.trim());
    return parsed;
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
