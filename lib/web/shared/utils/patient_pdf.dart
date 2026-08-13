import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';

Future<List<int>> buildPatientPdfBytes(Map<String, dynamic> patient) {
  final patientName = pdfJoin(
    [patient['firstName'], patient['surname']],
    separator: ' ',
    fallback: 'Unknown Patient',
  );

  return buildRecordPdfBytes(
    title: 'Patient Record',
    subtitle: patientName,
    footerText: 'Generated from the Patient records module.',
    barangayName: pdfText(patient['barangay']),
    summaryFields: [],
    sections: [
      RecordPdfSection(
        title: 'Personal Details',
        fields: [
          pdfField('Record ID', patient['id']),
          pdfField('First Name', patient['firstName']),
          pdfField('Surname', patient['surname']),
          pdfField('Mother\'s Maiden Name', patient['mothersMaidenName']),
          pdfField('Date of Birth', patient['dateOfBirth']),
          pdfField('Age', patient['age']),
          pdfField('Place of Birth', patient['placeOfBirth']),
          pdfField('Nationality', patient['nationality']),
          pdfField('Civil Status', patient['civilStatus']),
          pdfField('Gender', patient['gender']),
          pdfField('Religion', patient['religion']),
          pdfField('Occupation', patient['occupation']),
          pdfField('Educational Attainment', patient['educationalAttainment']),
          pdfField('Employee Status', patient['employeeStatus']),
          pdfField('Status', patient['status']),
        ],
      ),
      RecordPdfSection(
        title: 'Contact Information',
        fields: [
          pdfField('Phone Number', patient['phoneNumber']),
          pdfField('Alternative Phone', patient['alternativePhone']),
          pdfField('Email Address', patient['emailAddress']),
          pdfField('Guardian', patient['guardian']),
          pdfField('Street', patient['street']),
          pdfField('Barangay', patient['barangay']),
          pdfField('Municipality', patient['municipality']),
          pdfField('Province', patient['province']),
        ],
      ),
      RecordPdfSection(
        title: 'Medical Details',
        fields: [
          pdfField('Height', patient['height']),
          pdfField('Weight', patient['weight']),
          pdfField('BMI', patient['bmi']),
          pdfField('Blood Type', patient['bloodType']),
          pdfField('Allergies', patient['allergies']),
          pdfField('Immunization Status', patient['immunizationStatus']),
          pdfField('Family Medical History', patient['familyMedicalHistory']),
          pdfField('Past Medical History', patient['pastMedicalHistory']),
          pdfField('Current Medications', patient['currentMedications']),
          pdfField('Chronic Conditions', patient['chronicConditions']),
          pdfField('Chief Complaint', patient['chiefComplaint']),
          pdfField('Current Symptoms', patient['currentSymptoms']),
        ],
      ),
      RecordPdfSection(
        title: 'Vital Signs',
        fields: [
          pdfField(
            'Body Temperature',
            pdfJoin([
              patient['bodyTemperature'],
              patient['temperatureUnit'],
            ], separator: ' '),
          ),
          pdfField(
            'Blood Pressure',
            pdfJoin([
              patient['bpSystolic'],
              patient['bpDiastolic'],
            ], separator: '/'),
          ),
          pdfField('Heart Rate', patient['heartRate']),
          pdfField('Respiratory Rate', patient['respiratoryRate']),
          pdfField('Oxygen Saturation', patient['oxygenSaturation']),
        ],
      ),
      RecordPdfSection(
        title: 'Health & Follow-up',
        fields: [
          pdfField('Disability', patient['disability']),
          pdfField('Mental Health Status', patient['mentalHealthStatus']),
          pdfField('Substance Use History', patient['substanceUseHistory']),
          pdfField('Last Checkup', patient['lastCheckup']),
          pdfField('Next Checkup', patient['nextCheckup']),
        ],
      ),
      RecordPdfSection(
        title: 'Emergency Contact',
        fields: [
          pdfField('Contact Name', patient['emergencyContactName']),
          pdfField('Relationship', patient['emergencyRelationship']),
          pdfField('Phone', patient['emergencyContactPhone']),
          pdfField('Address', patient['emergencyContactAddress']),
        ],
      ),
      RecordPdfSection(
        title: 'Lifestyle & Habits',
        fields: [
          pdfField('Smoking Status', patient['smokingStatus']),
          pdfField('Exercise Frequency', patient['exerciseFrequency']),
          pdfField('Alcohol Consumption', patient['alcoholConsumption']),
          pdfField('Dietary Restrictions', patient['dietaryRestrictions']),
          pdfField(
            'Mental Health (Lifestyle)',
            patient['mentalHealthStatusLifestyle'],
          ),
          pdfField('Sleep Quality', patient['sleepQuality']),
        ],
      ),
      RecordPdfSection(
        title: 'Morbidity Assessment',
        fields: [
          pdfField('Risk Level', patient['morbidityRiskLevel']),
          pdfField('Number of Comorbidities', patient['numberOfComorbidities']),
          pdfField('Functional Status', patient['functionalStatus']),
          pdfField('Mobility Status', patient['mobilityStatus']),
          pdfField('Frailty Index', patient['frailtyIndex']),
          pdfField('Polypharmacy Risk', patient['polypharmacyRisk']),
          pdfField(
            'Preventive Care Compliance',
            patient['preventiveCareCompliance'],
          ),
          pdfField('Health Literacy Level', patient['healthLiteracyLevel']),
          pdfField('Social Support Level', patient['socialSupportLevel']),
          pdfField('Economic Status Impact', patient['economicStatusImpact']),
          pdfField('Assessment Notes', patient['morbidityNotes']),
        ],
      ),
      RecordPdfSection(
        title: 'Insurance & Registration',
        fields: [
          pdfField('Insurance Provider', patient['insuranceProvider']),
          pdfField('Insurance Number', patient['insuranceNumber']),
          pdfField('Insurance Expiry', patient['insuranceExpiry']),
          pdfField('Monthly Income', patient['monthlyIncome']),
          pdfField('Education Level', patient['educationLevel']),
          pdfField('Preferred Language', patient['preferredLanguage']),
          pdfField('Referral Source', patient['referralSource']),
          pdfField('Transportation', patient['transportation']),
          pdfField('Consent Given', patient['consentGiven']),
          pdfField('Registration Date', patient['registrationDate']),
          pdfField('Additional Info', patient['additionalInfo']),
        ],
      ),
    ],
  );
}

String buildPatientPdfFilename(Map<String, dynamic> patient) {
  return buildRecordPdfFilename(
    prefix: 'patient',
    subject: pdfJoin(
      [patient['firstName'], patient['surname']],
      separator: ' ',
      fallback: 'patient',
    ),
    rawDate: patient['registrationDate'],
  );
}
