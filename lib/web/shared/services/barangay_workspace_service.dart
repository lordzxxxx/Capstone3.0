import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';

class _BarangayWorkspaceModuleDefinition {
  final String id;
  final String label;
  final String moduleType;
  final String? collectionName;
  final List<String> sourceCollections;

  const _BarangayWorkspaceModuleDefinition({
    required this.id,
    required this.label,
    required this.moduleType,
    this.collectionName,
    this.sourceCollections = const <String>[],
  });

  Map<String, dynamic> toFirestorePayload(
    String barangayCode, {
    required String barangay,
    required String barangayDistrict,
  }) {
    final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
      barangayCode,
    );

    return <String, dynamic>{
      'moduleId': id,
      'label': label,
      'moduleType': moduleType,
      'barangay': barangay,
      'barangayCode': normalizedCode,
      'barangayDistrict': barangayDistrict,
      'collectionName': collectionName ?? '',
      'collectionPath': collectionName == null
          ? ''
          : BarangayFirestorePaths.barangayRecordCollectionPath(
              normalizedCode,
              collectionName!,
            ),
      'sourceCollections': sourceCollections,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class BarangayWorkspaceService {
  BarangayWorkspaceService._();

  static final BarangayWorkspaceService instance = BarangayWorkspaceService._();

  static const List<_BarangayWorkspaceModuleDefinition> _modules =
      <_BarangayWorkspaceModuleDefinition>[
        _BarangayWorkspaceModuleDefinition(
          id: 'checkup_records',
          label: 'Checkup Records',
          moduleType: 'collection',
          collectionName: 'checkup_records',
          sourceCollections: <String>['checkup_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'mortality_records',
          label: 'Mortality Records',
          moduleType: 'collection',
          collectionName: 'mortality_records',
          sourceCollections: <String>['mortality_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'morbidity_records',
          label: 'Morbidity Records',
          moduleType: 'collection',
          collectionName: 'morbidity_records',
          sourceCollections: <String>['morbidity_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'immunization_records',
          label: 'Immunization Records',
          moduleType: 'collection',
          collectionName: 'immunization_records',
          sourceCollections: <String>['immunization_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'patient_records',
          label: 'Patient Records',
          moduleType: 'collection',
          collectionName: 'patient_records',
          sourceCollections: <String>['patient_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'prenatal_records',
          label: 'Prenatal Records',
          moduleType: 'collection',
          collectionName: 'prenatal_records',
          sourceCollections: <String>['prenatal_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'referrals',
          label: 'Referrals',
          moduleType: 'collection',
          collectionName: 'referrals',
          sourceCollections: <String>['referrals'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'communicable',
          label: 'Communicable Cases',
          moduleType: 'derived_view',
          sourceCollections: <String>['checkup_records', 'morbidity_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'non_communicable',
          label: 'Non-Communicable Cases',
          moduleType: 'derived_view',
          sourceCollections: <String>['checkup_records', 'morbidity_records'],
        ),
        _BarangayWorkspaceModuleDefinition(
          id: 'analytics',
          label: 'Analytics',
          moduleType: 'derived_view',
          sourceCollections: <String>[
            'patient_records',
            'checkup_records',
            'prenatal_records',
            'immunization_records',
            'morbidity_records',
            'mortality_records',
            'referrals',
          ],
        ),
      ];

  final FirebaseFirestore _firestore = getFirestoreInstance();
  final Set<String> _ensuredBarangayCodes = <String>{};

  Future<void> ensureWorkspace(UserAccessScope scope) async {
    if (!scope.isAuthenticated || scope.barangayCode.trim().isEmpty) {
      return;
    }

    final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
      scope.barangayCode,
    );
    if (_ensuredBarangayCodes.contains(normalizedCode)) {
      return;
    }

    final barangayRef = _firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(normalizedCode);
    final batch = _firestore.batch();

    batch.set(barangayRef, <String, dynamic>{
      'barangay': scope.barangay,
      'barangayCode': normalizedCode,
      'barangayDistrict': scope.barangayDistrict,
      'workspaceCollections': _modules.map((module) => module.id).toList(),
      'workspaceInitializedByUid': scope.userId,
      'workspaceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final module in _modules) {
      batch.set(
        barangayRef.collection('workspace_modules').doc(module.id),
        module.toFirestorePayload(
          normalizedCode,
          barangay: scope.barangay,
          barangayDistrict: scope.barangayDistrict,
        ),
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    _ensuredBarangayCodes.add(normalizedCode);
  }
}
