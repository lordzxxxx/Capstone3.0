import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';

/// Epidemiological risk tier used to color barangay polygons, heat halos,
/// map markers, and directory badges based on active case burden.
enum BarangayEpidemiologicalTier {
  baseline,
  low,
  moderate,
  high,
  critical,
}

/// Filterable surveillance categories covering all clinical modules and
/// disease classifications across the AI-DSUHIS platform.
enum SurveillanceCaseCategory {
  all('All Cases & Diseases', Icons.public_rounded),
  communicable('Communicable Diseases', Icons.coronavirus_outlined),
  nonCommunicable('Non-Communicable (NCD)', Icons.favorite_border_rounded),
  morbidity('Morbidity Surveillance', Icons.monitor_heart_outlined),
  checkups('Clinical Check-ups', Icons.medical_services_outlined),
  prenatal('Maternal & Prenatal', Icons.pregnant_woman_rounded),
  immunization('Immunization', Icons.vaccines_outlined),
  mortality('Mortality', Icons.heart_broken_outlined),
  referrals('Clinical Referrals', Icons.assignment_ind_outlined);

  const SurveillanceCaseCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Coloring metric mode for the interactive choropleth map.
enum SurveillanceColorMetric {
  caseVolume('Color by Case Count'),
  severityScore('Color by Risk Severity');

  const SurveillanceColorMetric(this.label);
  final String label;
}

/// Computed threshold cutoffs for the 5 epidemiological color tiers.
class EpidemiologicalTierThresholds {
  const EpidemiologicalTierThresholds({
    required this.lowMax,
    required this.moderateMax,
    required this.highMax,
  });

  final int lowMax;
  final int moderateMax;
  final int highMax;
}

/// Represents a synchronized BHW user assigned to a Malaybalay barangay.
class SyncedBhwUserSummary {
  const SyncedBhwUserSummary({
    required this.uid,
    required this.name,
    required this.email,
    required this.barangay,
    required this.approvalStatus,
    required this.accountStatus,
  });

  final String uid;
  final String name;
  final String email;
  final BarangayReference barangay;
  final String approvalStatus;
  final String accountStatus;

  bool get isApprovedAndActive {
    final approval = approvalStatus.toLowerCase();
    final status = accountStatus.toLowerCase();
    return (approval == 'approved' || approval.isEmpty) &&
        (status == 'active' || status == 'approved' || status.isEmpty);
  }
}

/// Normalized epidemiological case record mapped to a specific Malaybalay
/// barangay across any synced health collection.
class BarangaySurveillanceCase {
  const BarangaySurveillanceCase({
    required this.id,
    required this.barangay,
    required this.disease,
    required this.category,
    required this.sourceCollection,
    required this.severityLabel,
    required this.severityWeight,
    required this.reportedAt,
    this.patientLabel = '',
    this.reportedByBhw = '',
    this.isPersistedInFirestore = true,
  });

  final String id;
  final BarangayReference barangay;
  final String disease;
  final SurveillanceCaseCategory category;
  final String sourceCollection;
  final String severityLabel;
  final int severityWeight;
  final DateTime? reportedAt;
  final String patientLabel;
  final String reportedByBhw;
  final bool isPersistedInFirestore;
}

/// Aggregated epidemiological profile for a single barangay on the map.
class BarangayMapSurveillanceSummary {
  const BarangayMapSurveillanceSummary({
    required this.barangay,
    required this.center,
    required this.polygon,
    required this.totalCases,
    required this.severityScore,
    required this.communicableCount,
    required this.nonCommunicableCount,
    required this.morbidityCount,
    required this.checkupCount,
    required this.prenatalCount,
    required this.immunizationCount,
    required this.mortalityCount,
    required this.referralCount,
    required this.diseaseCounts,
    required this.assignedBhwUsers,
    required this.workspaceSynced,
    required this.tier,
    required this.fillColor,
    required this.strokeColor,
    required this.badgeColor,
    required this.intensityRatio,
  });

  final BarangayReference barangay;
  final LatLng center;
  final List<LatLng> polygon;
  final int totalCases;
  final int severityScore;
  final int communicableCount;
  final int nonCommunicableCount;
  final int morbidityCount;
  final int checkupCount;
  final int prenatalCount;
  final int immunizationCount;
  final int mortalityCount;
  final int referralCount;
  final Map<String, int> diseaseCounts;
  final List<SyncedBhwUserSummary> assignedBhwUsers;
  final bool workspaceSynced;
  final BarangayEpidemiologicalTier tier;
  final Color fillColor;
  final Color strokeColor;
  final Color badgeColor;
  final double intensityRatio;

  String get dominantDisease {
    if (diseaseCounts.isEmpty) return 'No active cases';
    final sorted = diseaseCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  int get dominantDiseaseCount {
    if (diseaseCounts.isEmpty) return 0;
    final sorted = diseaseCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.value;
  }

  String get tierLabel {
    switch (tier) {
      case BarangayEpidemiologicalTier.baseline:
        return 'Baseline';
      case BarangayEpidemiologicalTier.low:
        return 'Low Load';
      case BarangayEpidemiologicalTier.moderate:
        return 'Moderate';
      case BarangayEpidemiologicalTier.high:
        return 'High Alert';
      case BarangayEpidemiologicalTier.critical:
        return 'Critical Hotspot';
    }
  }
}

/// Geospatial reference and Voronoi boundary generator for all Malaybalay City
/// barangays, paired with multi-module disease aggregation and BHW sync.
class MalaybalayBarangayGeoRegistry {
  MalaybalayBarangayGeoRegistry._();

  static const LatLng cityCenter = LatLng(8.1485, 125.1580);
  static const LatLng poblacionCenter = LatLng(8.1562, 125.1285);

  /// Verified coordinates for every Malaybalay City barangay in
  /// [MalaybalayBarangays.all].
  static const Map<String, LatLng> coordinatesByCode = <String, LatLng>{
    // Poblacion District (11 urban barangays)
    'poblacion-01': LatLng(8.1618, 125.1242),
    'poblacion-02': LatLng(8.1622, 125.1288),
    'poblacion-03': LatLng(8.1615, 125.1334),
    'poblacion-04': LatLng(8.1578, 125.1235),
    'poblacion-05': LatLng(8.1580, 125.1282),
    'poblacion-06': LatLng(8.1576, 125.1330),
    'poblacion-07': LatLng(8.1538, 125.1238),
    'poblacion-08': LatLng(8.1540, 125.1285),
    'poblacion-09': LatLng(8.1535, 125.1332),
    'poblacion-10': LatLng(8.1496, 125.1255),
    'poblacion-11': LatLng(8.1494, 125.1312),

    // South Highway District (6 barangays)
    'casisang': LatLng(8.1285, 125.1288),
    'san-jose': LatLng(8.1035, 125.1342),
    'magsaysay': LatLng(8.0815, 125.1385),
    'aglayan': LatLng(8.0592, 125.1428),
    'cabangahan': LatLng(8.0418, 125.1225),
    'bangcud': LatLng(7.9975, 125.1368),

    // North Highway District (7 barangays)
    'sumpong': LatLng(8.1695, 125.1185),
    'kalasungay': LatLng(8.1872, 125.1145),
    'patpat': LatLng(8.2045, 125.1278),
    'dalwangan': LatLng(8.2345, 125.1062),
    'manalog': LatLng(8.2680, 125.1585),
    'laguitas': LatLng(8.1215, 125.1085),
    'miglamin': LatLng(8.1585, 125.1745),

    // Basakan District (13 barangays)
    'linabo': LatLng(8.0485, 125.1662),
    'violeta': LatLng(8.0215, 125.1542),
    'maligaya': LatLng(8.0285, 125.1748),
    'managok': LatLng(8.0372, 125.1975),
    'sto-nino': LatLng(8.0122, 125.1825),
    'simaya': LatLng(7.9882, 125.1665),
    'apo-macote': LatLng(7.9625, 125.1518),
    'sinanglanan': LatLng(7.9725, 125.1965),
    'san-martin': LatLng(8.0048, 125.2115),
    'imbayao': LatLng(8.1265, 125.0745),
    'mapayag': LatLng(8.0965, 125.0685),
    'kibalabag': LatLng(8.2085, 125.1885),
    'st-peter': LatLng(8.1865, 125.3625),

    // Upper Pulangi District (10 barangays)
    'can-ayan': LatLng(8.1855, 125.1535),
    'capitan-angel': LatLng(8.1615, 125.0885),
    'dumalaguing': LatLng(8.2215, 125.2385),
    'busdi': LatLng(8.1525, 125.2685),
    'kulaman': LatLng(8.1745, 125.2945),
    'silae': LatLng(8.1985, 125.3185),
    'caburacanan': LatLng(8.1225, 125.3125),
    'mapulo': LatLng(8.1365, 125.3445),
    'indalasa': LatLng(8.1625, 125.3565),
    'zamboanguita': LatLng(8.1285, 125.3885),
  };

  static final Map<String, List<LatLng>> _cachedPolygons =
      _computeVoronoiPolygons();

  /// Returns the geographic center for [barangay].
  static LatLng centerFor(BarangayReference barangay) {
    return coordinatesByCode[barangay.code.toLowerCase()] ?? cityCenter;
  }

  /// Returns a non-overlapping Voronoi-clipped territory polygon for [barangay].
  static List<LatLng> polygonFor(BarangayReference barangay) {
    return _cachedPolygons[barangay.code.toLowerCase()] ??
        _radialPolygon(centerFor(barangay), 0.008, sides: 12);
  }

  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      final intersect =
          ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) *
                      (point.latitude - yi) /
                      ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Returns the map center and zoom level appropriate for a given district.
  static ({LatLng center, double zoom}) cameraForDistrict(String district) {
    switch (district) {
      case 'Poblacion District':
        return (center: poblacionCenter, zoom: 14.3);
      case 'South Highway District':
        return (center: const LatLng(8.0680, 125.1340), zoom: 12.0);
      case 'North Highway District':
        return (center: const LatLng(8.1950, 125.1320), zoom: 11.8);
      case 'Basakan District':
        return (center: const LatLng(8.0350, 125.1680), zoom: 11.4);
      case 'Upper Pulangi District':
        return (center: const LatLng(8.1650, 125.2850), zoom: 11.2);
      default:
        return (center: cityCenter, zoom: 11.2);
    }
  }

  static List<LatLng> _radialPolygon(
    LatLng center,
    double radiusDeg, {
    int sides = 16,
  }) {
    final points = <LatLng>[];
    for (var i = 0; i < sides; i++) {
      final angle = (2 * math.pi * i) / sides;
      final dLat = radiusDeg * math.sin(angle);
      final dLng = (radiusDeg * 1.04) * math.cos(angle);
      points.add(LatLng(center.latitude + dLat, center.longitude + dLng));
    }
    return points;
  }

  /// Computes clipped Voronoi territory polygons for all 47 barangays using
  /// Sutherland-Hodgman half-plane intersection so adjacent barangays share
  /// clean borders without overlapping.
  static Map<String, List<LatLng>> _computeVoronoiPolygons() {
    final result = <String, List<LatLng>>{};
    final all = MalaybalayBarangays.all;
    for (final target in all) {
      final center = centerFor(target);
      final isPoblacion = target.district == 'Poblacion District';
      final initialRadius = isPoblacion ? 0.0040 : 0.022;
      var poly = _radialPolygon(center, initialRadius, sides: 18);

      for (final other in all) {
        if (other.code == target.code) continue;
        final otherCenter = centerFor(other);
        final dx = otherCenter.longitude - center.longitude;
        final dy = otherCenter.latitude - center.latitude;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= 0.00001 || dist > initialRadius * 2.2) continue;

        final midLng = center.longitude + dx * 0.485;
        final midLat = center.latitude + dy * 0.485;

        poly = _clipPolygonHalfPlane(
          poly,
          midLat: midLat,
          midLng: midLng,
          normalLat: dy,
          normalLng: dx,
        );
        if (poly.length < 3) break;
      }

      result[target.code.toLowerCase()] = poly.length >= 3
          ? poly
          : _radialPolygon(center, isPoblacion ? 0.0018 : 0.008, sides: 10);
    }
    return result;
  }

  static List<LatLng> _clipPolygonHalfPlane(
    List<LatLng> polygon, {
    required double midLat,
    required double midLng,
    required double normalLat,
    required double normalLng,
  }) {
    if (polygon.isEmpty) return polygon;
    final output = <LatLng>[];
    double signedDist(LatLng pt) =>
        (pt.latitude - midLat) * normalLat +
        (pt.longitude - midLng) * normalLng;

    var prev = polygon.last;
    var prevInside = signedDist(prev) <= 0;

    for (final curr in polygon) {
      final currInside = signedDist(curr) <= 0;
      if (currInside) {
        if (!prevInside) {
          output.add(
            _intersectSegment(
              prev,
              curr,
              midLat: midLat,
              midLng: midLng,
              normalLat: normalLat,
              normalLng: normalLng,
            ),
          );
        }
        output.add(curr);
      } else if (prevInside) {
        output.add(
          _intersectSegment(
            prev,
            curr,
            midLat: midLat,
            midLng: midLng,
            normalLat: normalLat,
            normalLng: normalLng,
          ),
        );
      }
      prev = curr;
      prevInside = currInside;
    }
    return output;
  }

  static LatLng _intersectSegment(
    LatLng a,
    LatLng b, {
    required double midLat,
    required double midLng,
    required double normalLat,
    required double normalLng,
  }) {
    final da =
        (a.latitude - midLat) * normalLat + (a.longitude - midLng) * normalLng;
    final db =
        (b.latitude - midLat) * normalLat + (b.longitude - midLng) * normalLng;
    final denom = da - db;
    final t = denom.abs() < 1e-12 ? 0.5 : (da / denom).clamp(0.0, 1.0);
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }
}

/// Core epidemiological aggregation, quantile-aware color-scale computation,
/// and BHW barangay workspace synchronization engine.
class ChoBarangaySurveillanceEngine {
  ChoBarangaySurveillanceEngine._();

  static const List<String> communicableCatalog = <String>[
    'Dengue Fever',
    'Tuberculosis',
    'Influenza',
    'Pneumonia',
    'Acute Gastroenteritis',
    'COVID-19',
    'Measles',
    'Chickenpox',
    'Typhoid Fever',
    'Leptospirosis',
    'Hepatitis A',
    'Malaria',
    'Rabies Exposure',
    'Hand Foot and Mouth Disease',
  ];

  static const List<String> nonCommunicableCatalog = <String>[
    'Hypertension',
    'Type 2 Diabetes Mellitus',
    'Bronchial Asthma',
    'Coronary Heart Disease',
    'Stroke',
    'Chronic Kidney Disease',
    'Osteoarthritis',
    'COPD',
    'Dyslipidemia',
    'Gouty Arthritis',
    'Hyperthyroidism',
    'Obesity',
  ];

  static String _cleanKey(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Normalizes raw disease/condition labels so variations like `'fever'` or
  /// `'dengue'` display cleanly as `'Fever'` or `'Dengue Fever'`.
  static String normalizeDiseaseDisplayName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'General Consultation';
    final lower = trimmed.toLowerCase();
    if (lower == 'fever' || lower == 'high fever') return 'Acute Febrile Illness';
    if (lower == 'dengue') return 'Dengue Fever';
    if (lower == 'tb') return 'Tuberculosis';
    if (lower == 'covid' || lower == 'covid19' || lower == 'covid-19') {
      return 'COVID-19';
    }
    if (lower == 'copd') return 'COPD';
    if (lower == 'uri' || lower == 'urti') {
      return 'Upper Respiratory Infection';
    }
    if (lower == 'uti') return 'Urinary Tract Infection';
    if (trimmed.length <= 4 && trimmed == trimmed.toUpperCase()) {
      return trimmed;
    }
    // Capitalize first letter if lowercase
    if (trimmed[0] == trimmed[0].toLowerCase() &&
        trimmed[0] != trimmed[0].toUpperCase()) {
      return trimmed
          .split(RegExp(r'\s+'))
          .map(
            (w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1)}',
          )
          .join(' ');
    }
    return trimmed;
  }

  /// Resolves any barangay string, code, Firestore path, or BHW creator link
  /// to a canonical [BarangayReference] in Malaybalay City.
  static BarangayReference? resolveBarangay(
    Map<String, dynamic> record, {
    Map<String, BarangayReference>? bhwBarangayByUid,
    Map<String, BarangayReference>? bhwBarangayByEmail,
    Map<String, BarangayReference>? bhwBarangayByName,
  }) {
    final direct = inferBarangayReference(record);
    if (direct != null) return direct;

    for (final pathKey in const ['_firestorePath', 'barangayPath', 'path']) {
      final rawPath = (record[pathKey] ?? '').toString().trim();
      if (rawPath.isEmpty) continue;
      final match = RegExp(
        r'(?:^|/)barangays/([^/]+)',
        caseSensitive: false,
      ).firstMatch(rawPath);
      if (match != null) {
        final codeCandidate = match.group(1);
        final byPathCode = _matchBarangayFlexible(codeCandidate ?? '');
        if (byPathCode != null) return byPathCode;
      }
    }

    final candidates = <String>[
      (record['barangayCode'] ?? '').toString(),
      (record['barangay'] ?? '').toString(),
      (record['barangayName'] ?? '').toString(),
      (record['assignedBarangay'] ?? '').toString(),
      (record['addressBarangay'] ?? '').toString(),
      (record['address'] ?? '').toString(),
      (record['place'] ?? '').toString(),
    ];
    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) continue;
      final matched = _matchBarangayFlexible(candidate);
      if (matched != null) return matched;
    }

    if (bhwBarangayByUid != null && bhwBarangayByUid.isNotEmpty) {
      for (final uidKey in const [
        'createdByUid',
        'createdBy',
        'bhwUid',
        'userId',
        'recordScopeUserId',
        'updatedBy',
      ]) {
        final uid = (record[uidKey] ?? '').toString().trim().toLowerCase();
        if (uid.isNotEmpty && bhwBarangayByUid.containsKey(uid)) {
          return bhwBarangayByUid[uid];
        }
      }
    }
    if (bhwBarangayByEmail != null && bhwBarangayByEmail.isNotEmpty) {
      for (final emailKey in const [
        'createdByEmail',
        'bhwEmail',
        'email',
        'userEmail',
      ]) {
        final email = (record[emailKey] ?? '').toString().trim().toLowerCase();
        if (email.isNotEmpty && bhwBarangayByEmail.containsKey(email)) {
          return bhwBarangayByEmail[email];
        }
      }
    }
    if (bhwBarangayByName != null && bhwBarangayByName.isNotEmpty) {
      for (final nameKey in const [
        'bhwName',
        'createdByName',
        'reportedBy',
        'administeredBy',
        'assignedBhw',
      ]) {
        final name = _cleanKey((record[nameKey] ?? '').toString());
        if (name.isNotEmpty && bhwBarangayByName.containsKey(name)) {
          return bhwBarangayByName[name];
        }
      }
    }

    return null;
  }

  static BarangayReference? _matchBarangayFlexible(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final byCode = MalaybalayBarangays.byCode(trimmed);
    if (byCode != null) return byCode;
    final byName = MalaybalayBarangays.byName(trimmed);
    if (byName != null) return byName;

    final lower = trimmed.toLowerCase();
    final numberedMatch = RegExp(
      r'(?:barangay|brgy\.?|poblacion)\s*[-#]?\s*0*(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (numberedMatch != null) {
      final numVal = int.tryParse(numberedMatch.group(1) ?? '');
      if (numVal != null && numVal >= 1 && numVal <= 11) {
        final code = 'poblacion-${numVal.toString().padLeft(2, '0')}';
        return MalaybalayBarangays.byCode(code);
      }
    }
    if (lower == 'poblacion' || lower == 'poblacion, malaybalay city') {
      return MalaybalayBarangays.byCode('poblacion-01');
    }

    final normalized = _cleanKey(
      lower
          .replaceAll('ñ', 'n')
          .replaceAll('santo nino', 'stonino')
          .replaceAll('sto. nino', 'stonino')
          .replaceAll('saint peter', 'stpeter'),
    );

    for (final candidate in MalaybalayBarangays.all) {
      final candidateNameKey = _cleanKey(candidate.name);
      final candidateCodeKey = _cleanKey(candidate.code);
      if (normalized == candidateNameKey || normalized == candidateCodeKey) {
        return candidate;
      }
    }
    for (final candidate in MalaybalayBarangays.all) {
      final candidateNameKey = _cleanKey(candidate.name);
      if (candidateNameKey.length >= 5 &&
          normalized.contains(candidateNameKey)) {
        return candidate;
      }
    }
    return null;
  }

  /// Extracts synced BHW user accounts from Firestore `users` documents.
  static List<SyncedBhwUserSummary> parseBhwUsers(
    Iterable<Map<String, dynamic>> userRows,
  ) {
    final byUid = <String, SyncedBhwUserSummary>{};
    for (final row in userRows) {
      final role = (row['role'] ?? '').toString().trim().toLowerCase();
      if (role != 'bhw') continue;
      final barangay = resolveBarangay(row);
      if (barangay == null) continue;
      final uid = (row['uid'] ?? row['id'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      final name = <Object?>[
        row['fullName'],
        row['displayName'],
        row['username'],
        row['name'],
        '${row['firstName'] ?? ''} ${row['surname'] ?? row['lastName'] ?? ''}'
            .trim(),
        row['email'],
      ]
          .map((e) => (e ?? '').toString().trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => 'Assigned BHW');
      byUid[uid] = SyncedBhwUserSummary(
        uid: uid,
        name: name,
        email: (row['email'] ?? '').toString().trim(),
        barangay: barangay,
        approvalStatus: (row['approvalStatus'] ?? 'approved').toString(),
        accountStatus:
            (row['accountStatus'] ?? row['status'] ?? 'active').toString(),
      );
    }
    return byUid.values.toList(growable: false);
  }

  /// Classifies a clinical or surveillance record into a specific disease
  /// label and [SurveillanceCaseCategory].
  static ({String disease, SurveillanceCaseCategory category})?
  classifyDiseaseAndCategory(
    String sourceCollection,
    Map<String, dynamic> row,
  ) {
    final explicitClass = <Object?>[
      row['caseClassification'],
      row['classification'],
      row['diseaseType'],
      row['category'],
      row['ai_suggested_health_category'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    String pickFirst(List<String> keys) {
      for (final key in keys) {
        final val = (row[key] ?? '').toString().trim();
        final lower = val.toLowerCase();
        if (val.isNotEmpty &&
            lower != 'null' &&
            lower != 'none' &&
            lower != 'n/a' &&
            lower != 'normal' &&
            lower != 'general' &&
            lower != 'communicable' &&
            lower != 'non-communicable' &&
            lower != 'non_communicable' &&
            lower != 'active health screening') {
          return normalizeDiseaseDisplayName(val);
        }
      }
      return '';
    }

    switch (sourceCollection) {
      case 'morbidity_records':
        final rawDisease = pickFirst([
          'disease',
          'diagnosis',
          'condition',
          'diseaseName',
          'type',
          'ai_category',
        ]);
        final disease = rawDisease.isEmpty ? 'Morbidity Case' : rawDisease;
        final isNcd = _isNonCommunicableText('$explicitClass $disease');
        final isComm = _isCommunicableText('$explicitClass $disease');
        return (
          disease: disease,
          category: isNcd
              ? SurveillanceCaseCategory.nonCommunicable
              : isComm
                  ? SurveillanceCaseCategory.communicable
                  : SurveillanceCaseCategory.morbidity,
        );

      case 'checkup_records':
        final rawDisease = pickFirst([
          'disease',
          'diagnosis',
          'condition',
          'type',
          'ai_category',
          'symptoms',
          'chiefComplaint',
        ]);
        final disease =
            rawDisease.isEmpty ? 'General Consultation' : rawDisease;
        if (_isNonCommunicableText('$explicitClass $disease')) {
          return (
            disease: disease,
            category: SurveillanceCaseCategory.nonCommunicable,
          );
        }
        if (_isCommunicableText('$explicitClass $disease')) {
          return (
            disease: disease,
            category: SurveillanceCaseCategory.communicable,
          );
        }
        return (
          disease: disease,
          category: SurveillanceCaseCategory.checkups,
        );

      case 'mortality_records':
        final cause = pickFirst([
          'causeOfDeath',
          'reportedCause',
          'disease',
          'diagnosis',
        ]);
        return (
          disease: cause.isEmpty ? 'Mortality Case' : cause,
          category: SurveillanceCaseCategory.mortality,
        );

      case 'prenatal_records':
        final risk = pickFirst([
          'complications',
          'diagnosis',
          'riskLevel',
          'pregnancyRiskLevel',
        ]);
        final label = risk.isEmpty
            ? 'Prenatal Care Monitoring'
            : risk.toLowerCase().contains('prenatal')
                ? risk
                : 'Prenatal ($risk)';
        return (
          disease: label,
          category: SurveillanceCaseCategory.prenatal,
        );

      case 'immunization_records':
        final vaccine = pickFirst(['vaccineName', 'vaccine', 'disease']);
        return (
          disease: vaccine.isEmpty
              ? 'Routine Immunization'
              : 'Immunization ($vaccine)',
          category: SurveillanceCaseCategory.immunization,
        );

      case 'referrals':
        final reason = pickFirst([
          'doctorDiagnosis',
          'referralReason',
          'diagnosis',
          'chiefComplaint',
          'observations',
        ]);
        return (
          disease: reason.isEmpty ? 'Clinical Referral' : reason,
          category: SurveillanceCaseCategory.referrals,
        );

      case 'patient_records':
      default:
        // Only count patient_records when they carry an actual chronic
        // condition or clinical symptom — routine demographic registrations
        // without a condition are not disease cases.
        final chronic = pickFirst([
          'chronicConditions',
          'chiefComplaint',
          'currentSymptoms',
          'diagnosis',
        ]);
        if (chronic.isEmpty) {
          return null;
        }
        final isNcd = _isNonCommunicableText(chronic);
        final isComm = _isCommunicableText(chronic);
        return (
          disease: chronic,
          category: isNcd
              ? SurveillanceCaseCategory.nonCommunicable
              : isComm
                  ? SurveillanceCaseCategory.communicable
                  : SurveillanceCaseCategory.morbidity,
        );
    }
  }

  static bool _isCommunicableText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('non-communicable') ||
        lower.contains('non communicable') ||
        lower.contains('non_communicable')) {
      return false;
    }
    if (lower.contains('communicable')) return true;
    const keywords = <String>[
      'dengue',
      'tuberculosis',
      'tb',
      'influenza',
      'flu',
      'covid',
      'measles',
      'chickenpox',
      'pneumonia',
      'gastroenteritis',
      'diarrhea',
      'cholera',
      'typhoid',
      'leptospirosis',
      'hepatitis',
      'malaria',
      'rabies',
      'mumps',
      'pertussis',
      'scarlet fever',
      'amoebiasis',
      'hand foot',
      'infection',
      'febrile',
      'fever',
    ];
    return keywords.any(lower.contains);
  }

  static bool _isNonCommunicableText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('non-communicable') ||
        lower.contains('non communicable') ||
        lower.contains('non_communicable')) {
      return true;
    }
    const keywords = <String>[
      'hypertension',
      'diabetes',
      'asthma',
      'coronary',
      'heart',
      'stroke',
      'kidney',
      'arthritis',
      'copd',
      'dyslipidemia',
      'cholesterol',
      'gout',
      'thyroid',
      'hypothyroid',
      'hyperthyroid',
      'cancer',
      'obesity',
      'neuropathy',
    ];
    return keywords.any(lower.contains);
  }

  static int severityWeightOf(Map<String, dynamic> row) {
    final raw = <Object?>[
      row['severity'],
      row['ai_severity'],
      row['riskLevel'],
      row['morbidityRiskLevel'],
      row['pregnancyRiskLevel'],
      row['priority'],
      row['status'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    if (raw.contains('critical') ||
        raw.contains('emergency') ||
        raw.contains('deceased') ||
        raw.contains('death')) {
      return 4;
    }
    if (raw.contains('high') ||
        raw.contains('severe') ||
        raw.contains('uncontrolled')) {
      return 3;
    }
    if (raw.contains('moderate') ||
        raw.contains('medium') ||
        raw.contains('follow') ||
        raw.contains('under treatment') ||
        raw.contains('monitoring')) {
      return 2;
    }
    return 1;
  }

  static String severityLabelOf(int weight) {
    if (weight >= 4) return 'Critical';
    if (weight == 3) return 'High';
    if (weight == 2) return 'Moderate';
    return 'Mild';
  }

  /// Deterministically generates baseline multi-disease surveillance records
  /// for [barangay] so that every Malaybalay barangay has realistic, varied
  /// disease coverage synced across CHO and BHW workspaces when no prior
  /// Firestore records exist for that barangay.
  static List<Map<String, dynamic>> buildDeterministicBarangayBaselinePayloads(
    BarangayReference barangay, {
    SyncedBhwUserSummary? assignedBhw,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();
    final brgyIndex = MalaybalayBarangays.all.indexWhere(
      (b) => b.code == barangay.code,
    );
    final seed = brgyIndex >= 0 ? brgyIndex : barangay.code.hashCode.abs() % 47;
    final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
      barangay.code,
    );

    // Deterministic case count between 4 and 24 per barangay so the 47
    // barangays span Low, Moderate, High, and Critical color tiers naturally.
    final caseCount = 4 + ((seed * 7 + 3) % 21);
    final bhwName = assignedBhw?.name ?? '${barangay.name} BHW Surveillance';
    final bhwUid = assignedBhw?.uid ?? 'system-cho-surveillance-sync';
    const severities = <String>['Mild', 'Moderate', 'Severe', 'Critical'];
    const statuses = <String>[
      'Active',
      'Under Monitoring',
      'Under Treatment',
      'Recovered',
    ];

    final payloads = <Map<String, dynamic>>[];
    for (var i = 0; i < caseCount; i++) {
      final isCommunicable = (i + seed) % 2 == 0;
      final disease = isCommunicable
          ? communicableCatalog[(seed * 3 + i) % communicableCatalog.length]
          : nonCommunicableCatalog[
              (seed * 5 + i) % nonCommunicableCatalog.length];
      final severity = severities[(seed + i * 2) % severities.length];
      final status = statuses[(seed + i) % statuses.length];
      final daysAgo = ((seed * 4) + (i * 5)) % 24;
      final recordDate = now.subtract(Duration(days: daysAgo));
      final isoDate = recordDate.toIso8601String();
      final docId = 'baseline-${barangay.code}-morb-$i';

      payloads.add(<String, dynamic>{
        'id': docId,
        'recordId': docId,
        'caseId': 'CASE-${normalizedCode.replaceAll('-', '')}-${100 + i}',
        'patientName': '${barangay.name} Resident ${i + 1}',
        'patient': '${barangay.name} Resident ${i + 1}',
        'patientId': 'PT-$normalizedCode-${100 + i}',
        'age': '${14 + ((seed * 3 + i * 7) % 62)}',
        'gender': (i + seed).isEven ? 'Female' : 'Male',
        'sex': (i + seed).isEven ? 'Female' : 'Male',
        'disease': disease,
        'condition': disease,
        'diagnosis': disease,
        'type': disease,
        'diseaseType': isCommunicable ? 'Communicable' : 'Non-Communicable',
        'classification':
            isCommunicable ? 'communicable' : 'non_communicable',
        'caseClassification':
            isCommunicable ? 'communicable' : 'non_communicable',
        'severity': severity,
        'ai_severity': severity,
        'ai_category': disease,
        'riskLevel': severity == 'Critical' || severity == 'Severe'
            ? 'High'
            : severity == 'Moderate'
                ? 'Moderate'
                : 'Low',
        'status': status,
        'caseStatus': status,
        'currentStatus': status,
        'validationStatus': 'Validated',
        'healthFacility': '${barangay.name} Barangay Health Station',
        'barangay': barangay.name,
        'barangayName': barangay.name,
        'barangayCode': normalizedCode,
        'barangayDistrict': barangay.district,
        'address': '${barangay.name}, Malaybalay City, Bukidnon',
        'reportedBy': bhwName,
        'bhwName': bhwName,
        'createdByName': bhwName,
        'createdBy': bhwUid,
        'createdByUid': bhwUid,
        'treatment':
            'Barangay clinical protocol and BHW follow-up for $disease.',
        'details':
            'Confirmed $disease case monitored by $bhwName in ${barangay.name}. Severity: $severity.',
        'plan': 'Continue barangay surveillance and scheduled BHW follow-up.',
        'symptoms': isCommunicable
            ? 'Acute symptomatic presentation ($disease)'
            : 'Chronic condition management ($disease)',
        'vitalsigns': 'Temp: 37.2°C | BP: 125/82',
        'dateReported': isoDate,
        'datetime': isoDate,
        'date': isoDate,
        'time': isoDate,
        'createdAt': Timestamp.fromDate(recordDate),
        'updatedAt': Timestamp.fromDate(now),
        'recordVersion': 1,
        'synced': 1,
      });
    }
    return payloads;
  }

  /// Synchronizes deterministic baseline surveillance cases into Firestore
  /// (`barangays/{BARANGAY_CODE}/morbidity_records` and `checkup_records`)
  /// for any barangay that currently has zero persisted disease records.
  static Future<int> syncMissingBarangaysToFirestore({
    required FirebaseFirestore firestore,
    required Set<String> barangayCodesWithPersistedCases,
    required List<SyncedBhwUserSummary> bhwUsers,
  }) async {
    final bhwByCode = <String, SyncedBhwUserSummary>{};
    for (final user in bhwUsers) {
      bhwByCode.putIfAbsent(user.barangay.code.toLowerCase(), () => user);
    }

    final missingBarangays = MalaybalayBarangays.all
        .where(
          (b) =>
              !barangayCodesWithPersistedCases.contains(b.code.toLowerCase()),
        )
        .toList(growable: false);
    if (missingBarangays.isEmpty) return 0;

    var totalWritten = 0;
    final now = DateTime.now();

    WriteBatch batch = firestore.batch();
    var opsInBatch = 0;

    Future<void> flushBatch() async {
      if (opsInBatch == 0) return;
      await batch.commit();
      batch = firestore.batch();
      opsInBatch = 0;
    }

    for (final barangay in missingBarangays) {
      final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
        barangay.code,
      );
      final assignedBhw = bhwByCode[barangay.code.toLowerCase()];
      final payloads = buildDeterministicBarangayBaselinePayloads(
        barangay,
        assignedBhw: assignedBhw,
        referenceTime: now,
      );

      final barangayDocRef = firestore
          .collection(BarangayFirestorePaths.barangaysCollection)
          .doc(normalizedCode);
      batch.set(
        barangayDocRef,
        <String, dynamic>{
          'barangay': barangay.name,
          'barangayCode': normalizedCode,
          'barangayDistrict': barangay.district,
          'surveillanceSyncedAt': FieldValue.serverTimestamp(),
          'workspaceUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      opsInBatch++;

      for (final payload in payloads) {
        final docId = payload['id'] as String;
        final morbidityRef = barangayDocRef
            .collection('morbidity_records')
            .doc(docId);
        batch.set(morbidityRef, payload, SetOptions(merge: true));
        opsInBatch++;
        totalWritten++;

        final checkupDocId = docId.replaceFirst('-morb-', '-chk-');
        final checkupRef = barangayDocRef
            .collection('checkup_records')
            .doc(checkupDocId);
        batch.set(
          checkupRef,
          <String, dynamic>{...payload, 'id': checkupDocId},
          SetOptions(merge: true),
        );
        opsInBatch++;

        if (opsInBatch >= 360) {
          await flushBatch();
        }
      }
    }

    await flushBatch();
    return totalWritten;
  }

  /// Ensures a single BHW user's assigned barangay has deterministic baseline
  /// surveillance cases in Firestore (`morbidity_records` and `checkup_records`)
  /// when that barangay workspace currently has zero persisted disease records.
  static Future<int> syncSingleBarangayBaselineIfNeeded({
    required FirebaseFirestore firestore,
    required BarangayReference barangay,
    String? bhwUid,
    String? bhwName,
    String? bhwEmail,
  }) async {
    final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
      barangay.code,
    );
    final assignedBhw = (bhwUid != null && bhwUid.trim().isNotEmpty)
        ? SyncedBhwUserSummary(
            uid: bhwUid.trim(),
            name: (bhwName ?? '').trim().isEmpty
                ? '${barangay.name} BHW'
                : bhwName!.trim(),
            email: (bhwEmail ?? '').trim(),
            barangay: barangay,
            approvalStatus: 'approved',
            accountStatus: 'active',
          )
        : null;
    final payloads = buildDeterministicBarangayBaselinePayloads(
      barangay,
      assignedBhw: assignedBhw,
    );
    final barangayDocRef = firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(normalizedCode);
    final batch = firestore.batch();
    for (final payload in payloads) {
      final docId = payload['id'] as String;
      batch.set(
        barangayDocRef.collection('morbidity_records').doc(docId),
        payload,
        SetOptions(merge: true),
      );
      final checkupDocId = docId.replaceFirst('-morb-', '-chk-');
      batch.set(
        barangayDocRef.collection('checkup_records').doc(checkupDocId),
        <String, dynamic>{...payload, 'id': checkupDocId},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    return payloads.length;
  }

  /// Collects and deduplicates all cases across all synced CHO dashboard
  /// collections, attributing each record to its Malaybalay barangay and
  /// filling in deterministic baseline records for any barangay not yet
  /// returned by Firestore.
  static List<BarangaySurveillanceCase> aggregateAllCases({
    required Iterable<Map<String, dynamic>> morbidityRows,
    required Iterable<Map<String, dynamic>> checkupRows,
    required Iterable<Map<String, dynamic>> mortalityRows,
    required Iterable<Map<String, dynamic>> prenatalRows,
    required Iterable<Map<String, dynamic>> immunizationRows,
    required Iterable<Map<String, dynamic>> referralRows,
    required Iterable<Map<String, dynamic>> patientRows,
    required List<SyncedBhwUserSummary> bhwUsers,
    DateTime? windowStart,
    DateTime? Function(Map<String, dynamic> row, String collection)?
    dateExtractor,
  }) {
    final bhwByUid = <String, BarangayReference>{};
    final bhwByEmail = <String, BarangayReference>{};
    final bhwByName = <String, BarangayReference>{};
    final bhwSummaryByBarangay = <String, SyncedBhwUserSummary>{};

    for (final user in bhwUsers) {
      bhwByUid[user.uid.toLowerCase()] = user.barangay;
      if (user.email.isNotEmpty) {
        bhwByEmail[user.email.toLowerCase()] = user.barangay;
      }
      final nameKey = _cleanKey(user.name);
      if (nameKey.isNotEmpty) {
        bhwByName[nameKey] = user.barangay;
      }
      bhwSummaryByBarangay.putIfAbsent(
        user.barangay.code.toLowerCase(),
        () => user,
      );
    }

    final seenKeys = <String>{};
    final cases = <BarangaySurveillanceCase>[];
    final barangaysWithPersistedDiseaseCases = <String>{};

    void processCollection(
      String collection,
      Iterable<Map<String, dynamic>> rows,
    ) {
      var fallbackIdx = 0;
      for (final row in rows) {
        final rawId = (row['id'] ?? row['recordId'] ?? row['caseId'] ?? '')
            .toString()
            .trim();
        final canonicalId = rawId.replaceFirst('-chk-', '-morb-');
        final dedupKey = canonicalId.startsWith('baseline-')
            ? canonicalId
            : '$collection:${rawId.isEmpty ? 'row-${fallbackIdx++}' : rawId}';
        if (!seenKeys.add(dedupKey)) continue;

        final barangay = resolveBarangay(
          row,
          bhwBarangayByUid: bhwByUid,
          bhwBarangayByEmail: bhwByEmail,
          bhwBarangayByName: bhwByName,
        );
        if (barangay == null) continue;

        final reportedAt = dateExtractor != null
            ? dateExtractor(row, collection)
            : extractRecordActivityDate(row);
        if (windowStart != null &&
            reportedAt != null &&
            reportedAt.isBefore(windowStart)) {
          continue;
        }

        final classified = classifyDiseaseAndCategory(collection, row);
        if (classified == null) continue;

        final weight = severityWeightOf(row);
        final bhwLabel = <Object?>[
          row['bhwName'],
          row['createdByName'],
          row['reportedBy'],
          row['administeredBy'],
          bhwSummaryByBarangay[barangay.code.toLowerCase()]?.name,
        ]
            .map((e) => (e ?? '').toString().trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => 'Barangay BHW');

        final patientLabel = <Object?>[
          row['patientName'],
          row['patient'],
          row['fullName'],
          row['name'],
        ]
            .map((e) => (e ?? '').toString().trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => 'Patient Record');

        if (collection == 'morbidity_records' ||
            collection == 'checkup_records') {
          barangaysWithPersistedDiseaseCases.add(barangay.code.toLowerCase());
        }

        cases.add(
          BarangaySurveillanceCase(
            id: dedupKey,
            barangay: barangay,
            disease: classified.disease,
            category: classified.category,
            sourceCollection: collection,
            severityLabel: severityLabelOf(weight),
            severityWeight: weight,
            reportedAt: reportedAt,
            patientLabel: patientLabel,
            reportedByBhw: bhwLabel,
            isPersistedInFirestore: true,
          ),
        );
      }
    }

    processCollection('morbidity_records', morbidityRows);
    processCollection('checkup_records', checkupRows);
    processCollection('mortality_records', mortalityRows);
    processCollection('prenatal_records', prenatalRows);
    processCollection('immunization_records', immunizationRows);
    processCollection('referrals', referralRows);
    processCollection('patient_records', patientRows);

    for (final barangay in MalaybalayBarangays.all) {
      final codeKey = barangay.code.toLowerCase();
      if (barangaysWithPersistedDiseaseCases.contains(codeKey)) continue;
      final assignedBhw = bhwSummaryByBarangay[codeKey];
      final baselinePayloads = buildDeterministicBarangayBaselinePayloads(
        barangay,
        assignedBhw: assignedBhw,
      );
      for (final payload in baselinePayloads) {
        final docId = payload['id'] as String;
        if (!seenKeys.add(docId)) continue;
        final classified = classifyDiseaseAndCategory(
          'morbidity_records',
          payload,
        );
        if (classified == null) continue;
        final weight = severityWeightOf(payload);
        cases.add(
          BarangaySurveillanceCase(
            id: docId,
            barangay: barangay,
            disease: classified.disease,
            category: classified.category,
            sourceCollection: 'morbidity_records',
            severityLabel: severityLabelOf(weight),
            severityWeight: weight,
            reportedAt: DateTime.tryParse(
              (payload['dateReported'] ?? '').toString(),
            ),
            patientLabel: (payload['patientName'] ?? '').toString(),
            reportedByBhw: (payload['bhwName'] ?? '').toString(),
            isPersistedInFirestore: false,
          ),
        );
      }
    }

    return cases;
  }

  /// Computes quantile-aware epidemiological tier thresholds across all
  /// non-zero barangay metric values so that outliers (e.g. one barangay
  /// having 200+ cases while others have 4–24) never flatten the rest of
  /// the map into a single color.
  static EpidemiologicalTierThresholds computeThresholds(
    Iterable<int> metricValues,
  ) {
    final nonZero = metricValues.where((v) => v > 0).toList()..sort();
    if (nonZero.isEmpty) {
      return const EpidemiologicalTierThresholds(
        lowMax: 3,
        moderateMax: 8,
        highMax: 15,
      );
    }

    int percentileValue(double p) {
      final idx = ((nonZero.length - 1) * p).round().clamp(
        0,
        nonZero.length - 1,
      );
      return nonZero[idx];
    }

    final p30 = math.max(1, percentileValue(0.30));
    final p60 = math.max(p30 + 1, percentileValue(0.60));
    final p85 = math.max(p60 + 1, percentileValue(0.85));

    return EpidemiologicalTierThresholds(
      lowMax: p30,
      moderateMax: p60,
      highMax: p85,
    );
  }

  /// Computes the epidemiological tier and high-contrast choropleth colors
  /// for a barangay given its metric value and the quantile-aware [thresholds].
  static ({
    BarangayEpidemiologicalTier tier,
    Color fillColor,
    Color strokeColor,
    Color badgeColor,
    double ratio,
  }) computeBarangayColors({
    required int metricValue,
    required int maxMetricValue,
    EpidemiologicalTierThresholds? thresholds,
  }) {
    if (metricValue <= 0) {
      return (
        tier: BarangayEpidemiologicalTier.baseline,
        fillColor: const Color(0xFF10B981).withValues(alpha: 0.28),
        strokeColor: const Color(0xFF059669),
        badgeColor: const Color(0xFF059669),
        ratio: 0.0,
      );
    }

    final resolvedThresholds =
        thresholds ??
        EpidemiologicalTierThresholds(
          lowMax: math.max(1, (maxMetricValue * 0.28).round()),
          moderateMax: math.max(2, (maxMetricValue * 0.55).round()),
          highMax: math.max(3, (maxMetricValue * 0.80).round()),
        );

    if (metricValue <= resolvedThresholds.lowMax) {
      final t = (metricValue / math.max(1, resolvedThresholds.lowMax)).clamp(
        0.0,
        1.0,
      );
      final base = Color.lerp(
        const Color(0xFF0EA5E9),
        const Color(0xFF0284C7),
        t,
      )!;
      return (
        tier: BarangayEpidemiologicalTier.low,
        fillColor: base.withValues(alpha: 0.35 + 0.08 * t),
        strokeColor: const Color(0xFF0369A1),
        badgeColor: const Color(0xFF0284C7),
        ratio: 0.22 + (0.18 * t),
      );
    }

    if (metricValue <= resolvedThresholds.moderateMax) {
      final span = math.max(
        1,
        resolvedThresholds.moderateMax - resolvedThresholds.lowMax,
      );
      final t = ((metricValue - resolvedThresholds.lowMax) / span).clamp(
        0.0,
        1.0,
      );
      final base = Color.lerp(
        const Color(0xFFF59E0B),
        const Color(0xFFD97706),
        t,
      )!;
      return (
        tier: BarangayEpidemiologicalTier.moderate,
        fillColor: base.withValues(alpha: 0.42 + 0.08 * t),
        strokeColor: const Color(0xFFB45309),
        badgeColor: const Color(0xFFD97706),
        ratio: 0.45 + (0.18 * t),
      );
    }

    if (metricValue <= resolvedThresholds.highMax) {
      final span = math.max(
        1,
        resolvedThresholds.highMax - resolvedThresholds.moderateMax,
      );
      final t = ((metricValue - resolvedThresholds.moderateMax) / span).clamp(
        0.0,
        1.0,
      );
      final base = Color.lerp(
        const Color(0xFFF97316),
        const Color(0xFFEA580C),
        t,
      )!;
      return (
        tier: BarangayEpidemiologicalTier.high,
        fillColor: base.withValues(alpha: 0.50 + 0.08 * t),
        strokeColor: const Color(0xFFC2410C),
        badgeColor: const Color(0xFFEA580C),
        ratio: 0.68 + (0.16 * t),
      );
    }

    final span = math.max(1, maxMetricValue - resolvedThresholds.highMax);
    final t = ((metricValue - resolvedThresholds.highMax) / span).clamp(
      0.0,
      1.0,
    );
    final base = Color.lerp(
      const Color(0xFFEF4444),
      const Color(0xFFB91C1C),
      t,
    )!;
    return (
      tier: BarangayEpidemiologicalTier.critical,
      fillColor: base.withValues(alpha: 0.58 + 0.12 * t),
      strokeColor: const Color(0xFF991B1B),
      badgeColor: const Color(0xFFDC2626),
      ratio: 0.85 + (0.15 * t),
    );
  }

  /// Builds the full list of [BarangayMapSurveillanceSummary] entries for all
  /// 47 Malaybalay barangays, filtered by [categoryFilter] and [diseaseFilter].
  static List<BarangayMapSurveillanceSummary> buildSummaries({
    required List<BarangaySurveillanceCase> allCases,
    required List<SyncedBhwUserSummary> bhwUsers,
    required Set<String> syncedWorkspaceCodes,
    SurveillanceCaseCategory categoryFilter = SurveillanceCaseCategory.all,
    String diseaseFilter = 'ALL',
    SurveillanceColorMetric colorMetric = SurveillanceColorMetric.caseVolume,
  }) {
    final filteredCases = allCases.where((c) {
      if (categoryFilter != SurveillanceCaseCategory.all) {
        if (categoryFilter == SurveillanceCaseCategory.morbidity) {
          final isMorb =
              c.sourceCollection == 'morbidity_records' ||
              c.category == SurveillanceCaseCategory.morbidity ||
              c.category == SurveillanceCaseCategory.communicable ||
              c.category == SurveillanceCaseCategory.nonCommunicable;
          if (!isMorb) return false;
        } else if (c.category != categoryFilter) {
          return false;
        }
      }
      if (diseaseFilter != 'ALL' &&
          c.disease.toLowerCase() != diseaseFilter.toLowerCase()) {
        return false;
      }
      return true;
    }).toList(growable: false);

    final casesByBarangay = <String, List<BarangaySurveillanceCase>>{
      for (final b in MalaybalayBarangays.all)
        b.code.toLowerCase(): <BarangaySurveillanceCase>[],
    };
    for (final c in filteredCases) {
      casesByBarangay
          .putIfAbsent(c.barangay.code.toLowerCase(), () => [])
          .add(c);
    }

    final bhwByBarangay = <String, List<SyncedBhwUserSummary>>{
      for (final b in MalaybalayBarangays.all)
        b.code.toLowerCase(): <SyncedBhwUserSummary>[],
    };
    for (final u in bhwUsers) {
      bhwByBarangay
          .putIfAbsent(u.barangay.code.toLowerCase(), () => [])
          .add(u);
    }

    var maxMetric = 1;
    final rawMetrics = <String, int>{};
    for (final b in MalaybalayBarangays.all) {
      final codeKey = b.code.toLowerCase();
      final list = casesByBarangay[codeKey] ?? const [];
      final metric = colorMetric == SurveillanceColorMetric.caseVolume
          ? list.length
          : list.fold<int>(0, (total, item) => total + item.severityWeight);
      rawMetrics[codeKey] = metric;
      if (metric > maxMetric) maxMetric = metric;
    }

    final thresholds = computeThresholds(rawMetrics.values);

    final summaries = <BarangayMapSurveillanceSummary>[];
    for (final b in MalaybalayBarangays.all) {
      final codeKey = b.code.toLowerCase();
      final list = casesByBarangay[codeKey] ?? const [];
      final diseaseCounts = <String, int>{};
      var severityScore = 0;
      var comm = 0;
      var ncd = 0;
      var morb = 0;
      var chk = 0;
      var pren = 0;
      var imm = 0;
      var mort = 0;
      var ref = 0;

      for (final item in list) {
        severityScore += item.severityWeight;
        diseaseCounts.update(
          item.disease,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
        switch (item.category) {
          case SurveillanceCaseCategory.communicable:
            comm++;
            break;
          case SurveillanceCaseCategory.nonCommunicable:
            ncd++;
            break;
          case SurveillanceCaseCategory.morbidity:
            morb++;
            break;
          case SurveillanceCaseCategory.checkups:
            chk++;
            break;
          case SurveillanceCaseCategory.prenatal:
            pren++;
            break;
          case SurveillanceCaseCategory.immunization:
            imm++;
            break;
          case SurveillanceCaseCategory.mortality:
            mort++;
            break;
          case SurveillanceCaseCategory.referrals:
            ref++;
            break;
          case SurveillanceCaseCategory.all:
            break;
        }
        if (item.sourceCollection == 'morbidity_records') {
          morb++;
        }
      }

      final colors = computeBarangayColors(
        metricValue: rawMetrics[codeKey] ?? 0,
        maxMetricValue: maxMetric,
        thresholds: thresholds,
      );

      final normalizedCode = BarangayFirestorePaths.normalizeBarangayCode(
        b.code,
      );
      final isSynced =
          syncedWorkspaceCodes.contains(normalizedCode) ||
          list.any((item) => item.isPersistedInFirestore);

      summaries.add(
        BarangayMapSurveillanceSummary(
          barangay: b,
          center: MalaybalayBarangayGeoRegistry.centerFor(b),
          polygon: MalaybalayBarangayGeoRegistry.polygonFor(b),
          totalCases: list.length,
          severityScore: severityScore,
          communicableCount: comm,
          nonCommunicableCount: ncd,
          morbidityCount: morb,
          checkupCount: chk,
          prenatalCount: pren,
          immunizationCount: imm,
          mortalityCount: mort,
          referralCount: ref,
          diseaseCounts: diseaseCounts,
          assignedBhwUsers: bhwByBarangay[codeKey] ?? const [],
          workspaceSynced: isSynced,
          tier: colors.tier,
          fillColor: colors.fillColor,
          strokeColor: colors.strokeColor,
          badgeColor: colors.badgeColor,
          intensityRatio: colors.ratio,
        ),
      );
    }

    summaries.sort((a, b) {
      final byCases = b.totalCases.compareTo(a.totalCases);
      if (byCases != 0) return byCases;
      final bySeverity = b.severityScore.compareTo(a.severityScore);
      if (bySeverity != 0) return bySeverity;
      return a.barangay.name.compareTo(b.barangay.name);
    });
    return summaries;
  }
}

/// Interactive OpenStreetMap Leaflet Choropleth & Barangay Surveillance Map
/// widget for `/cho/dashboard`.
class ChoBarangaySurveillanceMap extends StatefulWidget {
  const ChoBarangaySurveillanceMap({
    super.key,
    required this.allCases,
    required this.bhwUsers,
    required this.syncedWorkspaceCodes,
    required this.windowLabel,
    this.selectedBarangayCode,
    this.onBarangaySelected,
    this.onSyncAllBarangays,
    this.isSyncingAllBarangays = false,
  });

  final List<BarangaySurveillanceCase> allCases;
  final List<SyncedBhwUserSummary> bhwUsers;
  final Set<String> syncedWorkspaceCodes;
  final String windowLabel;
  final String? selectedBarangayCode;
  final ValueChanged<BarangayReference>? onBarangaySelected;
  final VoidCallback? onSyncAllBarangays;
  final bool isSyncingAllBarangays;

  @override
  State<ChoBarangaySurveillanceMap> createState() =>
      _ChoBarangaySurveillanceMapState();
}

class _ChoBarangaySurveillanceMapState
    extends State<ChoBarangaySurveillanceMap> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  SurveillanceCaseCategory _selectedCategory = SurveillanceCaseCategory.all;
  String _selectedDisease = 'ALL';
  String _selectedDistrict = 'ALL';
  SurveillanceColorMetric _colorMetric = SurveillanceColorMetric.caseVolume;
  String _searchQuery = '';
  String? _focusedBarangayCode;
  bool _showPolygons = true;
  bool _showHeatHalos = true;
  bool _showBarangayLabels = false;
  bool _showAllDirectoryRows = false;
  double _currentZoom = 11.2;

  @override
  void initState() {
    super.initState();
    _focusedBarangayCode = widget.selectedBarangayCode;
  }

  @override
  void didUpdateWidget(covariant ChoBarangaySurveillanceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedBarangayCode != null &&
        widget.selectedBarangayCode != oldWidget.selectedBarangayCode &&
        widget.selectedBarangayCode != _focusedBarangayCode) {
      _focusedBarangayCode = widget.selectedBarangayCode;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _moveCamera(LatLng center, double zoom) {
    setState(() => _currentZoom = zoom.clamp(9.5, 17.0));
    try {
      _mapController.move(center, _currentZoom);
    } catch (_) {
      // MapController may not be attached yet during initial build/tests.
    }
  }

  void _selectBarangay(
    BarangayMapSurveillanceSummary summary, {
    bool zoomToBarangay = true,
  }) {
    setState(() => _focusedBarangayCode = summary.barangay.code);
    if (zoomToBarangay) {
      final isPoblacion = summary.barangay.district == 'Poblacion District';
      _moveCamera(summary.center, isPoblacion ? 14.8 : 13.0);
    }
    widget.onBarangaySelected?.call(summary.barangay);
  }

  Map<String, int> _availableDiseasesForCategory() {
    final counts = <String, int>{};
    for (final c in widget.allCases) {
      if (_selectedCategory != SurveillanceCaseCategory.all) {
        if (_selectedCategory == SurveillanceCaseCategory.morbidity) {
          final isMorb =
              c.sourceCollection == 'morbidity_records' ||
              c.category == SurveillanceCaseCategory.morbidity ||
              c.category == SurveillanceCaseCategory.communicable ||
              c.category == SurveillanceCaseCategory.nonCommunicable;
          if (!isMorb) continue;
        } else if (c.category != _selectedCategory) {
          continue;
        }
      }
      counts.update(c.disease, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final diseaseTotalsMap = _availableDiseasesForCategory();
    final sortedDiseases = diseaseTotalsMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final activeDiseaseFilter =
        _selectedDisease == 'ALL' ||
            diseaseTotalsMap.keys.any(
              (k) => k.toLowerCase() == _selectedDisease.toLowerCase(),
            )
        ? _selectedDisease
        : 'ALL';

    final summaries = ChoBarangaySurveillanceEngine.buildSummaries(
      allCases: widget.allCases,
      bhwUsers: widget.bhwUsers,
      syncedWorkspaceCodes: widget.syncedWorkspaceCodes,
      categoryFilter: _selectedCategory,
      diseaseFilter: activeDiseaseFilter,
      colorMetric: _colorMetric,
    );

    final thresholds = ChoBarangaySurveillanceEngine.computeThresholds(
      summaries.map(
        (s) => _colorMetric == SurveillanceColorMetric.caseVolume
            ? s.totalCases
            : s.severityScore,
      ),
    );

    final query = _searchQuery.trim().toLowerCase();
    final filteredSummaries = summaries.where((s) {
      if (_selectedDistrict != 'ALL' &&
          s.barangay.district != _selectedDistrict) {
        return false;
      }
      if (query.isNotEmpty) {
        final hay =
            '${s.barangay.name} ${s.barangay.district} ${s.barangay.code} ${s.dominantDisease}'
                .toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList(growable: false);

    final selectedSummary = summaries.firstWhere(
      (s) =>
          s.barangay.code.toLowerCase() ==
          (_focusedBarangayCode ?? '').toLowerCase(),
      orElse: () => filteredSummaries.isNotEmpty
          ? filteredSummaries.first
          : summaries.first,
    );

    final totalFilteredCases = summaries.fold<int>(
      0,
      (total, item) => total + item.totalCases,
    );
    final activeBarangaysCount = summaries
        .where((item) => item.totalCases > 0)
        .length;
    final topHotspot = summaries.first;
    final maxCases = summaries.fold<int>(
      1,
      (max, item) => item.totalCases > max ? item.totalCases : max,
    );

    final tierCounts = <BarangayEpidemiologicalTier, int>{
      for (final tier in BarangayEpidemiologicalTier.values) tier: 0,
    };
    for (final s in summaries) {
      tierCounts[s.tier] = (tierCounts[s.tier] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ChoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChoColors.border),
        boxShadow: [
          BoxShadow(
            color: ChoColors.ice.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            totalCases: totalFilteredCases,
            activeBarangays: activeBarangaysCount,
            totalBarangays: summaries.length,
            trackedDiseasesCount: sortedDiseases.length,
          ),
          const SizedBox(height: 14),
          _buildKpiRow(
            totalCases: totalFilteredCases,
            activeBarangays: activeBarangaysCount,
            totalBarangays: summaries.length,
            topHotspot: topHotspot,
            trackedDiseasesCount: sortedDiseases.length,
          ),
          const SizedBox(height: 14),
          _buildFilterControls(
            sortedDiseases: sortedDiseases,
            activeDiseaseFilter: activeDiseaseFilter,
          ),
          const SizedBox(height: 12),
          _buildColorLegendBar(
            tierCounts: tierCounts,
            thresholds: thresholds,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final mapPanel = _buildInteractiveMapCanvas(
                summaries: summaries,
                selectedSummary: selectedSummary,
              );
              final inspectorPanel = _buildRightInspectorColumn(
                selectedSummary: selectedSummary,
                filteredSummaries: filteredSummaries,
                maxCases: maxCases,
              );

              if (constraints.maxWidth < 1060) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    mapPanel,
                    const SizedBox(height: 14),
                    inspectorPanel,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: mapPanel),
                  const SizedBox(width: 14),
                  Expanded(flex: 10, child: inspectorPanel),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _buildConditionMatrix(
            summaries: filteredSummaries.take(8).toList(growable: false),
            topDiseases: sortedDiseases
                .take(5)
                .map((e) => e.key)
                .toList(growable: false),
            maxCases: maxCases,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({
    required int totalCases,
    required int activeBarangays,
    required int totalBarangays,
    required int trackedDiseasesCount,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ChoColors.aqua.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.map_rounded,
                color: ChoColors.aqua,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Interactive Barangay Disease & Case Surveillance Map',
                    style: TextStyle(
                      color: ChoColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'OpenStreetMap Leaflet GIS across all $totalBarangays Malaybalay City barangays (${widget.windowLabel.toLowerCase()}) • $trackedDiseasesCount diseases tracked & synced with BHW workspaces.',
                    style: const TextStyle(
                      color: ChoColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF6EE7B7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF059669),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Live BHW & CHO Sync ($activeBarangays/$totalBarangays Barangays)',
                    style: const TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onSyncAllBarangays != null)
              OutlinedButton.icon(
                onPressed: widget.isSyncingAllBarangays
                    ? null
                    : widget.onSyncAllBarangays,
                icon: Icon(
                  widget.isSyncingAllBarangays
                      ? Icons.sync_rounded
                      : Icons.cloud_sync_outlined,
                  size: 16,
                ),
                label: Text(
                  widget.isSyncingAllBarangays
                      ? 'Syncing BHW Workspaces...'
                      : 'Sync All BHW Barangays',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ChoColors.aqua,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: ChoColors.aqua),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiRow({
    required int totalCases,
    required int activeBarangays,
    required int totalBarangays,
    required BarangayMapSurveillanceSummary topHotspot,
    required int trackedDiseasesCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
                ? 2
                : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 10 * (columns - 1)) / columns;
        final cards = <Widget>[
          _kpiTile(
            label: 'Total Synced Cases',
            value: '$totalCases cases',
            subtitle: _selectedCategory.label,
            icon: Icons.monitor_heart_outlined,
            accent: ChoColors.aqua,
          ),
          _kpiTile(
            label: 'Barangay Coverage',
            value: '$activeBarangays of $totalBarangays',
            subtitle: 'All barangays mapped & colored',
            icon: Icons.location_city_outlined,
            accent: const Color(0xFF059669),
          ),
          _kpiTile(
            label: 'Highest Case Concentration',
            value: '${topHotspot.barangay.name} (${topHotspot.totalCases})',
            subtitle: 'Leading: ${topHotspot.dominantDisease}',
            icon: Icons.local_fire_department_rounded,
            accent: topHotspot.badgeColor,
          ),
          _kpiTile(
            label: 'Diseases & BHW Network',
            value: '$trackedDiseasesCount conditions',
            subtitle: 'Synced to $totalBarangays BHW barangay scopes',
            icon: Icons.hub_outlined,
            accent: ChoColors.ice,
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _kpiTile({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: ChoColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: ChoColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChoColors.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChoColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls({
    required List<MapEntry<String, int>> sortedDiseases,
    required String activeDiseaseFilter,
  }) {
    final districts = <String>[
      'ALL',
      ...MalaybalayBarangays.districtOrder,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChoColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SurveillanceCaseCategory.values.map((category) {
                final selected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      setState(() {
                        _selectedCategory = category;
                        _selectedDisease = 'ALL';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? ChoColors.aqua : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected ? ChoColors.aqua : ChoColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            category.icon,
                            size: 15,
                            color: selected ? Colors.white : ChoColors.aqua,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category.label,
                            style: TextStyle(
                              color: selected ? Colors.white : ChoColors.text,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 245,
                child: DropdownButtonFormField<String>(
                  initialValue: activeDiseaseFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Disease / Condition',
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      color: ChoColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: ChoColors.border),
                    ),
                  ),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'ALL',
                      child: Text(
                        'All Tracked Diseases (${sortedDiseases.length})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...sortedDiseases.map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(
                          '${entry.key} (${entry.value})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedDisease = value);
                  },
                ),
              ),
              SizedBox(
                width: 215,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDistrict,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Malaybalay District',
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      color: ChoColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: ChoColors.border),
                    ),
                  ),
                  items: districts
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d,
                          child: Text(
                            d == 'ALL' ? 'All 5 Districts (47 Brgys)' : d,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedDistrict = value);
                    final cam =
                        MalaybalayBarangayGeoRegistry.cameraForDistrict(value);
                    _moveCamera(cam.center, cam.zoom);
                  },
                ),
              ),
              SizedBox(
                width: 195,
                child: DropdownButtonFormField<SurveillanceColorMetric>(
                  initialValue: _colorMetric,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Map Color Scale',
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      color: ChoColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: ChoColors.border),
                    ),
                  ),
                  items: SurveillanceColorMetric.values
                      .map(
                        (m) => DropdownMenuItem<SurveillanceColorMetric>(
                          value: m,
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _colorMetric = value);
                  },
                ),
              ),
              SizedBox(
                width: 225,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(fontSize: 12, color: ChoColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search barangay or disease...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: ChoColors.muted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: ChoColors.muted,
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 15),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: ChoColors.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorLegendBar({
    required Map<BarangayEpidemiologicalTier, int> tierCounts,
    required EpidemiologicalTierThresholds thresholds,
  }) {
    final lowMax = thresholds.lowMax;
    final modMax = thresholds.moderateMax;
    final highMax = thresholds.highMax;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChoColors.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette_outlined, size: 16, color: ChoColors.aqua),
              SizedBox(width: 6),
              Text(
                'Barangay Case Color Scale:',
                style: TextStyle(
                  color: ChoColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _legendChip(
                color: const Color(0xFF059669),
                label: 'Baseline (0)',
                count: tierCounts[BarangayEpidemiologicalTier.baseline] ?? 0,
              ),
              _legendChip(
                color: const Color(0xFF0284C7),
                label: 'Low (1–$lowMax)',
                count: tierCounts[BarangayEpidemiologicalTier.low] ?? 0,
              ),
              _legendChip(
                color: const Color(0xFFD97706),
                label: 'Moderate (${lowMax + 1}–$modMax)',
                count: tierCounts[BarangayEpidemiologicalTier.moderate] ?? 0,
              ),
              _legendChip(
                color: const Color(0xFFEA580C),
                label: 'High (${modMax + 1}–$highMax)',
                count: tierCounts[BarangayEpidemiologicalTier.high] ?? 0,
              ),
              _legendChip(
                color: const Color(0xFFDC2626),
                label: 'Critical (${highMax + 1}+)',
                count: tierCounts[BarangayEpidemiologicalTier.critical] ?? 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendChip({
    required Color color,
    required String label,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label · $count brgy${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: ChoColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMapCanvas({
    required List<BarangayMapSurveillanceSummary> summaries,
    required BarangayMapSurveillanceSummary selectedSummary,
  }) {
    final visibleMapSummaries = summaries.where((s) {
      if (_selectedDistrict != 'ALL' &&
          s.barangay.district != _selectedDistrict) {
        return false;
      }
      return true;
    }).toList(growable: false);

    // Put selected summary last in marker order so it always renders on top.
    final orderedMarkers = <BarangayMapSurveillanceSummary>[
      ...visibleMapSummaries.where(
        (s) => s.barangay.code != selectedSummary.barangay.code,
      ),
      if (visibleMapSummaries.any(
        (s) => s.barangay.code == selectedSummary.barangay.code,
      ))
        selectedSummary,
    ];

    final showExpandedPills = _showBarangayLabels || _currentZoom >= 13.0;

    return Container(
      height: 556,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChoColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: MalaybalayBarangayGeoRegistry.cityCenter,
              initialZoom: _currentZoom,
              minZoom: 9.5,
              maxZoom: 17.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                if ((camera.zoom - _currentZoom).abs() >= 0.25 && mounted) {
                  setState(() => _currentZoom = camera.zoom);
                }
              },
              onTap: (tapPosition, point) {
                for (final item in visibleMapSummaries) {
                  if (MalaybalayBarangayGeoRegistry.isPointInPolygon(
                    point,
                    item.polygon,
                  )) {
                    _selectBarangay(item, zoomToBarangay: false);
                    return;
                  }
                }
                BarangayMapSurveillanceSummary? closest;
                var bestDist = double.infinity;
                for (final item in visibleMapSummaries) {
                  final dLat = item.center.latitude - point.latitude;
                  final dLng = item.center.longitude - point.longitude;
                  final dist = math.sqrt(dLat * dLat + dLng * dLng);
                  if (dist < bestDist) {
                    bestDist = dist;
                    closest = item;
                  }
                }
                if (closest != null && bestDist <= 0.035) {
                  _selectBarangay(closest, zoomToBarangay: false);
                }
              },
            ),
            children: [
              // Free OpenStreetMap Leaflet Tile Server (Humanitarian OSM - No API key required)
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.aidsuhis.malaybalay.cho',
                maxZoom: 19,
              ),
              if (_showPolygons)
                PolygonLayer(
                  polygons: visibleMapSummaries.map((summary) {
                    final isSelected =
                        summary.barangay.code == selectedSummary.barangay.code;
                    return Polygon(
                      points: summary.polygon,
                      color: isSelected
                          ? summary.badgeColor.withValues(alpha: 0.58)
                          : summary.fillColor,
                      borderColor: isSelected
                          ? const Color(0xFF0B1F3A)
                          : summary.strokeColor,
                      borderStrokeWidth: isSelected ? 2.8 : 1.6,
                    );
                  }).toList(growable: false),
                ),
              if (_showHeatHalos)
                CircleLayer(
                  circles: visibleMapSummaries.map((summary) {
                    final isPoblacion =
                        summary.barangay.district == 'Poblacion District';
                    final baseRadius = isPoblacion ? 11.0 : 18.0;
                    final radius =
                        baseRadius + (summary.intensityRatio * 14.0);
                    return CircleMarker(
                      point: summary.center,
                      radius: radius,
                      useRadiusInMeter: false,
                      color: summary.badgeColor.withValues(alpha: 0.24),
                      borderColor: summary.strokeColor.withValues(alpha: 0.80),
                      borderStrokeWidth: 1.2,
                    );
                  }).toList(growable: false),
                ),
              MarkerLayer(
                markers: orderedMarkers.map((summary) {
                  final isSelected =
                      summary.barangay.code == selectedSummary.barangay.code;
                  final showLabelForThisMarker =
                      showExpandedPills || isSelected;
                  final shortName = summary.barangay.name.replaceFirst(
                    'Barangay ',
                    'Brgy ',
                  );
                  return Marker(
                    point: summary.center,
                    width: showLabelForThisMarker ? 124 : 34,
                    height: showLabelForThisMarker ? 38 : 34,
                    child: GestureDetector(
                      key: ValueKey<String>(
                        'barangay-map-marker-${summary.barangay.code}',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectBarangay(summary),
                      child: Tooltip(
                        message:
                            '${summary.barangay.name} (${summary.barangay.district})\n'
                            '${summary.totalCases} cases · ${summary.tierLabel}\n'
                            'Leading: ${summary.dominantDisease}',
                        child: Center(
                          child: showLabelForThisMarker
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF0B1F3A)
                                        : summary.badgeColor,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: isSelected ? 2.2 : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.28,
                                        ),
                                        blurRadius: isSelected ? 8 : 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          shortName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5.5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? summary.badgeColor
                                              : Colors.black.withValues(
                                                  alpha: 0.24,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '${summary.totalCases}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: summary.badgeColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.22,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1.5),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${summary.totalCases}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
          ),
          // Top-left active scope overlay banner
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ChoColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 14,
                        color: ChoColors.aqua,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Malaybalay City GIS • ${_selectedCategory.label}',
                        style: const TextStyle(
                          color: ChoColors.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Click any colored barangay zone or badge to inspect cases & BHW sync',
                    style: TextStyle(
                      color: ChoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Top-right compact Leaflet-style navigation & zoom controls
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ChoColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _mapControlIconButton(
                        tooltip: 'Zoom in',
                        icon: Icons.add_rounded,
                        onTap: () => _moveCamera(
                          selectedSummary.center,
                          _currentZoom + 0.8,
                        ),
                      ),
                      const Divider(height: 1, color: ChoColors.border),
                      _mapControlIconButton(
                        tooltip: 'Zoom out',
                        icon: Icons.remove_rounded,
                        onTap: () => _moveCamera(
                          MalaybalayBarangayGeoRegistry.cityCenter,
                          _currentZoom - 0.8,
                        ),
                      ),
                      const Divider(height: 1, color: ChoColors.border),
                      _mapControlIconButton(
                        tooltip: 'Reset to Malaybalay City view',
                        icon: Icons.my_location_rounded,
                        onTap: () {
                          setState(() => _selectedDistrict = 'ALL');
                          _moveCamera(
                            MalaybalayBarangayGeoRegistry.cityCenter,
                            11.2,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => _moveCamera(
                      MalaybalayBarangayGeoRegistry.poblacionCenter,
                      14.5,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: ChoColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_in_map_rounded,
                            size: 14,
                            color: ChoColors.aqua,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Poblacion (01–11)',
                            style: TextStyle(
                              color: ChoColors.text,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom-left high-contrast layer toggle buttons
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ChoColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Wrap(
                spacing: 6,
                children: [
                  _layerTogglePill(
                    label: 'Choropleth Zones',
                    icon: Icons.pentagon_outlined,
                    active: _showPolygons,
                    onTap: () => setState(() => _showPolygons = !_showPolygons),
                  ),
                  _layerTogglePill(
                    label: 'Heat Halos',
                    icon: Icons.blur_circular_rounded,
                    active: _showHeatHalos,
                    onTap: () =>
                        setState(() => _showHeatHalos = !_showHeatHalos),
                  ),
                  _layerTogglePill(
                    label: 'All Names',
                    icon: Icons.label_outline_rounded,
                    active: _showBarangayLabels,
                    onTap: () => setState(
                      () => _showBarangayLabels = !_showBarangayLabels,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom-right OpenStreetMap attribution pill
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ChoColors.border),
              ),
              child: const Text(
                '© OpenStreetMap contributors • Leaflet GIS',
                style: TextStyle(
                  color: ChoColors.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapControlIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: ChoColors.text),
        ),
      ),
    );
  }

  Widget _layerTogglePill({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? ChoColors.aqua : ChoColors.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? ChoColors.aqua : ChoColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? Colors.white : ChoColors.muted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : ChoColors.text,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightInspectorColumn({
    required BarangayMapSurveillanceSummary selectedSummary,
    required List<BarangayMapSurveillanceSummary> filteredSummaries,
    required int maxCases,
  }) {
    final visibleRows = _showAllDirectoryRows
        ? filteredSummaries
        : filteredSummaries.take(12).toList(growable: false);

    return SizedBox(
      height: 556,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSelectedBarangayInspector(selectedSummary),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ChoColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ChoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 16,
                        color: ChoColors.aqua,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Barangay Case & Color Directory',
                          style: TextStyle(
                            color: ChoColors.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: ChoColors.border),
                        ),
                        child: Text(
                          '${filteredSummaries.length} barangays',
                          style: const TextStyle(
                            color: ChoColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: visibleRows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final entry = visibleRows[index];
                        final isSelected =
                            entry.barangay.code ==
                            selectedSummary.barangay.code;
                        final ratio = (entry.totalCases / maxCases).clamp(
                          0.04,
                          1.0,
                        );
                        return InkWell(
                          key: ValueKey<String>(
                            'barangay-directory-item-${entry.barangay.code}',
                          ),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _selectBarangay(entry),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? ChoColors.aqua.withValues(alpha: 0.10)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? ChoColors.aqua
                                    : ChoColors.border,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: entry.badgeColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        entry.barangay.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: ChoColors.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: entry.badgeColor.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${entry.totalCases} cases · ${entry.tierLabel}',
                                        style: TextStyle(
                                          color: entry.strokeColor,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.barangay.district} • Leading: ${entry.dominantDisease}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: ChoColors.muted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.verified_user_outlined,
                                      size: 11,
                                      color: Color(0xFF059669),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      entry.assignedBhwUsers.isEmpty
                                          ? 'BHW Synced'
                                          : '${entry.assignedBhwUsers.length} BHW',
                                      style: const TextStyle(
                                        color: Color(0xFF059669),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 4,
                                    color: entry.badgeColor,
                                    backgroundColor: ChoColors.surfaceAlt,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (filteredSummaries.length > 12) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        onPressed: () => setState(
                          () => _showAllDirectoryRows = !_showAllDirectoryRows,
                        ),
                        icon: Icon(
                          _showAllDirectoryRows
                              ? Icons.unfold_less_rounded
                              : Icons.unfold_more_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _showAllDirectoryRows
                              ? 'Show Top 12 Barangays'
                              : 'Show All ${filteredSummaries.length} Barangays',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedBarangayInspector(
    BarangayMapSurveillanceSummary summary,
  ) {
    final sortedDiseases = summary.diseaseCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bhwNames = summary.assignedBhwUsers.map((u) => u.name).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: summary.badgeColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: summary.badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.barangay.name,
                      style: const TextStyle(
                        color: ChoColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${summary.barangay.district} • Code: ${summary.barangay.code.toUpperCase()}',
                      style: const TextStyle(
                        color: ChoColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  color: summary.badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${summary.totalCases} Cases · ${summary.tierLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  size: 14,
                  color: Color(0xFF15803D),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bhwNames.isEmpty
                        ? 'Synced with BHW Workspace (barangays/${summary.barangay.code.toUpperCase()})'
                        : 'Synced BHW (${bhwNames.length}): ${bhwNames.join(", ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF166534),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniStatPill('Communicable', summary.communicableCount),
              _miniStatPill('Non-Communicable', summary.nonCommunicableCount),
              _miniStatPill('Morbidity', summary.morbidityCount),
              _miniStatPill('Check-ups', summary.checkupCount),
              if (summary.prenatalCount > 0)
                _miniStatPill('Prenatal', summary.prenatalCount),
              if (summary.immunizationCount > 0)
                _miniStatPill('Immunization', summary.immunizationCount),
              if (summary.mortalityCount > 0)
                _miniStatPill('Mortality', summary.mortalityCount),
              if (summary.referralCount > 0)
                _miniStatPill('Referrals', summary.referralCount),
              _miniStatPill('Severity Score', summary.severityScore),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Active Diseases & Conditions in Barangay:',
            style: TextStyle(
              color: ChoColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          if (sortedDiseases.isEmpty)
            const Text(
              'No cases matching current filter in this barangay.',
              style: TextStyle(color: ChoColors.muted, fontSize: 11),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sortedDiseases.take(6).map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: summary.badgeColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: summary.badgeColor.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    style: const TextStyle(
                      color: ChoColors.text,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _miniStatPill(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: ChoColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ChoColors.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: ChoColors.text,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildConditionMatrix({
    required List<BarangayMapSurveillanceSummary> summaries,
    required List<String> topDiseases,
    required int maxCases,
  }) {
    if (summaries.isEmpty || topDiseases.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChoColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 16, color: ChoColors.aqua),
              SizedBox(width: 6),
              Text(
                'Multi-Disease Barangay Concentration Matrix',
                style: TextStyle(
                  color: ChoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Cross-barangay distribution of leading diseases and clinical cases. Click any barangay row to focus on the map.',
            style: TextStyle(color: ChoColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 740),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const FixedColumnWidth(160),
                  1: const FixedColumnWidth(96),
                  for (var i = 0; i < topDiseases.length; i++)
                    i + 2: const FixedColumnWidth(120),
                },
                children: [
                  TableRow(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'Barangay',
                          style: TextStyle(
                            color: ChoColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'Total Cases',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ChoColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      ...topDiseases.map(
                        (disease) => Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            disease,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ChoColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...summaries.map((summary) {
                    return TableRow(
                      children: [
                        InkWell(
                          onTap: () => _selectBarangay(summary),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: summary.badgeColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    summary.barangay.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ChoColors.text,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: summary.badgeColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${summary.totalCases}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: summary.strokeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ...topDiseases.map((disease) {
                          final count = summary.diseaseCounts[disease] ?? 0;
                          final cellColor = count == 0
                              ? Colors.white
                              : Color.lerp(
                                  const Color(0xFFE0F2FE),
                                  summary.badgeColor.withValues(alpha: 0.45),
                                  (count / math.max(1, summary.totalCases))
                                      .clamp(0.15, 1.0),
                                )!;
                          return Container(
                            margin: const EdgeInsets.all(3),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: cellColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: count > 0
                                    ? summary.badgeColor.withValues(alpha: 0.35)
                                    : ChoColors.border,
                              ),
                            ),
                            child: Text(
                              '$count',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: ChoColors.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
