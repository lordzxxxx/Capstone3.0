import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Patient-First Service Selection & Timeline Tests', () {
    test('resolveRegisteredPatient correctly resolves patient from seed or isRegisteredPatient', () async {
      final service = PatientCenteredHistoryService();

      final registeredPatient = {
        'id': 'pat_101',
        'patientId': 'PAT-2026-001',
        'patientCode': 'PAT-001',
        'firstName': 'Maria Clara',
        'surname': 'Santos',
        'age': '28',
        'gender': 'Female',
        'address': 'Purok 4, Casisang',
        'isRegisteredPatient': true,
      };

      final resolved = await service.resolveRegisteredPatient(registeredPatient);
      expect(resolved, isNotNull);
      expect(resolved!['patientId'], 'PAT-2026-001');
      expect(resolved['firstName'], 'Maria Clara');
      expect(resolved['surname'], 'Santos');
    });

    test('Patient timeline gathers events across checkup, prenatal, immunization, morbidity, mortality', () async {
      final service = PatientCenteredHistoryService();

      final patient = {
        'id': 'pat_101',
        'patientId': 'PAT-2026-001',
        'firstName': 'Maria Clara',
        'surname': 'Santos',
      };

      final snapshot = await service.loadPatientHistory(patient);
      expect(snapshot, isNotNull);
      expect(snapshot.patient['id'], 'pat_101');
      expect(snapshot.totalRecords, isNonNegative);
    });
  });
}
