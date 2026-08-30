import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';

const String _productionBaseUrl = String.fromEnvironment(
  'APP_BASE_URL',
  defaultValue: 'https://www.ai-dsuhis.com',
);

Future<List<int>> buildReferralPdfBytes(Map<String, dynamic> record) async {
  final patientInformation = record['patientInformation'] is Map
      ? Map<String, dynamic>.from(record['patientInformation'] as Map)
      : const <String, dynamic>{};
  final resolvedRecord = <String, dynamic>{...patientInformation, ...record};
  final patientName = _buildPatientName(resolvedRecord);
  final referralCategories = _safeStringList(record['referralCategories']);
  final referralType = referralCategories.isEmpty
      ? pdfText(record['referralType'], fallback: 'Not selected')
      : referralCategories.join(', ');

  final hasSurgicalOperations = _readNullableBool(
    record['hasSurgicalOperations'],
  );
  final hasHealthInsuranceCoverage = _readNullableBool(
    record['hasHealthInsuranceCoverage'],
  );

  final surgicalProcedure = pdfText(
    record['surgicalProcedure'],
    fallback: '',
  ).trim();
  final healthInsuranceCoverageType = pdfText(
    record['healthInsuranceCoverageType'],
    fallback: '',
  ).trim();

  final surgicalSummary =
      hasSurgicalOperations == true && surgicalProcedure.isNotEmpty
      ? 'Yes - $surgicalProcedure'
      : _displayYesNo(hasSurgicalOperations);

  final insuranceSummary =
      hasHealthInsuranceCoverage == true &&
          healthInsuranceCoverageType.isNotEmpty
      ? 'Yes - $healthInsuranceCoverageType'
      : _displayYesNo(hasHealthInsuranceCoverage);

  final patientFields = <MapEntry<String, String>>[
    pdfField('Patient Name', patientName, fallback: 'Unnamed patient'),
    pdfField(
      'Age',
      _firstValue(resolvedRecord, ['patientAge', 'age']),
      fallback: 'N/A',
    ),
    pdfField(
      'Sex',
      _firstValue(resolvedRecord, ['patientSex', 'sex', 'gender']),
      fallback: 'N/A',
    ),
    pdfField(
      'Contact Number',
      _firstValue(resolvedRecord, [
        'patientContactNumber',
        'contactNumber',
        'phoneNumber',
      ]),
      fallback: 'Not provided',
    ),
    pdfField(
      'Date of Birth',
      _firstValue(resolvedRecord, ['patientDateOfBirth', 'dateOfBirth', 'dob']),
      fallback: 'Not provided',
    ),
    pdfField(
      'Address',
      _firstValue(resolvedRecord, ['patientAddress', 'address', 'street']),
      fallback: 'Not provided',
    ),
    pdfField('Barangay', record['barangay'], fallback: 'Unassigned barangay'),
  ];

  final referralFields = <MapEntry<String, String>>[
    pdfField('Referral ID', record['id']),
    pdfField('Referral Type', referralType, fallback: 'Not selected'),
    pdfField('Referred To', record['referredTo'], fallback: 'Not provided'),
    pdfField(
      'Referral Date & Time',
      record['referralDateTime'],
      fallback: _formatDate(record['createdAt']),
    ),
    pdfField('Reason for Referral', record['referralReason']),
    pdfField('Chief Complaints', record['chiefComplaint']),
    pdfField('Status', record['status'], fallback: 'submitted'),
    pdfField(
      'Submitted By',
      record['createdByName'] ?? record['createdByEmail'],
      fallback: 'Unknown sender',
    ),
    pdfField('Created At', _formatDate(record['createdAt'])),
    pdfField('Updated At', _formatDate(record['updatedAt'])),
  ];

  final clinicalFields = <MapEntry<String, String>>[
    pdfField('Medical History', record['medicalHistory']),
    pdfField(
      'Complete Vital Signs',
      _firstValue(record, [
        'completeVitalSigns',
        'latestVitalSigns',
        'vitalsigns',
        'vitalSigns',
        'vitals',
      ]),
    ),
    pdfField(
      'Impression',
      record['impression'] ?? record['currentDiagnosis'],
      fallback: 'Not provided',
    ),
    pdfField(
      'Action Taken (phone/RECO)',
      record['actionTaken'] ?? record['currentTreatment'],
      fallback: 'Not provided',
    ),
    pdfField('Last Meal Time', record['lastMealTime']),
    pdfField('Surgical Operations', surgicalSummary),
    pdfField('Health Insurance Coverage', insuranceSummary),
  ];

  final workflowFields = <MapEntry<String, String>>[
    pdfField('Assigned Doctor', record['assignedDoctorName']),
    pdfField('Assigned Doctor Email', record['assignedDoctorEmail']),
    pdfField('Assignment Mode', record['assignmentMode']),
    pdfField('Assignment Rationale', record['assignmentRationale']),
    pdfField('CHO Review Notes', record['choReviewNotes']),
    pdfField('Doctor Diagnosis', record['doctorDiagnosis']),
    pdfField('Doctor Treatment', record['doctorTreatment']),
    pdfField('Doctor Medication', record['doctorMedication']),
    pdfField('Doctor Notes', record['doctorNotes']),
  ];
  final referralId = pdfText(record['id'] ?? record['referralId']).trim();
  final verificationUrl = referralId.isEmpty
      ? ''
      : '${_productionBaseUrl.replaceFirst(RegExp(r'\/$'), '')}/cho/referrals?referralId=${Uri.encodeComponent(referralId)}';

  return buildRecordPdfBytes(
    title: 'Patient Referral Form',
    subtitle: 'Complete Referral Details',
    systemName: 'AI-DSUHIS Referral Management',
    footerText: 'Generated from the CHO Referral page.',
    barangayName: pdfText(record['barangay']),
    summaryFields: const [],
    signatureSectionOnNewPage: true,
    signatureSectionAtPageBottom: true,
    signatureLines: const [
      RecordPdfSignatureLine(title: 'Barangay Captain'),
      RecordPdfSignatureLine(title: 'Barangay Kagawad in Health'),
      RecordPdfSignatureLine(title: 'BHW Head'),
      RecordPdfSignatureLine(title: 'BHW Assigned on Duty'),
    ],
    trailingWidgets: verificationUrl.isEmpty
        ? const []
        : [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: verificationUrl,
                    width: 120,
                    height: 120,
                    drawText: false,
                    backgroundColor: PdfColors.white,
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Text(
                      'Secure referral record\nScan this QR code to open the authorized digital referral record. The QR payload contains only the referral reference and application route.',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ],
    sections: [
      RecordPdfSection(title: 'Patient Information', fields: patientFields),
      RecordPdfSection(title: 'Referral Information', fields: referralFields),
      RecordPdfSection(title: 'Clinical Details', fields: clinicalFields),
      RecordPdfSection(
        title: 'Workflow and Assignment',
        fields: workflowFields,
      ),
    ],
  );
}

String buildReferralPdfFilename(Map<String, dynamic> record) {
  final patientName = _buildPatientName(record);
  return buildRecordPdfFilename(
    prefix: 'referral_form',
    subject: patientName,
    rawDate: record['referralDateTime'] ?? record['createdAt'],
  );
}

String _buildPatientName(Map<String, dynamic> data) {
  final surname = pdfText(
    _firstValue(data, ['patientSurname', 'surname', 'lastName']),
    fallback: '',
  ).trim();
  final firstName = pdfText(
    _firstValue(data, ['patientFirstName', 'firstName']),
    fallback: '',
  ).trim();
  final middleName = pdfText(
    _firstValue(data, ['patientMiddleName', 'middleName']),
    fallback: '',
  ).trim();
  final combined = <String>[
    firstName,
    middleName,
  ].where((value) => value.isNotEmpty).join(' ').trim();

  if (surname.isNotEmpty && combined.isNotEmpty) {
    return '$surname, $combined';
  }

  final storedName = pdfText(
    _firstValue(data, ['patientName', 'fullName', 'name']),
    fallback: '',
  ).trim();
  if (storedName.isNotEmpty) {
    return storedName;
  }

  return 'patient';
}

dynamic _firstValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value.toString().trim().isNotEmpty) return value;
  }
  return null;
}

List<String> _safeStringList(dynamic value) {
  if (value is Iterable) {
    return value
        .map((entry) => pdfText(entry, fallback: '').trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  final text = pdfText(value, fallback: '').trim();
  if (text.isEmpty) {
    return const <String>[];
  }

  return text
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

bool? _readNullableBool(dynamic value) {
  if (value is bool) {
    return value;
  }

  final normalized = pdfText(value, fallback: '').trim().toLowerCase();
  if (normalized == 'true' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == 'no') {
    return false;
  }
  return null;
}

String _displayYesNo(bool? value, {String fallback = 'Not specified'}) {
  if (value == null) {
    return fallback;
  }
  return value ? 'Yes' : 'No';
}

String _formatDate(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  if (value is DateTime) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  final text = pdfText(value, fallback: '').trim();
  return text;
}
