import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_logo_assets.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';

class BarangayBrandingProfile {
  final BarangayReference barangay;
  final String logoUrl;
  final String logoStoragePath;
  final String assignedOfficial;
  final String officialESignatureUrl;
  final String effectiveDate;
  final String notes;
  final DateTime? updatedAt;

  const BarangayBrandingProfile({
    required this.barangay,
    required this.logoUrl,
    required this.logoStoragePath,
    required this.assignedOfficial,
    required this.officialESignatureUrl,
    required this.effectiveDate,
    required this.notes,
    required this.updatedAt,
  });

  bool get hasCustomLogo => logoUrl.trim().isNotEmpty;

  String? get localAssetPath => resolveBarangayLogoAssetPath(
    barangayCode: barangay.code,
    barangayName: barangay.name,
  );

  String get resolvedLogoUrl => hasCustomLogo
      ? logoUrl.trim()
      : BarangayBrandingService.placeholderLogoUrl;

  bool get hasLocalAssetLogo => (localAssetPath ?? '').trim().isNotEmpty;

  bool get hasSignature => officialESignatureUrl.trim().isNotEmpty;

  factory BarangayBrandingProfile.fallback(BarangayReference barangay) {
    return BarangayBrandingProfile(
      barangay: barangay,
      logoUrl: '',
      logoStoragePath: '',
      assignedOfficial: '',
      officialESignatureUrl: '',
      effectiveDate: '',
      notes: '',
      updatedAt: null,
    );
  }

  factory BarangayBrandingProfile.fromMap(
    BarangayReference barangay,
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return BarangayBrandingProfile.fallback(barangay);
    }

    return BarangayBrandingProfile(
      barangay: barangay,
      logoUrl: (data['logoUrl'] ?? '').toString(),
      logoStoragePath: (data['logoStoragePath'] ?? '').toString(),
      assignedOfficial: (data['assignedOfficial'] ?? '').toString(),
      officialESignatureUrl: (data['officialESignatureUrl'] ?? '').toString(),
      effectiveDate: (data['effectiveDate'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      updatedAt: BarangayBrandingService.coerceDate(data['updatedAt']),
    );
  }
}

class UploadedBrandingAsset {
  final String downloadUrl;
  final String storagePath;

  const UploadedBrandingAsset({
    required this.downloadUrl,
    required this.storagePath,
  });
}

class BarangayBrandingService {
  BarangayBrandingService._();

  static final BarangayBrandingService instance = BarangayBrandingService._();

  static const String collectionName = 'barangay_branding';
  static const String placeholderLogoUrl =
      'https://placehold.co/320x320/0A1F24/F5F5F5?text=Barangay+Logo';

  final FirebaseFirestore _firestore = getFirestoreInstance();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static DateTime? coerceDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  Stream<BarangayBrandingProfile> watchBranding(BarangayReference barangay) {
    return _firestore
        .collection(collectionName)
        .doc(barangay.code)
        .snapshots()
        .map(
          (snapshot) =>
              BarangayBrandingProfile.fromMap(barangay, snapshot.data()),
        );
  }

  Future<BarangayBrandingProfile> getBranding(
    BarangayReference barangay,
  ) async {
    final snapshot = await _firestore
        .collection(collectionName)
        .doc(barangay.code)
        .get();
    return BarangayBrandingProfile.fromMap(barangay, snapshot.data());
  }

  Stream<List<BarangayBrandingProfile>> watchAllBranding() {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      final docsByCode = <String, Map<String, dynamic>>{
        for (final doc in snapshot.docs) doc.id: doc.data(),
      };

      return MalaybalayBarangays.all
          .map(
            (barangay) => BarangayBrandingProfile.fromMap(
              barangay,
              docsByCode[barangay.code],
            ),
          )
          .toList();
    });
  }

  Future<void> saveBranding({
    required BarangayReference barangay,
    required String logoUrl,
    required String logoStoragePath,
    required String assignedOfficial,
    required String officialESignatureUrl,
    required String effectiveDate,
    required String notes,
    required String? updatedBy,
  }) {
    return _firestore.collection(collectionName).doc(barangay.code).set({
      'barangay': barangay.name,
      'barangayCode': barangay.code,
      'barangayDistrict': barangay.district,
      'logoUrl': logoUrl.trim(),
      'logoStoragePath': logoStoragePath.trim(),
      'assignedOfficial': assignedOfficial.trim(),
      'officialESignatureUrl': officialESignatureUrl.trim(),
      'effectiveDate': effectiveDate.trim(),
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    }, SetOptions(merge: true));
  }

  Future<UploadedBrandingAsset> uploadBrandingAsset({
    required BarangayReference barangay,
    required Uint8List bytes,
    required String originalFileName,
    required String contentType,
    required bool isSignature,
  }) async {
    final assetType = isSignature ? 'esign' : 'logo';
    final sanitizedName = originalFileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .toLowerCase();
    final extension = sanitizedName.contains('.')
        ? sanitizedName.split('.').last
        : 'png';
    final storagePath =
        'barangay-branding/${barangay.code}/$assetType-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref().child(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final downloadUrl = await ref.getDownloadURL();
    return UploadedBrandingAsset(
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }
}
