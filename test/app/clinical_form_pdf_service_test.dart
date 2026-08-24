import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClinicalFormPdfService Tests', () {
    test('exposes canonical form codes and titles', () {
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.checkup), 'CHK-2026');
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.prenatal), 'PNC-2026');
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.immunization), 'IMZ-2026');
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.morbidity), 'MBD-2026');
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.mortality), 'MOR-2026');
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.patientRegistration), 'PAT-2026');

      expect(ClinicalFormPdfService.getFormTitle(ClinicalFormType.checkup), contains('Check-Up'));
      expect(ClinicalFormPdfService.getFormTitle(ClinicalFormType.prenatal), contains('Prenatal'));
      expect(ClinicalFormPdfService.getFormTitle(ClinicalFormType.immunization), contains('Immunization'));
    });

    test('generates valid PDF bytes for Check-Up Form (CHK-2026) filled & blank', () async {
      final filledBytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.checkup,
        record: {
          'patient': 'Juan Dela Cruz',
          'patientId': 'PAT-2026-0105',
          'dateOfBirth': '1992-05-18',
          'age': '34',
          'gender': 'Male',
          'civilStatus': 'Married',
          'contactNumber': '09178889900',
          'philhealthNumber': '12-345678901-2',
          'address': '45 Rizal Ave',
          'barangay': 'Casisang',
          'bloodPressure': '120/80 mmHg',
          'temperature': '36.7 °C',
          'heartRate': '74 bpm',
          'symptoms': 'Fever and cough',
          'diagnosis': 'URTI',
          'treatment': 'Paracetamol',
        },
        isBlank: false,
      );

      final blankBytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.checkup,
        isBlank: true,
      );

      expect(filledBytes.isNotEmpty, isTrue);
      expect(blankBytes.isNotEmpty, isTrue);

      // Verify PDF header magic bytes "%PDF-" (0x25, 0x50, 0x44, 0x46, 0x2D)
      expect(String.fromCharCodes(filledBytes.sublist(0, 5)), '%PDF-');
      expect(String.fromCharCodes(blankBytes.sublist(0, 5)), '%PDF-');
      expect(filledBytes.length, greaterThan(1000));
      expect(blankBytes.length, greaterThan(1000));
    });

    test('generates valid PDF bytes for Prenatal Care Form (PNC-2026)', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.prenatal,
        record: {
          'patientName': 'Maria Santos Cruz',
          'patientId': 'PAT-2026-042',
          'gravida': '2',
          'para': '1',
          'lmp': '2026-01-10',
          'edd': '2026-10-17',
          'riskLevel': 'Low Risk',
        },
        isBlank: false,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('generates valid PDF bytes for Immunization Card (IMZ-2026)', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.immunization,
        record: {
          'childName': 'Baby Gabriel Reyes',
          'patientId': 'PAT-2026-088',
          'vaccine': 'Pentavalent Vaccine',
          'dose': '2nd Dose',
        },
        isBlank: false,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('generates valid PDF bytes for Morbidity Surveillance (MBD-2026)', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.morbidity,
        record: {
          'patientName': 'Ana Theresa Lim',
          'disease': 'Dengue Fever',
        },
        isBlank: false,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('generates valid PDF bytes for Mortality Notification (MOR-2026)', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.mortality,
        record: {
          'deceasedName': 'Pedro Alvarez Cruz',
          'cause': 'Acute Myocardial Infarction',
        },
        isBlank: false,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('generates valid PDF bytes for Patient Master Registration (PAT-2026)', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.patientRegistration,
        record: {
          'patientName': 'Rodrigo Garcia Fernandez',
          'occupation': 'Teacher',
        },
        isBlank: false,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
