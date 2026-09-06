import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';

Future<List<int>> buildCheckupPdfBytes(Map<String, dynamic> record) async {
  final patientName = pdfText(record['patient'], fallback: 'Unknown Patient');

  final patientFields = <MapEntry<String, String>>[
    pdfField('Patient Name', patientName),
    pdfField('Age', record['age']),
    pdfField('Address', record['address']),
  ];

  final encounterFields = <MapEntry<String, String>>[
    pdfField('Record ID', record['id']),
    pdfField('Date & Time', record['datetime']),
    pdfField(
      'Disease Classification',
      record['diseaseType'],
      fallback: 'General',
    ),
    pdfField('Status', record['status'], fallback: 'Completed'),
    pdfField('Follow-up Date', record['followup']),
  ];

  final clinicalFields = <MapEntry<String, String>>[
    pdfField('Vital Signs', record['vitalsigns']),
    pdfField('Symptoms', record['symptoms']),
    pdfField('Treatment Plan', record['plan']),
    pdfField('Assessment Details', record['details']),
  ];

  return buildRecordPdfBytes(
    title: 'Check-Up Record',
    subtitle: '',
    footerText: 'Generated from the Check-Up records module.',
    barangayName: pdfText(record['barangay']),
    summaryFields: [],
    singlePage: true,
    signatureSectionOnNewPage: false,
    signatureSectionAtPageBottom: false,
    sections: [
      RecordPdfSection(title: 'Patient Information', fields: patientFields),
      RecordPdfSection(title: 'Encounter Details', fields: encounterFields),
      RecordPdfSection(title: 'Clinical Summary', fields: clinicalFields),
    ],
    trailingWidgets: [
      // AI Classification and Recovery recommendations removed as per requirements
    ],
  );
}

String buildCheckupPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'checkup',
    subject: pdfText(record['patient'], fallback: 'patient'),
    rawDate: record['datetime'],
  );
}
