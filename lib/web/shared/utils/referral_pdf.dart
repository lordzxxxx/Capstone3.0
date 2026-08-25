import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';

Future<List<int>> buildReferralPdfBytes(Map<String, dynamic> record) async {
  final patientName = _buildPatientName(record);
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
    pdfField('Age', record['patientAge'], fallback: 'N/A'),
    pdfField('Sex', record['patientSex'], fallback: 'N/A'),
    pdfField('Address', record['patientAddress'], fallback: 'Not provided'),
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
    pdfField('Complete Vital Signs', record['completeVitalSigns']),
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
  final surname = pdfText(data['patientSurname'], fallback: '').trim();
  final firstName = pdfText(data['patientFirstName'], fallback: '').trim();
  final middleName = pdfText(data['patientMiddleName'], fallback: '').trim();
  final combined = <String>[
    firstName,
    middleName,
  ].where((value) => value.isNotEmpty).join(' ').trim();

  if (surname.isNotEmpty && combined.isNotEmpty) {
    return '$surname, $combined';
  }

  final storedName = pdfText(data['patientName'], fallback: '').trim();
  if (storedName.isNotEmpty) {
    return storedName;
  }

  return 'patient';
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
