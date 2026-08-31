import 'package:flutter/material.dart';

enum ChoDestination {
  dashboard,
  patients,
  checkups,
  prenatal,
  immunization,
  morbidity,
  mortality,
  referrals,
  bhwManagement,
  manageChoAccess,
  reports,
  announcements,
  dataQuality,
  auditLogs,
  notifications,
  profile,
}

class ChoFieldColumn {
  const ChoFieldColumn(this.label, this.keys, {this.flex = 1});

  final String label;
  final List<String> keys;
  final int flex;
}

class ChoModuleConfig {
  const ChoModuleConfig({
    required this.destination,
    required this.title,
    required this.description,
    required this.collection,
    required this.icon,
    required this.tabs,
    required this.columns,
    required this.dateKeys,
    this.aiEnabled = false,
  });

  final ChoDestination destination;
  final String title;
  final String description;
  final String collection;
  final IconData icon;
  final List<String> tabs;
  final List<ChoFieldColumn> columns;
  final List<String> dateKeys;
  final bool aiEnabled;

  static const patients = ChoModuleConfig(
    destination: ChoDestination.patients,
    title: 'Patients',
    description:
        'Review city-wide patient registrations, monitoring status, and linked health activity.',
    collection: 'patient_records',
    icon: Icons.people_alt_outlined,
    tabs: ['Summary', 'Records'],
    dateKeys: ['registrationDate', 'createdAt', 'updatedAt'],
    columns: [
      ChoFieldColumn('Patient ID', ['patientId', 'id']),
      ChoFieldColumn('Full Name', ['fullName', 'name'], flex: 2),
      ChoFieldColumn('Age', ['age']),
      ChoFieldColumn('Sex', ['sex', 'gender']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName'], flex: 2),
      ChoFieldColumn('Household No.', ['householdId', 'householdNumber']),
      ChoFieldColumn('Assigned BHW', ['assignedBhw', 'bhwName'], flex: 2),
      ChoFieldColumn('Last Visit', ['lastVisit', 'lastCheckup']),
      ChoFieldColumn('Health Status', ['riskLevel', 'healthStatus']),
      ChoFieldColumn('Record Status', ['validationStatus', 'status']),
    ],
  );

  static const checkups = ChoModuleConfig(
    destination: ChoDestination.checkups,
    title: 'Check-ups',
    description:
        'Supervise consultations, AI decision support, referrals, and submitted-record validation.',
    collection: 'checkup_records',
    icon: Icons.medical_services_outlined,
    tabs: ['Insights', 'Records', 'Pending Validation'],
    dateKeys: ['datetime', 'date', 'createdAt'],
    aiEnabled: true,
    columns: [
      ChoFieldColumn('Record ID', ['recordId', 'id']),
      ChoFieldColumn('Patient', ['patientName', 'fullName', 'name'], flex: 2),
      ChoFieldColumn('Date and Time', ['datetime', 'date']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName']),
      ChoFieldColumn('BHW', ['bhwName', 'createdByName']),
      ChoFieldColumn('Symptoms', ['symptoms', 'ai_keywords'], flex: 2),
      ChoFieldColumn('Decision-support category', [
        'healthCategory',
        'ai_suggested_health_category',
        'ai_prediction',
      ]),
      ChoFieldColumn('Risk', ['riskLevel']),
      ChoFieldColumn('Validation', ['validationStatus', 'status']),
    ],
  );

  static const prenatal = ChoModuleConfig(
    destination: ChoDestination.prenatal,
    title: 'Prenatal',
    description:
        'Review maternal care activity, high-risk pregnancies, schedules, and validation queues.',
    collection: 'prenatal_records',
    icon: Icons.pregnant_woman_rounded,
    tabs: ['Insights', 'Records', 'High-Risk Cases', 'Pending Validation'],
    dateKeys: ['lastVisit', 'visitDate', 'createdAt'],
    columns: [
      ChoFieldColumn('Maternal ID', ['maternalRecordId', 'recordId', 'id']),
      ChoFieldColumn('Patient', ['patientName', 'fullName', 'name'], flex: 2),
      ChoFieldColumn('Age', ['age', 'maternalAge']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName']),
      ChoFieldColumn('Gestational Age', ['gestationalAge']),
      ChoFieldColumn('Trimester', ['trimester']),
      ChoFieldColumn('Risk', ['riskLevel', 'pregnancyRiskLevel']),
      ChoFieldColumn('Next Visit', ['nextVisit', 'nextCheckup']),
      ChoFieldColumn('Expected Delivery', ['dueDate', 'expectedDeliveryDate']),
      ChoFieldColumn('Validation', ['validationStatus', 'status']),
    ],
  );

  static const immunization = ChoModuleConfig(
    destination: ChoDestination.immunization,
    title: 'Immunization',
    description:
        'Monitor vaccination delivery, coverage, due schedules, and missed immunizations.',
    collection: 'immunization_records',
    icon: Icons.vaccines_outlined,
    tabs: ['Insights', 'Records', 'Due and Missed'],
    dateKeys: ['administrationDate', 'dateAdministered', 'date', 'createdAt'],
    columns: [
      ChoFieldColumn('Record ID', ['recordId', 'id']),
      ChoFieldColumn('Patient ID', ['patientId', 'linkedPatientId']),
      ChoFieldColumn('Patient', ['patientName', 'fullName', 'name'], flex: 2),
      ChoFieldColumn('Vaccine', ['vaccineName', 'vaccine']),
      ChoFieldColumn('Dose', ['dose', 'doseNumber']),
      ChoFieldColumn('Date Administered', [
        'administrationDate',
        'dateAdministered',
        'date',
      ]),
      ChoFieldColumn('Administration Time', ['administrationTime']),
      ChoFieldColumn('Injection Site', ['injectionSite']),
      ChoFieldColumn('Next Schedule', ['nextDoseDueDate', 'nextSchedule']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName']),
      ChoFieldColumn('Administered By', [
        'administeredBy',
        'bhwName',
        'createdByName',
      ]),
      ChoFieldColumn('AEFI', ['adverseEvents']),
      ChoFieldColumn('Status', ['status', 'vaccinationStatus']),
    ],
  );

  static const morbidity = ChoModuleConfig(
    destination: ChoDestination.morbidity,
    title: 'Morbidity',
    description:
        'Monitor reported cases, disease categories, risk, referral status, and validation.',
    collection: 'morbidity_records',
    icon: Icons.monitor_heart_outlined,
    tabs: [
      'Insights',
      'Records',
      'Communicable',
      'Non-Communicable',
      'Pending Validation',
    ],
    dateKeys: ['dateReported', 'date', 'createdAt'],
    columns: [
      ChoFieldColumn('Case ID', ['caseId', 'recordId', 'id']),
      ChoFieldColumn('Patient', ['patientName', 'fullName', 'name'], flex: 2),
      ChoFieldColumn('Disease', ['disease', 'diagnosis', 'condition'], flex: 2),
      ChoFieldColumn('Category', ['diseaseType', 'classification']),
      ChoFieldColumn('Date Recorded', ['dateReported', 'date']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName']),
      ChoFieldColumn('BHW', ['bhwName', 'createdByName']),
      ChoFieldColumn('Case Status', ['caseStatus', 'status']),
      ChoFieldColumn('Risk', ['riskLevel']),
      ChoFieldColumn('Validation', ['validationStatus']),
    ],
  );

  static const mortality = ChoModuleConfig(
    destination: ChoDestination.mortality,
    title: 'Mortality',
    description:
        'Validate reported mortality records and review privacy-preserving aggregate trends.',
    collection: 'mortality_records',
    icon: Icons.heart_broken_outlined,
    tabs: ['Insights', 'Records', 'Pending Validation'],
    dateKeys: ['dateOfDeath', 'date', 'createdAt'],
    columns: [
      ChoFieldColumn('Record ID', ['recordId', 'id']),
      ChoFieldColumn('Authorized Identifier', [
        'patientId',
        'patientName',
      ], flex: 2),
      ChoFieldColumn('Date of Death', ['dateOfDeath', 'date']),
      ChoFieldColumn('Age', ['age']),
      ChoFieldColumn('Sex', ['sex', 'gender']),
      ChoFieldColumn('Barangay', ['barangay', 'barangayName']),
      ChoFieldColumn('Reported Cause', [
        'causeOfDeath',
        'reportedCause',
      ], flex: 2),
      ChoFieldColumn('Classification', ['classification']),
      ChoFieldColumn('Certification', ['certificationStatus']),
      ChoFieldColumn('Validation', ['validationStatus', 'status']),
    ],
  );

  static const all = [
    patients,
    checkups,
    prenatal,
    immunization,
    morbidity,
    mortality,
  ];
}
