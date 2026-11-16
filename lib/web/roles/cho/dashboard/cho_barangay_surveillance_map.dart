import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';

/// Epidemiological risk tier used to color barangay polygons, heat halos,
/// map markers, and directory badges based on active case burden.
enum BarangayEpidemiologicalTier { baseline, low, moderate, high, critical }

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

/// Geospatial reference boundaries for all configured Malaybalay City
/// barangays, paired with multi-module disease aggregation and BHW sync.
class MalaybalayBarangayGeoRegistry {
  MalaybalayBarangayGeoRegistry._();

  static const LatLng cityCenter = LatLng(8.1340, 125.1950);
  static const LatLng poblacionCenter = LatLng(8.1550, 125.1280);

  /// Reporting points within the reference polygons for every configured
  /// barangay. These points are map focus locations, not official centroids.
  static const Map<String, LatLng> coordinatesByCode = <String, LatLng>{
    // Poblacion District (11 urban barangays)
    'poblacion-01': LatLng(8.1610, 125.1292),
    'poblacion-02': LatLng(8.1588, 125.1252),
    'poblacion-03': LatLng(8.1572, 125.1250),
    'poblacion-04': LatLng(8.1547, 125.1270),
    'poblacion-05': LatLng(8.1553, 125.1284),
    'poblacion-06': LatLng(8.1557, 125.1304),
    'poblacion-07': LatLng(8.1498, 125.1298),
    'poblacion-08': LatLng(8.1530, 125.1303),
    'poblacion-09': LatLng(8.1501, 125.1331),
    'poblacion-10': LatLng(8.1516, 125.1243),
    'poblacion-11': LatLng(8.1483, 125.1249),

    // South Highway District (6 barangays)
    'casisang': LatLng(8.1349, 125.1269),
    'san-jose': LatLng(8.1036, 125.1286),
    'magsaysay': LatLng(8.0959, 125.0981),
    'aglayan': LatLng(8.0532, 125.1354),
    'cabangahan': LatLng(8.0222, 125.1395),
    'bangcud': LatLng(7.9943, 125.1322),

    // North Highway District (7 barangays)
    'sumpong': LatLng(8.1581, 125.1198),
    'kalasungay': LatLng(8.1720, 125.1031),
    'patpat': LatLng(8.1962, 125.0638),
    'dalwangan': LatLng(8.2003, 125.0433),
    'manalog': LatLng(8.2944, 125.1545),
    'laguitas': LatLng(8.0868, 125.1322),
    'miglamin': LatLng(8.0394, 125.2428),

    // Basakan District (13 barangays)
    'linabo': LatLng(8.0553, 125.1544),
    'violeta': LatLng(8.0269, 125.1585),
    'maligaya': LatLng(8.0410, 125.2054),
    'managok': LatLng(8.0268, 125.1903),
    'sto-nino': LatLng(7.9791, 125.1818),
    'simaya': LatLng(8.0032, 125.1553),
    'apo-macote': LatLng(7.9766, 125.2077),
    'sinanglanan': LatLng(7.9927, 125.1985),
    'san-martin': LatLng(8.0005, 125.1945),
    'imbayao': LatLng(8.1175, 125.0328),
    'mapayag': LatLng(8.0846, 125.0427),
    'kibalabag': LatLng(8.2455, 125.1766),
    'st-peter': LatLng(8.2242, 125.2836),

    // Upper Pulangi District (10 barangays)
    'can-ayan': LatLng(8.1867, 125.1550),
    'capitan-angel': LatLng(8.1478, 125.0220),
    'busdi': LatLng(8.2822, 125.2530),
    'kulaman': LatLng(8.2395, 125.2648),
    'silae': LatLng(8.1585, 125.2840),
    'caburacanan': LatLng(8.2142, 125.2771),
    'mapulo': LatLng(8.1882, 125.2975),
    'indalasa': LatLng(8.1873, 125.3062),
    'zamboanguita': LatLng(8.2017, 125.2979),
  };

  /// Historical administrative boundaries for the 46 configured Malaybalay
  /// barangays. Extracted from the MIT-licensed altcoder Philippines PSGC
  /// shapefiles (2015), filtered to ADM3_PCODE PH101312000 and simplified for
  /// browser rendering. This is a visual reference, not a surveyed boundary.
  static const String boundarySourceLabel = 'PSGC boundary reference (2015)';

  static const Map<String, String> _encodedPolygonsByCode = <String, String>{
    'aglayan':
        'b3NmcEBhe3l6VnJLZkByRGJDfFR2Q3RBZkFEbkNiQ2NCZEFmQnJDQWRDUWBEeUJkQHVFZEFpQnBBTE9uQmZCZEF0RnlGcERpQGxEYkFiRF1gQXtCcEp7RFFlQX1CVXpBeUVgQUFgQnZBaE9rRGRHS35BdEB2QXNBeEB5Q3xFbUFgQVxWdERwRGxDakJrQX5EWXBAfUJoQXZCbkNlQXJAeEBKfkVqRmVEdEV8RWVBeEN4QW5CaEJwX0B8QHxoQHtGbkJxRmdBX0RuRmVBYEdvRWxEakB+Q3BDcEFhQnREa0V0RF9OaEZ3RXxIZ0pwSXVEY0BjQ3ZDcEBwRXNAZk17QFZvQn5EekNqSXNCZkNsQGJGaUB2RG9DfkZMfEFhR0NtRHJKVWxGZkJ8XUl4Tm1CfFJhRn5YeUZsRmN3QG5ea2VAaFpzYEBgSHFLd2xBZkB5QHhDUWJCd0htQGVDVHNGYUBpQ2VEYUZ1QXBDc0BTP21EYkNhQ0xvQVFvRGlEZ0V8QWlGU3lEckF9RmlAYUVnQ2dGe0VjRXtBdUdhT2xEdld5cUFqS2lBdEVKfEZlUnxIbUxkSntKckN9U0Z5QmFAQGBGfX5A',
    'apo-macote':
        'Z3Z2b0Blfm97VnhAb3ZBdHZEdmxHZGlAZFp6QWJMY0BuTHFKdlZ5QnBSaVx0aUFvSHpFbVdoSH1IeFB9QmBPcUN6QXlGYkh7VWhDZUdmRGNZS3dCfUF1RGJAc3BAZFx+Q3dqQGVBb2pAX0tzfEBgR2t3Q2VGbXZD',
    'bangcud':
        'YWt6b0BxZHh6VnZFS2pHZUVkQVxkQX5DdENYdkV1RGhBb0NuRGVBXG9Ad0B9Ql9Fa0JxQF9CQH1DeEN9QGJGTnBId0F6RnBCckhxRmxIc0B1QGdCaUFfQFZhQm5Ob11kRXNHZkVxQXpWakN4Q2pBaEN0Q3FCdEVcdkR+Q3JEdENsQHVBakNmQGhEcUR8Q19BaENCcENsQXhDdkRkQT9kQX1CZEBfQnFCbUFPbUh+QnlIa0d3QnBHbEViT1lkSWNBakJ5QVx1QnFDa0R7QGlLdEJCZEhkTWJOaEJsRGBBZEZfQG5GZ0pkQnFJe0F1SWpHY0lId0F0Q3VCaEBnQXxBdkBwQWxEYEFyQmxHa0NiQ3NEckBfRndCaUdHZUN8QHlAdEN9QWZAZUBtQFZ9RWVDe0FvQnpBbUJuRWVBQnVBdUFzRGJBcUBqQEJyRGJEbkd1QnRBd0ZMaUJ3QWlEbEB7QXNAU29CX0lgRHFQZUNxQXRAYUJ7QnNCbVVSfUBmRV9BbEBhQUFxZEBUXWRMeERsRWFJU2VBYEJlRGRMX1BWY0I=',
    'busdi':
        'Z2p2cUBpanl7VmJ6QG9fQWhdaW1Bbm9BY3NAbmBFaU9oQ3FDZkd9QHdCfmNNfUxxQGlMdkBtQHRFbEVyeUlnaEp3SFBjZ0N9QHtPWHl9QF9Bd2BAeWJAaXFIcnBAY1Y=',
    'cabangahan':
        'ZX59b0Blc3l6VnhXc0J8RXZDZEJwSXpPYEBoRmZEbkJOdEd3QHxDbkFwQ2BIaEduQnJJfkZsSUR8Q3JFV2JCZUx+T2FCZERSZEFtRWBJZUx5RFVcQHBkQG1AYEFnRX5AU3xAckJsVWBCekJlQmJDYEF6Qn1EckB5RXhFY0R9QXdFeUl7QVBzfEJrekF9QH1oQGlCcV9AZEppQGxDa0FkQGdEckJkQG5KbkloRmhDakZYbkRnRHhFaEd0Qn5AZEZfQGBAeUF+QXVAZkFAbkV8RA==',
    'caburacanan':
        'cXNlcUBtaHJ7VmJHZ0B6UWtKZk59QH5CZUFoQH1BU3VDb0NxSGxCY0hrQHdFY0J3QXFFX0BXa0NlQW9BZEBfTnxCZUZ4QGVAeERmQGBBXWpGZ0lqVX1Call9RXhEfkByQXhDbEVXaEVzRFRpR3BDc0FgR31JcEBtRHJPfmhAdmxAcG1EblJoYUFvdEFiekRzcUJ7QXdWe2dIfkBxWGtAc0FkQXdBa0FtQnRBa0M=',
    'can-ayan':
        'aWxhcUB9dWd7Vm50QWN6RHZ1Q2pIdmZGeVBySndAZkNnRmZKekR2Q2pfQXJdZHtAdGRFZnlAakBkaUN9a0JgS3t1Qnh8QG1VfnFAa1B4QmVKdFF3T3xNb0xiRHdJZk55R2BTekR0aUBWfmVAX3FAe0FhU3JEbUpgR3lEbEt1RWZHe1NgRn1DdEVsQWhNb0BgSXJBZlhrWnBGb2VAcEBhYEB3QnNlQHxIZ0VXY0V3RGtDS3lHZ0x1RWNAY053SHNpQGBdfW5Ac0NlSHNVYUxjbkBxSnt5RFRnX0JoUG99Qw==',
    'capitan-angel':
        'X216cEB1YWd6Vn5UZURkWXBBZmdAX2JAbEN7RWJFaFFsRmBDZkNuR2xFfkZ2Qn5FUHxDZEJeR3ZEZkFYckJhQmZCdkRsQVZuRXhFYkhiQmBGbkNmRWpHZ0BuQFpsQX5EUGhGYkJGekFkQWZAXXpAakJyS2JCZkRoRWxCekF6RX5ATmZCcUFqQ2xBbkFBeEBxQXxBdEBmQ2ZJckNwQmxBeEN0QG5MZkhoRWNAekdoRXBEYEB4TXBCakFxQnZRekN0R0JmQ3dBfkNhSmJkQGJGfH1AbEp6bkBkUnZgQGpGflZ+WX5cb3RHaUlxdUBtd0F0UHtgRnpAe0NhRHlDe0BxRnpDdUNQa0JnRXtEaUFnRXVIaUJpRXlEcEVvYUBoW2NR',
    'casisang':
        'bWZ2cEBhbXZ6VnRVbkJ+RXFAbENxQXJDe0VsQEd8RmBBZER4QmRDY1p9SHNnQGFBa2xAZENjXldfZkB7RHVpQHhHYVN2SWdObkxjRHpqQ3BpRHVIdEZlQGpBb0ZhQXNCdEBiQGBMb0R2S2ZAckRfQG5CZUtyV1FyUnZMdFVBdkJ8Q3ZBUGRDX0J6QmBDakFBfkRlQmJBdEFuQkF2Q25CbkM/cktyQmxCeEB6Q2dCZENNbkJ+QWRBekF9QGJCbkBxQHpDeEB0Q2xKdkpmQHxIckN4QltkQnFDZkR+R3pBRHBCeEF6Qk16QHtBZEBKekFsUXpOakF2akFgUnh7QGBBdkt6QnpCaUBiQERyQ2pBZEFxQWZEc0BvRXtCbER6QXZGdUF4QlhiTnRBekR2QFphQH5CaEJoQUl0QnxCekFefEFXakBnQGdAb0BYekFsQXVBXGhAbkRhRHRAQmJBZEFOQHJBbUFHbUJuQUB6QGBCT2ZBakBPbkRhQnBAckJsRXtBYEVvQmZAfkN0Qn5CXkdgSHlAZEF2QWJBRXJFaEB8QHdAeEFCdkJzRGpEakF0SG9DXFh+R3dCaEBjQmZESHxAc0FJZUFmQUF4QHxBeEF1QG5CZEFBcEBiQWFAZkNiQHJEekR2Q3tAckBKaEFpQEhmQW5De0xsRmdRW31dX2NAZVFxV2tfQG9Yc29AcVNefUJ3QHVEcUZkQF9Ab0ByQHFEY0F9RmpDY0hpQHtBc0JRQWVFYUFfQ25BYUJtQHVCdkBxS2FFZ0FlQG1EcENfRHpAeUVwQWtAQ3dCb0NnR2NCUXNEaEF3RH1FW2dCekBpQl9CYUdhQm1BYEJ3Q29Be0B3QWRBd0BnQF55Q2pBdUBhQWlFfUBPbUNqQWlCU11hQ2BBc0J5QF9Fd0JfQndDRGVAY0B+QHNCdkFpQGJAb0N5QGFDdUFdVHlFdUJUbUFnQH1CZ0hlQ2RBcUBfQENzQWxCU2JBfUJtQWFDZURtQUpnRnFBZUZkQnFIZ0J3QntGfUJXa0hzQm9CZUJPYEB3R21AZ0R4Q2lKQmlEY0JhQX1AdEF1QnNCZEZzQ1Z7QHFHaUZ4QGFBfUFxRUxvQGJCQmtBc0R4Qm9HfENhRWlETXhAe0B5QmNKbURsQXlCbUJwQl9CWGNFZ0h3Q2RIdUdCfUBrQntAaUFtQmxGYUVzQHlAX0ZmQHtAfUBKe0NkQn1DYUFpQXpAZ0FRfUNhQndBakJvQEJzRW1BdUB7REZzRW9IYEVnQA==',
    'dalwangan':
        'e297cEBhbWV6VmhFeER0SGhCaEFmRWZFekRRakJ7Q3RDekBwRmBEeEN7QHpDdVB6YEZwdUBsd0Fte0J7eEBxbkBxZkF1UWtOd0h9Sm1HYUB7RntGZ0JxQ2pEfUllRH1BeURXQGtBbkFrQVV1QHNCW2VAcUJrQnhASWFEbUhPc0B9QE1zQ3lGXXtAc0VtRVNxQWlCXWlEaUNjQUl7RGVEcUFhQmVGe0VxQHdCVHFGdUJzQHlDX0N3Q3dKbUJ5QWlGa0dxRXNDekBlQndAa0BzQndBVUBgQ2NAP3FCc0RzR2JBY0BdZEBxQmVDa0B3QHlDfUFfQXlCTV9BZEJxQl51QXdGfUJAZ0VnRH1CYkFjTnNDX09Mb1VnRHVQc0BzR2FLZUlfc0F8Q2lJckBrSlN7Sm9AbUdxRGlHd0BrR2xAe0BwRWhAeEJbc0RjTEJpQnlAX0FqQWNGeUJxR3lHY0JrQnVFYUVSbUV3QWlAX01gQGlIYUFvTmNCaUlwQHdYckNxUWFCd1Z1RWtLYEJhYUBkRXFSdURlVWFNb0VgV2tGbmpAdHJAclFgbUNsa0J0eUBwb0FqYkBuTWpSSWBCdkRkQGZAeUBiQkdZckB6QFRBdEF6QGlBV3JGZEFJVGJEbkBDTXBAZEF4QW9CdkBiQXRAX0BsQXpDQnZDdUh+SX1GZHNCZmZAfEFLYEJhQmRBUmhCZkNCdkFtQW5DXmZBekJF',
    'imbayao':
        'X2R2cEBvaWx6VmZMdUd+RF9FckF1R3xDaUNqSkZ8RGFDYEZmQWBEZEN4Q050QF9DcEV3QGBFfkJgQkp+QmRIe0BoQlpmQnZEfEVyRGlBYkJQfENoSW1DeERJYENxQ35DZEBsRHxDZEBwQGRCZUFsSWxAdEJvQWBCYEF+QkBkRXJCUGhAekFrQ2JIYEFwRHFAfEZebkBwRmVAdkB0RF9AfEJyb0BwU2pfQG5YZFFwV3xdfmJAZlFaekxtRnJAbkFTfkJsQWBAXX5CZkB+QGhBSHhBckNZbkBoQHBCcUN4QGRCYkVUcFB4Q3JPcEFsQVJwQn1DfkRxQX5EbkpkW3lCfEdhR2BHcUBsTHxCdEh+Q2JFYkN6R054Q3tDfk1WbFFgQWBHZEJ6RXZHYkpoQmpIaUFmRlZ2QnJIYkx5QGxdfEF2SHtcZllpakB6VHddelhpakBkUl9aX11rRl9XZVJ3YEBtSntuQGNGfX1AYEpjZEB2QV9EQ2dDe0N1R3BCd1FxQmtBYUB5TWlFcURiQHtHZ0hpRXVAb0xtQXlDc0NxQmtEb0p5QE15QHBBe0VrQWdCcEFfQU97QXtFaUVtQmNCZ0RrQnNLXHtAZUFnQEd7QWlGY0JfRVFbbUFmQG9AZ0VrR2FGb0NjSGNCb0V5RW1BV2dCd0RzQmBCZ0FZRndEZUJfQFF9Q3dCX0ZtRV9HZ0NvR21GYUNjRWlRbEtlXT93QmpDYURYeURyQW9BUG9DZk9Vfkp3RmRQZVRjVXtoQA==',
    'indalasa':
        'YWB9cEBpY2Z8VmRLdHxBfEV2ZEdzWWJLX0B2QHBFakZvQGBDa0l8QWdDc0FnRmJDdEdgVnRRckhuSFZiQ35FZ0F8RGlDaENpQnZAfUlMcUt6RHNDYkRpRW5BY0ZXZUhoQ3tHYURjRFdjQG5AXXZLaUBpQXFBUn1AdURlREllQ31DcUR7QGtDYUdsQmFIfkB1S35DY0p6QWNCfENEakR3QWNCX0ZlRl9EUGVBc0h3bEBpWGV9QHNiQHNxQ19QY21BbENxQGZFZkJqSXFCdkt8Q2xGX0FyQ3tCekV1QGhHbkFiRG1BYkJqSHRCV2pGe0N+R0h+SmFFckNFdEJ2QHhHTXBBakFgQU10QXtEfkBVekFkQm5AT1ZhR3BHdUJeeUVwSGFDQH1BfUJ3QWRDcUVhQnFJakN1QWJFRQ==',
    'kalasungay':
        'X3tpcUBlanF6VnRLY1l0TG9IfEJtQ3pAcUdmQmdCdkNcdEN6RmpFbkN0RmFBfkFfQ3xAZ0JNb1BsSnFIZkJrQ3xBd0tzQHNEfU5xQGtBdUJKY0F0RXVGYkpxRnJKUmBPY0J2SHJYcGlAdnFAZHdHfElgTXVAeEF3QGpBb0RBZ0B3QExqQl9BZUFnQHpDaUV4Q3RFQXNBckBJYEVfR2hCc0laZkFgQ1J0QnZHfEBlRGpEcUJ0QE9yQ2JCaEBjQ35ARWBBdUJuSWdAeEZ4QmJEQnhCYEJ6SXJkQ2Z+QGJgQWZWaltiVXpoQGVQZFRfS3ZGZ09UUW5Dc0FuQVl4RGtDYEQ/dkJtS2RdbUN6RWdnQH5hQGVZcUFfVWREX09xT3tDaUF1QH1SdUFlQUxtQHFCSWdCX0RqQHNEbUF3RH5AX0NzRW1EUmFCa0FtQW5DZ0l5QG9AS3tEZUFjQUBrQ2FFdUl0Ql9Dc0VfRWpBbUt1QWNCaEBhRXNNb1B5SGdPQ3VBbUZfQ3FAaUF+QWtGcUJ5QlF9QXBAYUB2Q2ZAfkBpQWxGYVB5QGdJY0V5Q2VXe0l4QnFDeUFxQFRhQ19GbkB9QV1yQXVHZVN2Q31fQE9fe0d3ZEFpdEBlQQ==',
    'kibalabag':
        'Z2xrcUBxfWZ7VnJnQGdadGNEP3JxQnpBaVBufUNVZl9CcEp6eURzRm5QS35CdEFwRXNCYEFnS2BQdkNwR0l8QHlEZEF9RWhFfUViQHBBbkd9QXJEdUN+QGVCU3dNZkp9Q3JAZ0NpQGFDcUptQVNpSGpGd0JuQH1EX0BzQnhAbUd4Q21DakNlSGxJb0ZiUEtqSX5AZEdxQHJCZ0NkQHdYVWFPYkJzSlNhRWhCe0h0R3tAZkJObENuQGpAfE5wQHJAckR9QXZLZ0JqQ21KcEhMblB9QGZCX0J+QnVGYEFrRW9DdUN7RndDXWdCZkJ7QHBHfUJsQ3VMbkhvSXpSd0FtVX5CdU1tekFnfUlvYUJ3bEhmaEN+Qg==',
    'kulaman':
        'X3ZqcUBhX3J7VnRMcUB4UGtPZlFUflxlRWJFb0JsSl9BYlp+RHhbZEhkSGpDdUFqQ2pBbEJlQXZBakByQV9BcFh2VnpnSHVjRD9zZ0BmWm1Fc3lJbEB1RWhMd0B8THBA',
    'laguitas':
        'a2hocEBtYl97VnFCZGpEbHdAeUJhRnx+QGBAQUd4QnNDfFNlSnpKfUhsTH1GZFJ1RUtrS2hBd1d4cUFzWmtEc3JAbUBtQmtpQF9QaXxAbExvaEdidEJnSA==',
    'linabo':
        'a2hocEBtYl97Vn5HZ3xDclZtQG5lQHp0QGp2QWhsQGZmQHxkQX5iQHRXdVd4S2BAfmRBdkNiTGtEek19QHtAV3VEYUFdfUVsQXlAeEN3QXJBX0J1QGVHSmlPakRhQndBYUFAe0F4RXxCVFBkQXFKekRhQXpCY0RcbURjQXFEaEB1RnhGZ0JlQU5vQnFBTWVBaEJlQHRFYUR4QmVDUHNDQGVBZ0JjQ2JCRW9DdUFnQX1Ud0NzRGNDbUlrQHN5QHxCcEJlakQ=',
    'magsaysay':
        'b3ZrcEBfaHN6VnJyQGxAclpqRGBPbUR6QXRHekViRWZDZkZoQGBFc0F8RlJ4RH1BaEZoRGZFUG5ETW5BY0NgQz9sRHJAUnRBcUNkRGBGYEBoQ1VyRmxAZENjQnZIeUNQZ0B4QHBLdmxBbUdmQ3VDcEZnQm5Oe0ZqVndIak15QHJHSnpKfEJkRnFCbElzREZrTnpMdU97Tm9CZ0VlQHFEY0RkQHFAfENxRXNDZ0RyQHJCb0d9RWVAcUlpVWdiQGddb2dAd1NhUnl7QGtBd2pBalZsQWZRT3BSZ0diV2lxQA==',
    'maligaya':
        'X2tocEB5ZWh7VmxjQmFSdnNAe1ByQ3hJZ0R8UHBBdllyfkBuSWhpQXZ4QHxDYklHckdtUHhQX0J0R3FwQHhiQGFhQGRhQHFfQHhca3ZBaWxAb2VAe3RAX2pCbkRrQGVpQ2JoQT8=',
    'managok':
        'ZW1jcEB9X2l7VmBkQGtKalxrRW5fRHVKdUBucUNxVGpuRGdRbnNBY2JBaUp3ZkBfTF9jQHVXZ2ZAfWRBcF9AeVxgYUBlYUBwcEB5YkB+QXVHbFB5UEZzR31DY0lpaUF3eEBzfkBvSXFBd1lmRH1Q',
    'manalog':
        'b3VvcUBxYWd7Vm5hQnZsSGx6QWZ9SV9DdE12QWxVe0NyUmBFckl9S2RBcUJmQlxkTG1BdEJzQFx3QW9Ab0F5TGlBb0FhQUptU3pceUZuQmNLb0ljQ1d9QG5BekByRnNAbkJ1VnpKc0FfQ0FtQnxGY0lXdURpRGlDb0RsQGVBZENna0NhekVha0B1YEFtfEFjdEFvW3dhS35+RXZE',
    'mapayag':
        'a3ZtcEB5Zm16Vm5nQHZTZmJAZl1wSWhVfEVkQHNCbkdmRHNAcEVyQ3BAfUNiRGVAZEBwRG5CZkV0T3pOd0RkWH1MaEtLYktvQnpIQXhOYkl+UGZGdFlwR3ZuQEh0TnlAYklhSWBPdkFiRmhGbEhoVGxNeEVpRXpCbEFsSXRAeUBgT2VXemBAbVF+RXFJblhja0B8VmJAbFhhSGZcbUZ8SH1Mdkl9QXdIeEBtXXNIY0xXd0JoQWdGaUJrSHdHY0plQntFYUFhR1dtUXpDX05PeUNjQ3tHX0RjRX1CdUhwQG1MYEdhR3hCfUdvSmVbcEFfRXxDX0VTcUJxQW1BeUNzT1VxUGVCY0VwQ3lAaUBxQlhvQHlBc0NpQUlnQF9BXF9DbUFhQFJfQ3tCd0V4QW9De0R3Q2NAc0RgQGdDcUBjQWVBQHRAb0J9QXlBakBvQnRCTU93QGJCZ0R2QmlAWV9IbkNda0F1SHJEa0RDd0J2QHlBaUB9QERzRXdBY0F4QGVBRmFIX0h9Qm5CX0F6QWFFc0JtRWBCcUBOb0RnQWtAYUJOQXtAbEJvQWxBRkFzQWVBT0NjQWBEdUBpQG9EdEFde0FtQW5AWWZAZkBYa0FfRHlDSHVCaUJpQWBAX0N3QFt1QXtEWWNOdEF5QntBd0Z6Qm1EckBuRXBBZ0RrQWVBRXNDaEBjQHtCe0JhQXdL',
    'mapulo':
        'YX1+cEB3c3d7Vlx3S2JAb0BiRFZ6R2BEZEhpQ2JGVmhFb0FyQ2NEcEt7RHxJTWhCd0BoQ2lDZkF9RHpOZExSZnlHfXVBZGBBb1JpYUF3bEBxbURpUG9qQHxBcUNkRVVoSmNDdEBabkV9Q25CcEJDeER+Qm5CYEpuQmhEbkJ0Q0xiRm9FY0BhQEh1Q2ZNbV1pQG9B',
    'miglamin':
        'dWZocEBvY2x7VmB0QmtvQH5uQW5FRnNBdkRpQl9BaUVsRG9AQmdDdkN7QmxDSWpCcUFxQH1CYEF1QkljRnJEb0ZoSHFAcENpSmxGe0N+QXVFZERfRGZBT2BFdkFsSl9Dbkd3RXJCe0RuTHFHcEJhR1tvQ2BBY0N+QEVwQXRBakJVakNlQ2hIfUJmQ21EeER5QWREfUV2e0V3XXlAbnZBd2RCYlB7fUF6cEByT3h8Qm9fRHRKa1xqRWFkQGpKc0N5SXdzQHpQbWNCYFJoQ3V8Qg==',
    'patpat':
        'X3tpcUBlanF6Vmh0QGRBfnpHdmRBfF9ATmRTd0NzQXRHfEFcfkVvQFVgQ3hBcEB5QnBDZFd6SWJFeEN4QGZJbUZgUF9BaEF3Q2dAcUBgQFB8QXBCeEJfQmpGcEBoQWxGfkJCdEF4SGZPck1uUGlAYEV0QWJCa0FsS3JFfkR1Qn5CYEV0SUFqQ2RBYkFKekR4QG5Ab0NmSWpBbEFTYEJyRWxEX0F+QmxBdkRrQHJEZkJ+Q3BCSE1sQHRBZEF0QHxSekNoQX5OcE9pW2JRcUVuYUB7QkRfQGdBbEFvQ0N3QWlCZ0NlQVNhQmBCfUFKZXNCZ2ZAX0p8RndDdEh7Q0NebUFjQXVAbkJ3QGVBeUFMcUBvQEJVY0RlQUhWc0Z7QGhBQHVBe0BVWHNAY0JGZ0B4QHdEZUBIYUJvTWtScW9Ba2JAbWtCdXlAc1FhbUNvakB1ckBhV2pGcURfR3RBa0w=',
    'poblacion-01':
        'a2R5cEB3eHd6VmpDeFh+QVZwRXtBZkRkQnpDa0RsRFtiQX5FX0NwRlBsQmpCdEJsRVJpQX5ARWhDe0BwQVZ8Q31ZelJjVH1QZUlnRWNJY0pxSHVCZ0hcY0JpRGdDbUJtRnhBe0N6QnFDY0BzRXtFeUN7QG9DeUVjRkRnQm9CVWNDY0VzQ3JlQH1IYGBAdkJuZUBxQA==',
    'poblacion-02': 'ZWJ4cEB7X3Z6VmZEYkRlU3BWeUp9R3ZZd1I=',
    'poblacion-03':
        'fXx3cEB3enV6VnxKeEtlQ2xCd0ZoTFx0Q3hBZkJhQnpJcUVvSWlNaU1kU3FW',
    'poblacion-04': 'fXx3cEB3enV6VnpJb0hkRGJIakVpQm5BZEJjQmhFe0h+RX1KeUs=',
    'poblacion-05': 'X2J4cEBfYHZ6VnJKeUZ+QWpDcUh0R2FEZ0Q=',
    'poblacion-06':
        'a353cEB5bXZ6VlV7QnpJcUZmRWxHY0liRXRAekFzSnhGV31DekBxQURpQ2hBX0E=',
    'poblacion-07':
        'YXJ3cEBnZHZ6VmhkQHdUdEJXZEdiRG5Hekh3UlduQXJFbUhoRHVIakBrSV9EYUJ4QUR+QWhASGVDfEFlRGNI',
    'poblacion-08': 'YXh3cEB1anZ6VnxRd0pmQnZHb1BmSXVDZ0Y=',
    'poblacion-09':
        'd3R0cEBlX3t6VmVDYl5gQWpsQHxIcmdAZUNiWmVEeUJ9RmFBaUd6R3FJYkFnRn1Ab0d7SHtEcUNlQ1N9VWJMZ0J3R3lHckRfRW1HY0pwRkd+QW9ERl9DdURgQ19IY0FfRm1EWntDakRnRGVCcUV6QV9CV2tDeVhqWnFGc0FnWG5AYUltQWlNfEN1RXpTYUZ0RWdHeERtS2xKYUdgU3NEfnBAekE=',
    'poblacion-10':
        'Z3x3cEBranR6VmBCX0h5QWNEXXVDYEBnQXRFYUpgTW1JfEFtQ29Ac0NpQ0tCYUN4QndAaEh+Q3RIa0BxRHRNZ0BBbEBqQHlIZEtwRGJEd0N+Q3RBekRiQnVAZEN0RkF4QXJDZEJwQXRhQH1BekdwQXhZakl6YkFyUXx6QWpBdENsQVB7QHZDX0V+RGdMdEdnVmtbZ35AY2BBe0lzZENpQ3NCVXtCYExhUHZEekBuSlN6SV9BfENtQw==',
    'poblacion-11':
        'YXN2cEBxYHZ6VnBEY0F+QmtCdkBMekBoQnpER3hBeEFVekRjQlJ+QWZCUHxDe0BmQWBBaEFlQnxDS3pDekB8QH5FZ0ByQHhAbUZgRWhBbEJqQnpAQ3xAZUh0R2ZIdkNZYkVxQn5BeEJsQmxEbUF4QmJKeUB6QGhETH1DYEV5Qm5HakFyRGNCQ01uQHxBcEV5QGBBcEdoRld6QGVGckN0QnJCfEB1QWJCYEFDaER5Q2hKbEBmRGFAdkdkQk5yQm5CVmpIekZ8QmZCdkJlQnBIcEFkRktmRmREbEFsQWBDY0F8Qm1CUkJyQXBAXmRDZUF8QmZIbEFmQHRCVVV4RXRBXGBBcERjRXxGZEBiQHZDRXZCfkF4QH5EYUFyQlxgQ2hCUmxDa0F8QE5gQWhFa0F0QF9AeEN2QGZAdkFlQW5BekBfQmhCSGxBbUZhQ3FFdkB1QH5CeUNPYURlQ2FGZ0F9RGBDa0pHfUNoQ1d8Qm1BUWtBdUNzUX16QWtJe2JBcUF5WXxBe0dxQXVhQHNDZUJAeUFlQ3VGY0J0QHVBe0R2Q19EcURjRHhIZUttQGtAZkBAcER1TQ==',
    'san-jose':
        'd3JqcEBze2N7VmpyQWFDX0hmfENjdEJmSG1MbmhHfk9ofEBsQmppQGNXaHFAcVJmR2dRTmtWbUFtUXtOS3tBekFlQEx7QHlBe0JFcUJfSHtBcENnRFplQnNDeUJnQH1IbUp3SnlAdUNwQHtDY0JvQHtBfEBfQmVBTG9CZkJlQ3lAe0NzQm1CP3NLb0JvQ0B3Q3VBb0JkQmNBQF9FYUNrQX5Be0JRZUN9Q3dBQHdCd0x1VVBzUmRLc1deb0JnQHNEbkR3S2NAYUxyQnVAbkZgQWRAa0F0SHVGe2pDcWlEdk99TWRKdVFqUHlCbFVfckB6dUJ5fEB8a0JhSw==',
    'san-martin':
        'Z2p8b0BrfWl7VnNPeXxCen1Be3BAbk1wbkRnS2JiQmpDdUBTakFuQUpmQXBCckNmQHpAZ0BqQnRAa0FgSXFBZEB4TXBKYkt4akFfQ35gQHxDYmNBdVhmU2t2Qm1DcFRrbkR0QG9xQw==',
    'silae':
        'a3B8cEB1eXh7VmNDX0ZvSFd1UXNIdUdhVmZGY0NmQ3JBakl9QW5AYUNxRWtGXndAclljS31Fd2RHfUp1fkFxRGtFeUJ9RkxpRX5AZUF6Qk9+QWNDP2lHdkFnQWxCaUZiRWtCbkB5SGhLd0Z0QUdiQHJGdEJHXWlHbkFtQmJEfUBWZUF1QHtFekR9QE17Q2pDX0BOfUBzQmVCVm1CfEJlQXxIZkJiRmFFZkRlTW1BbUNed0BwR3tAckRrQ3JEdkBqRmNEdkdYeEZlQWZCa0RtQW1CbUVhQnRAe0JuR3tAYkNjQmJDfEBqQHJEZEFHfEJpRWZFVXJDe0FuQHFDXV9JbEp3Q25Ddkd6RGNCZkVAdkF7RHZFZUZ+R2NBckpOZUF5Q3xCfUh4RE5iQ3NCalx6e054QnhfQ3tiQHJbcV1ub0JAfGhDYm1CSGJqQGZDZER0SmJFTlBkQFdkQW9HYEBnRHBBbEBgTGJCfEF+RXZBWnhBd0BqQ35BYkFzSH5AQmZBeENiQWdDZkZrckZwUnd1Q2tIfHVBZWBBU2d5R3tOZUw=',
    'simaya':
        'YX19b0Bze3t6VnBae35CanZCbEN4X0FnckBqQXhiRHJKekdmRHdBbERiQmRAfEdsQ2JAYkBqQmtAUmNCYUF9QWBAeURuQ116Q2BBekBuQ2NDdkJpQHpDYEFOdEBnQ2JCZ0F2QmBHZEl5Q2tBX1RjQ3tBR2dFcEFlRXJHb05uXVdgQmhBXnRAZkJtSHJAc0hwRntGcUJxSHZBY0ZPeUN8QEF8Q3BAfkF+RGpCdkB8Ql1uQG9EZEFpQW5Dd0V0RHVDWWVBX0RlQV1rR2RFd0VKfUNzRW1JRXNJX0dpR29CcUNhSH1Db0F1R3ZAb0JPaUZnRHtPYUBlQnFJfUV3Q3dNYEFXY0FoQWNJZUJfQ3tGYUBhQW1FZ0JQekR1bkA=',
    'sinanglanan':
        'Z3Z2b0Blfm97VmRGbHZDYUdqd0N+SnJ8QGRBbmpAX0R2akBrWmROY2ZAfl19Q2NjQX5CX2FAY0t5akF5TXFKcEFlQGpBYUlrQnVAe0BmQHNDZ0BnQXFCb0FLUmtBa0N0QGZLY2JCb01xbkR2ZEJjUA==',
    'st-peter':
        'Z3JqcUBhZGB8Vn51QmlTdFR0YEBoSXpsQH1EckJmQG5Gb0NLbUByRHFCZkRfRmhEZ0BqRWtEZEF+QXxFcUNsQkJ2Q3NAWmdDX0BsQWhEQnZDa0JiQWVKYEx7QHZFakB8Q3xAckBqQ09oQHpBXWxDZkFkQX5Ea0BoQnVBbkdiRXRFd0F4Rn5AVnhAd0BgQ19DYkRaYEFkRUp0QnNCZEJiQXJCc0B+R0x+QHRESWRFZEJ0Q3hCZEF1QHpKdEB2QnxCdUJmQHNEeEBFdERkQ2JGaUBjQHREdUJgQ3JHaEVtR3RFa0F6RGBAYEFrQGhEfEE/dkBzQ3hBfkJyQ2FBZEBeTH5BdkR2Q0NwQHNAckBlQ2NAUWxAaEJ2QnNDY0BpQVhdZEN4QWxBbkRvQnpBckBtQHZBe0Z0QmZAckBuQ3dAeERHakBmQF18QGtGakJHdkJfRXpBZUByQnRBcEBZbENiQXhBSXZCfENmQXpEfkZqQ21Afk9kSH5EY0B0QWJAXG5EZUJ2QnZERnxBbkRpQ25AakByQmVAbkBqQmBBYENkRnZFakRlakBoSGtGZklhQVx5RGdAZ0NiQ29AZkNlQH5NZEFuQVZqQ3BFXmJCdkFqQHZFbUJiSG5DcEhSdENpQHxBX0NkQWdOfEB7UWpKY0dmQGVIa0N5W2VIY1pfRW1KfkBjRW5CX11kRWdRVXlQak91THBAdkJfZE0=',
    'sto-nino':
        'aWl3b0BpamF7Vn5rQWtrQHREY0B2QnxBYllKYkN8SmpCakN5TnpGc0FoRGVAckpgQWZMY0BqTn1GbE50QGRFZFZ0VHxNUkdkYEFfQ2ZEb0JsY0B3e0BARHBxQHBAbll9SXtKY0FvRV9CZUB3RVZ3Q19Cd0F5Ql13RHBCdUV9RXNFbURnR2ZBd0JmQ2NCT3VAe0F1QGVDQWFFYkR1QGFAT2dCbEF7QnBFY0N8QmBBakBTY0BrQm1DY0BlQH1HbURjQmdEdkFzSntHa0F5YkQ=',
    'sumpong':
        'd3JhcUBpfHl6VmBMYm5AZEhyVXxuQHJDcmlAYV1iTnZIdEViQGpHfEt4Q1RiRXZEZEd2QGRDckJUYkNmQm5CYkZFbkN4RXhDekByRXpFcENiQHpDe0JsRnlBZkNsQmJCaERmSF1wSHRCckluSnRIekR8X0B6WWhNaE1wRW5JfUNsQ3tJfkBvSlJ3RHtAc0tuTlF4QmhAZEFjREN5RnlCb0lmQGFBdEJfQURpQGJDc0NjQnVATmtEcEJ9QGREdUJ3R2FDU1tnQWlCcklhRX5Gc0BIQHJBeUN1RXtDaEVkQWZAa0J+QHZATUBmQGtBbkR5QXZAYU10QGV3R31JcWlAd3FAd0hzWHZYVGZDZUBwQHNCc0FlTnJEcU5gS2tOfkZzRW5Ha0N8RF52Qm9AfEl1RnpDbkt6RVxgUG9LZEJSdENfQXxBc0RxQW9HfEVjQHxFaUV4RGVBSH1Ad0NxR2ZLYVByQmFBdUFxRUpfQ3JGb1A=',
    'violeta':
        'c35gcEBpX356VnZmQH5LYmJBaEppSGpqQHtEdG5AZkJRYEFsRXpGYEBkQn5CaUFiSVZiQWFJcEBvRX1EZ0FBX0J0QGFAeEFlRl51Ql9BeUVpR29EZkRrRllpRmlDb0pvSXNCZUBlQGZEbUNqQWVKaEB1QW1BYEF7RGVBYUJvQ3tCa0ZkRFdlR3dEcEB7QHlCX0F+Ql9FWGtCakFzQnFBakR7TXdDY0xhQF9lQXRXeUs=',
    'zamboanguita':
        'Z3tmcUBreGB8VmRPa1V2akF3eEFyQ0V2QWdDaERLakRfSH5HQnZGfERiSmRDekRlQGBGYkJwQ3NAfk9ibUFyYkBycUNoWGR9QHJIdmxAUWRBZEZ+Q2JCfkVrRHZBfUNFe0FiQl9EYkpfQXRLcUJ6Rm5DZkhwRHpAZEN8Q2RESHxAdERwQVNyQXhDZ01sXUl0Q2JAYEBjRm5FdUNNaURvQmFKb0JfQ29CQnlEb0JxQm9FfEN1QFtpSmJDZUVUbUF2QWtAdkdhR3xJcUNyQVVoR2lFckRtRVZTbUFjQ3FCdUJZcURwQHdFa0RhQ2VGa0JhQWRAb0BrQHNCaENvQH1Bb0R3REdkQndCXW9EdUFjQF9FYkBfUGVIa0NsQHtEX0d9Q2dBSHdCY0F5QVhtQ3VBcUBkQHNCfkR7QUZ3QmpGa0JcfUBrQGdAeURGb0N2QGdAc0B6RnVCbEB3QXtBc0BvRG5CeUFtQVxlQ2hBWXJDYkBpQndCUG1AZENiQHJAc0BCcUB3RHdDTV9CZUBfQHNDYEF5QV9Dd0ByQ31BP2pAaURhQGFBakF7RGxHdUVzR2lFdEJhQ2JAdURjRmhAdURlQ3lARGdAckR9QnRCdUB3QnRAe0p5QmVBZUJ1Q0hlRV9BdURfSE1zQnJAZUJjQXVCckJlRUtbYUF+QmNEeEBpRHNHcUF1RXZBb0djRWlCdEFfRWpAZ0FlQVJ7RHlAY0F3Q1pjQWdFekB3RWRKYUxqQmNBQ3dDc0FlQ3RAb0B2QWpAckBbQ3dDcENtQnNBb0Z+Q3NAZkBrRX5FaURwQmdEbEBzRG5DSmdAb0Z8RHNCaUl7bEB1VHVgQA==',
  };

  static final Map<String, List<LatLng>> _cachedPolygons =
      _encodedPolygonsByCode.map(
        (code, encoded) => MapEntry<String, List<LatLng>>(
          code,
          _decodePolyline(utf8.decode(base64Decode(encoded))),
        ),
      );

  /// Returns the reviewed map reference point for [barangay].
  ///
  /// Reporting point used for focusing a selected polygon.
  static LatLng centerFor(BarangayReference barangay) {
    return coordinatesByCode[barangay.code.toLowerCase()] ?? cityCenter;
  }

  /// Returns the persisted PSGC reference polygon for [barangay].
  static List<LatLng> polygonFor(BarangayReference barangay) {
    return _cachedPolygons[barangay.code.toLowerCase()] ?? const <LatLng>[];
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      int decodeValue() {
        var shift = 0;
        var result = 0;
        int chunk;
        do {
          chunk = encoded.codeUnitAt(index++) - 63;
          result |= (chunk & 0x1f) << shift;
          shift += 5;
        } while (chunk >= 0x20 && index < encoded.length);
        // Bitwise complement of a signed delta is not consistent in compiled
        // JavaScript; arithmetic decoding keeps negative steps within bounds.
        return (result & 1) == 1 ? -((result >> 1) + 1) : result >> 1;
      }

      latitude += decodeValue();
      longitude += decodeValue();
      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    return points;
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
        return (center: poblacionCenter, zoom: 14.5);
      case 'South Highway District':
        return (center: const LatLng(8.0650, 125.1300), zoom: 12.0);
      case 'North Highway District':
        return (center: const LatLng(8.1850, 125.0950), zoom: 11.5);
      case 'Basakan District':
        return (center: const LatLng(8.0250, 125.1600), zoom: 11.5);
      case 'Upper Pulangi District':
        return (center: const LatLng(8.2150, 125.2750), zoom: 11.3);
      default:
        return (center: cityCenter, zoom: 10.8);
    }
  }
}

/// Paints all zones in the same map coordinate space. A single canvas avoids
/// web polygon-layer artifacts when many translucent polygons are stacked.
class _BarangayZonePainter extends CustomPainter {
  const _BarangayZonePainter({
    required this.camera,
    required this.summaries,
    required this.selectedCode,
    required this.showZones,
  });

  final MapCamera camera;
  final List<BarangayMapSurveillanceSummary> summaries;
  final String selectedCode;
  final bool showZones;

  @override
  void paint(Canvas canvas, Size size) {
    final zones = <(BarangayMapSurveillanceSummary, ui.Path)>[];
    for (final summary in summaries) {
      if (summary.polygon.length < 3) continue;
      final points = summary.polygon
          .map(camera.latLngToScreenOffset)
          .toList(growable: false);
      final path = ui.Path()..addPolygon(points, true);
      zones.add((summary, path));
    }

    // Clear city geometry from the outside scrim. This avoids inverse-path
    // rendering differences between Flutter's native and web renderers.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xDDF1F5F9),
    );
    for (final (_, path) in zones) {
      canvas.drawPath(path, Paint()..blendMode = BlendMode.clear);
    }
    canvas.restore();

    for (final (summary, path) in zones) {
      final selected = summary.barangay.code == selectedCode;
      if (showZones) {
        canvas.drawPath(
          path,
          Paint()
            ..color = summary.fillColor.withValues(
              alpha: selected ? 0.88 : 0.70,
            )
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = selected ? const Color(0xFF0F172A) : const Color(0xFF475569)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.4 : 0.85,
      );
    }
  }

  @override
  bool shouldRepaint(_BarangayZonePainter oldDelegate) =>
      camera != oldDelegate.camera ||
      summaries != oldDelegate.summaries ||
      selectedCode != oldDelegate.selectedCode ||
      showZones != oldDelegate.showZones;
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
    if (lower == 'fever' || lower == 'high fever') {
      return 'Acute Febrile Illness';
    }
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
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
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
      r'(?:barangay|brgy\.?|bgy\.?|poblacion)\s*[-#]?\s*0*(\d{1,2})\b',
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
          .replaceAll('sto nino', 'stonino')
          .replaceAll('saint peter', 'stpeter')
          .replaceAll('st. peter', 'stpeter')
          .replaceAll('st peter', 'stpeter')
          .replaceAll('capt. angel', 'capitanangel')
          .replaceAll('capt angel', 'capitanangel')
          .replaceAll('canayan', 'canayan')
          .replaceAll('apo macote', 'apomacote'),
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
      if (candidateNameKey.length >= 4 &&
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
      final name =
          <Object?>[
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
        accountStatus: (row['accountStatus'] ?? row['status'] ?? 'active')
            .toString(),
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
        final disease = rawDisease.isEmpty
            ? 'General Consultation'
            : rawDisease;
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
        return (disease: disease, category: SurveillanceCaseCategory.checkups);

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
        return (disease: label, category: SurveillanceCaseCategory.prenatal);

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
          : nonCommunicableCatalog[(seed * 5 + i) %
                nonCommunicableCatalog.length];
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
        'classification': isCommunicable ? 'communicable' : 'non_communicable',
        'caseClassification': isCommunicable
            ? 'communicable'
            : 'non_communicable',
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
      batch.set(barangayDocRef, <String, dynamic>{
        'barangay': barangay.name,
        'barangayCode': normalizedCode,
        'barangayDistrict': barangay.district,
        'surveillanceSyncedAt': FieldValue.serverTimestamp(),
        'workspaceUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
        batch.set(checkupRef, <String, dynamic>{
          ...payload,
          'id': checkupDocId,
        }, SetOptions(merge: true));
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
        final bhwLabel =
            <Object?>[
                  row['bhwName'],
                  row['createdByName'],
                  row['reportedBy'],
                  row['administeredBy'],
                  bhwSummaryByBarangay[barangay.code.toLowerCase()]?.name,
                ]
                .map((e) => (e ?? '').toString().trim())
                .firstWhere((e) => e.isNotEmpty, orElse: () => 'Barangay BHW');

        final patientLabel =
            <Object?>[
                  row['patientName'],
                  row['patient'],
                  row['fullName'],
                  row['name'],
                ]
                .map((e) => (e ?? '').toString().trim())
                .firstWhere(
                  (e) => e.isNotEmpty,
                  orElse: () => 'Patient Record',
                );

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
  })
  computeBarangayColors({
    required int metricValue,
    required int maxMetricValue,
    EpidemiologicalTierThresholds? thresholds,
  }) {
    if (metricValue <= 0) {
      return (
        tier: BarangayEpidemiologicalTier.baseline,
        fillColor: const Color(0xFFDDE4EC),
        strokeColor: const Color(0xFF475569),
        badgeColor: const Color(0xFF64748B),
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
      return (
        tier: BarangayEpidemiologicalTier.low,
        fillColor: const Color(0xFFFADCD9),
        strokeColor: const Color(0xFF9F3A45),
        badgeColor: const Color(0xFFB95A61),
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
      return (
        tier: BarangayEpidemiologicalTier.moderate,
        fillColor: const Color(0xFFF2A29D),
        strokeColor: const Color(0xFF9F343B),
        badgeColor: const Color(0xFFC4575E),
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
      return (
        tier: BarangayEpidemiologicalTier.high,
        fillColor: const Color(0xFFDF6668),
        strokeColor: const Color(0xFF8F242B),
        badgeColor: const Color(0xFFB9323C),
        ratio: 0.68 + (0.16 * t),
      );
    }

    final span = math.max(1, maxMetricValue - resolvedThresholds.highMax);
    final t = ((metricValue - resolvedThresholds.highMax) / span).clamp(
      0.0,
      1.0,
    );
    return (
      tier: BarangayEpidemiologicalTier.critical,
      fillColor: const Color(0xFFA32F3F),
      strokeColor: const Color(0xFF762434),
      badgeColor: const Color(0xFF982D3F),
      ratio: 0.85 + (0.15 * t),
    );
  }

  /// Builds the full list of [BarangayMapSurveillanceSummary] entries for all
  /// 46 Malaybalay barangays, filtered by [categoryFilter] and [diseaseFilter].
  static List<BarangayMapSurveillanceSummary> buildSummaries({
    required List<BarangaySurveillanceCase> allCases,
    required List<SyncedBhwUserSummary> bhwUsers,
    required Set<String> syncedWorkspaceCodes,
    SurveillanceCaseCategory categoryFilter = SurveillanceCaseCategory.all,
    String diseaseFilter = 'ALL',
    SurveillanceColorMetric colorMetric = SurveillanceColorMetric.caseVolume,
  }) {
    final filteredCases = allCases
        .where((c) {
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
        })
        .toList(growable: false);

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
      bhwByBarangay.putIfAbsent(u.barangay.code.toLowerCase(), () => []).add(u);
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
        diseaseCounts.update(item.disease, (v) => v + 1, ifAbsent: () => 1);
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
        if (item.sourceCollection == 'morbidity_records' &&
            item.category != SurveillanceCaseCategory.morbidity) {
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
    this.isDataTruncated = false,
  });

  final List<BarangaySurveillanceCase> allCases;
  final List<SyncedBhwUserSummary> bhwUsers;
  final Set<String> syncedWorkspaceCodes;
  final String windowLabel;
  final String? selectedBarangayCode;
  final ValueChanged<BarangayReference>? onBarangaySelected;
  final VoidCallback? onSyncAllBarangays;
  final bool isSyncingAllBarangays;
  final bool isDataTruncated;

  @override
  State<ChoBarangaySurveillanceMap> createState() =>
      _ChoBarangaySurveillanceMapState();
}

class _ChoBarangaySurveillanceMapState
    extends State<ChoBarangaySurveillanceMap> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _directoryScrollController = ScrollController();

  SurveillanceCaseCategory _selectedCategory = SurveillanceCaseCategory.all;
  String _selectedDisease = 'ALL';
  String _selectedDistrict = 'ALL';
  SurveillanceColorMetric _colorMetric = SurveillanceColorMetric.caseVolume;
  String _searchQuery = '';
  String? _focusedBarangayCode;
  bool _showPolygons = true;
  bool _showBarangayLabels = false;
  double _currentZoom = 10.8;

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
    _directoryScrollController.dispose();
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
    final filteredSummaries = summaries
        .where((s) {
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
        })
        .toList(growable: false);

    final selectedSummary = filteredSummaries.firstWhere(
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 20,
            offset: Offset(0, 4),
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
          if (widget.isDataTruncated) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF475569),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Map counts may be incomplete: a source reached the 2,500-record dashboard read limit. Use Reports for complete historical analysis.',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildKpiRow(
            totalCases: totalFilteredCases,
            activeBarangays: activeBarangaysCount,
            totalBarangays: summaries.length,
            topHotspot: topHotspot,
            trackedDiseasesCount: sortedDiseases.length,
          ),
          const SizedBox(height: 16),
          _buildFilterControls(
            sortedDiseases: sortedDiseases,
            activeDiseaseFilter: activeDiseaseFilter,
            tierCounts: tierCounts,
            thresholds: thresholds,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1060;
              final mapPanel = _buildInteractiveMapCanvas(
                summaries: summaries,
                selectedSummary: selectedSummary,
                compact: compact,
                initialZoom: compact && constraints.maxWidth < 520
                    ? 10.0
                    : 10.8,
              );
              final inspectorPanel = _buildRightInspectorColumn(
                selectedSummary: selectedSummary,
                filteredSummaries: filteredSummaries,
                maxCases: maxCases,
                compact: compact,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    mapPanel,
                    const SizedBox(height: 16),
                    inspectorPanel,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: mapPanel),
                  const SizedBox(width: 16),
                  Expanded(flex: 10, child: inspectorPanel),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
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
      spacing: 14,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.analytics_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Interactive Barangay Disease & Case Surveillance Map',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Malaybalay City · $totalBarangays barangays · ${widget.windowLabel} · $trackedDiseasesCount tracked conditions. Boundaries: ${MalaybalayBarangayGeoRegistry.boundarySourceLabel}.',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFA7F3D0)),
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
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x4010B981),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Reporting barangays ($activeBarangays/$totalBarangays)',
                    style: const TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
            : constraints.maxWidth >= 300
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
            icon: Icons.personal_injury_outlined,
            accent: const Color(0xFF2563EB),
          ),
          _kpiTile(
            label: 'Barangays Reporting',
            value: '$activeBarangays of $totalBarangays',
            subtitle: 'With cases in the selected view',
            icon: Icons.location_city_outlined,
            accent: const Color(0xFF2563EB),
          ),
          _kpiTile(
            label: 'Highest Hotspot',
            value: '${topHotspot.barangay.name} (${topHotspot.totalCases})',
            subtitle: 'Leading: ${topHotspot.dominantDisease}',
            icon: Icons.local_fire_department_rounded,
            accent: const Color(0xFF2563EB),
          ),
          _kpiTile(
            label: 'Diseases & BHW Network',
            value: '$trackedDiseasesCount conditions',
            subtitle: 'Across Malaybalay surveillance records',
            icon: Icons.hub_outlined,
            accent: const Color(0xFF2563EB),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 210;
        final iconBox = Container(
          width: narrow ? 28 : 40,
          height: narrow ? 28 : 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: accent, size: narrow ? 16 : 20),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: narrow ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
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
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
            ),
          ],
        );
        return Container(
          height: narrow ? 132 : null,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [iconBox, const SizedBox(height: 6), details],
                )
              : Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFilterControls({
    required List<MapEntry<String, int>> sortedDiseases,
    required String activeDiseaseFilter,
    Map<BarangayEpidemiologicalTier, int>? tierCounts,
    EpidemiologicalTierThresholds? thresholds,
  }) {
    final districts = <String>['ALL', ...MalaybalayBarangays.districtOrder];

    final isFiltered =
        _selectedCategory != SurveillanceCaseCategory.all ||
        activeDiseaseFilter != 'ALL' ||
        _selectedDistrict != 'ALL' ||
        _searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Category Filter Segmented Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SurveillanceCaseCategory.values
                  .map((category) {
                    final selected = _selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _selectedCategory = category;
                              _selectedDisease = 'ALL';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7.5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF2563EB)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFE2E8F0),
                              ),
                              boxShadow: selected
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x262563EB),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  category.icon,
                                  size: 15,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  category.label,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF334155),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          // Row 2: Search Bar & Dropdowns (Uniform modern 40px height)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search barangay or disease...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: Color(0xFF64748B),
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
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 230,
                height: 40,
                child: DropdownButtonFormField<String>(
                  initialValue: activeDiseaseFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.coronavirus_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
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
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    ...sortedDiseases.map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(
                          '${entry.key} (${entry.value})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
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
                width: 205,
                height: 40,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDistrict,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.map_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                  ),
                  items: districts
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d,
                          child: Text(
                            d == 'ALL' ? 'All 5 Districts (46 Brgys)' : d,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedDistrict = value);
                    final cam = MalaybalayBarangayGeoRegistry.cameraForDistrict(
                      value,
                    );
                    _moveCamera(cam.center, cam.zoom);
                  },
                ),
              ),
              SizedBox(
                width: 195,
                height: 40,
                child: DropdownButtonFormField<SurveillanceColorMetric>(
                  initialValue: _colorMetric,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.palette_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                  ),
                  items: SurveillanceColorMetric.values
                      .map(
                        (m) => DropdownMenuItem<SurveillanceColorMetric>(
                          value: m,
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF334155),
                            ),
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
              if (isFiltered)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() {
                      _selectedCategory = SurveillanceCaseCategory.all;
                      _selectedDisease = 'ALL';
                      _selectedDistrict = 'ALL';
                      _searchController.clear();
                      _searchQuery = '';
                    });
                    _moveCamera(MalaybalayBarangayGeoRegistry.cityCenter, 10.8);
                  },
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_off_outlined,
                          size: 15,
                          color: Color(0xFFDC2626),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (tierCounts != null && thresholds != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _colorMetric == SurveillanceColorMetric.caseVolume
                            ? 'Barangay case scale:'
                            : 'Barangay risk score scale:',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _legendChip(
                        color: const Color(0xFF64748B),
                        label: 'Baseline (0)',
                        count:
                            tierCounts[BarangayEpidemiologicalTier.baseline] ??
                            0,
                      ),
                      _legendChip(
                        color: const Color(0xFFB95A61),
                        label: 'Low (1–${thresholds.lowMax})',
                        count: tierCounts[BarangayEpidemiologicalTier.low] ?? 0,
                      ),
                      _legendChip(
                        color: const Color(0xFFC4575E),
                        label:
                            'Moderate (${thresholds.lowMax + 1}–${thresholds.moderateMax})',
                        count:
                            tierCounts[BarangayEpidemiologicalTier.moderate] ??
                            0,
                      ),
                      _legendChip(
                        color: const Color(0xFFB9323C),
                        label:
                            'High (${thresholds.moderateMax + 1}–${thresholds.highMax})',
                        count:
                            tierCounts[BarangayEpidemiologicalTier.high] ?? 0,
                      ),
                      _legendChip(
                        color: const Color(0xFF982D3F),
                        label: 'Critical (${thresholds.highMax + 1}+)',
                        count:
                            tierCounts[BarangayEpidemiologicalTier.critical] ??
                            0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$label · $count brgy${count == 1 ? '' : 's'}',
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMapCanvas({
    required List<BarangayMapSurveillanceSummary> summaries,
    required BarangayMapSurveillanceSummary selectedSummary,
    required bool compact,
    required double initialZoom,
  }) {
    final visibleMapSummaries = summaries
        .where((s) {
          if (_selectedDistrict != 'ALL' &&
              s.barangay.district != _selectedDistrict) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

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

    final showExpandedPills = _showBarangayLabels;

    return Container(
      height: compact ? 520 : 620,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: MalaybalayBarangayGeoRegistry.cityCenter,
              initialZoom: initialZoom,
              minZoom: 9.5,
              maxZoom: 17.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onMapReady: () {
                if (mounted) {
                  setState(() => _currentZoom = _mapController.camera.zoom);
                }
              },
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
              Positioned.fill(
                child: Builder(
                  builder: (context) => IgnorePointer(
                    child: CustomPaint(
                      painter: _BarangayZonePainter(
                        camera: MapCamera.of(context),
                        summaries: summaries,
                        selectedCode: selectedSummary.barangay.code,
                        showZones: _showPolygons,
                      ),
                    ),
                  ),
                ),
              ),
              MarkerLayer(
                markers: orderedMarkers
                    .where(
                      (summary) =>
                          _showBarangayLabels ||
                          summary.barangay.code ==
                              selectedSummary.barangay.code,
                    )
                    .map((summary) {
                      final isSelected =
                          summary.barangay.code ==
                          selectedSummary.barangay.code;
                      final showLabelForThisMarker =
                          showExpandedPills || isSelected;
                      final shortName = summary.barangay.name.replaceFirst(
                        'Barangay ',
                        'Brgy ',
                      );

                      return Marker(
                        point: summary.center,
                        width: showLabelForThisMarker ? 134 : 32,
                        height: showLabelForThisMarker ? 38 : 32,
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
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: isSelected ? 2.2 : 1.6,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: summary.badgeColor
                                                .withValues(
                                                  alpha: isSelected
                                                      ? 0.60
                                                      : 0.35,
                                                ),
                                            blurRadius: isSelected ? 10 : 6,
                                            spreadRadius: isSelected ? 1.5 : 0,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: summary.badgeColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              shortName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: summary.badgeColor,
                                              borderRadius:
                                                  BorderRadius.circular(999),
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
                                          width: 2.0,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: summary.badgeColor
                                                .withValues(alpha: 0.45),
                                            blurRadius: 6,
                                            spreadRadius: 0.5,
                                            offset: const Offset(0, 2),
                                          ),
                                          const BoxShadow(
                                            color: Color(0x33000000),
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        '${summary.totalCases}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
          // Top-right compact Leaflet navigation dock
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
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 8,
                        offset: Offset(0, 2),
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
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      _mapControlIconButton(
                        tooltip: 'Zoom out',
                        icon: Icons.remove_rounded,
                        onTap: () => _moveCamera(
                          _mapController.camera.center,
                          _currentZoom - 0.8,
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      _mapControlIconButton(
                        tooltip: 'Reset to Malaybalay City view',
                        icon: Icons.my_location_rounded,
                        onTap: () {
                          setState(() => _selectedDistrict = 'ALL');
                          _moveCamera(
                            MalaybalayBarangayGeoRegistry.cityCenter,
                            10.8,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _moveCamera(
                      MalaybalayBarangayGeoRegistry.poblacionCenter,
                      14.5,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6.5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F0F172A),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_city_rounded,
                            size: 13,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Poblacion (01–11)',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
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
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 6,
                children: [
                  _layerTogglePill(
                    label: 'Barangay zones',
                    icon: Icons.pentagon_outlined,
                    active: _showPolygons,
                    onTap: () => setState(() => _showPolygons = !_showPolygons),
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
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(
                  color: Color(0xFF64748B),
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
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: const Color(0xFF1E3A5F)),
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF334155),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
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
    required bool compact,
  }) {
    final visibleRows = filteredSummaries;

    return SizedBox(
      height: compact ? null : 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSelectedBarangayInspector(selectedSummary),
          const SizedBox(height: 12),
          if (compact)
            SizedBox(
              height: 400,
              child: _buildDirectoryCard(
                visibleRows,
                selectedSummary,
                maxCases,
              ),
            )
          else
            Expanded(
              child: _buildDirectoryCard(
                visibleRows,
                selectedSummary,
                maxCases,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectoryCard(
    List<BarangayMapSurveillanceSummary> visibleRows,
    BarangayMapSurveillanceSummary selectedSummary,
    int maxCases,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.format_list_bulleted_rounded,
                size: 16,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Barangay Case & Color Directory',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '${visibleRows.length} barangays',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Sorted by reported cases · select a row to focus the map',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _directoryScrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _directoryScrollController,
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                itemCount: visibleRows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final entry = visibleRows[index];
                  final isSelected =
                      entry.barangay.code == selectedSummary.barangay.code;
                  final ratio = (entry.totalCases / maxCases).clamp(0.0, 1.0);
                  return InkWell(
                    key: ValueKey<String>(
                      'barangay-directory-item-${entry.barangay.code}',
                    ),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _selectBarangay(entry),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF0F7FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x050F172A),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
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
                                  style: TextStyle(
                                    color: isSelected
                                        ? const Color(0xFF1E3A8A)
                                        : const Color(0xFF0F172A),
                                    fontSize: 12.5,
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
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${entry.totalCases} cases · ${entry.tierLabel}',
                                  style: TextStyle(
                                    color: entry.strokeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${entry.barangay.district} • Leading: ${entry.dominantDisease}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                entry.workspaceSynced
                                    ? Icons.cloud_done_outlined
                                    : Icons.cloud_off_outlined,
                                size: 12,
                                color: entry.workspaceSynced
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                entry.workspaceSynced
                                    ? '${entry.assignedBhwUsers.length} BHW · synced'
                                    : '${entry.assignedBhwUsers.length} BHW · pending',
                                style: TextStyle(
                                  color: entry.workspaceSynced
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF64748B),
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
                              minHeight: 2.5,
                              color: entry.badgeColor,
                              backgroundColor: const Color(0xFFE2E8F0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAllBarangays(visibleRows),
              icon: const Icon(Icons.grid_view_rounded, size: 17),
              label: Text('Browse all ${visibleRows.length} barangays'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1D4ED8),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAllBarangays(
    List<BarangayMapSurveillanceSummary> summaries,
  ) async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final results = summaries.where((entry) {
            final term = query.trim().toLowerCase();
            return entry.barangay.name.toLowerCase().contains(term) ||
                entry.barangay.district.toLowerCase().contains(term);
          }).toList();
          final size = MediaQuery.sizeOf(dialogContext);
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: size.height * 0.86,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Browse barangays',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close barangay directory',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summaries.length} barangays · select one to focus the map',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('barangay-directory-search'),
                      autofocus: false,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'Search barangay or district',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: results.isEmpty
                          ? const Center(child: Text('No barangays found'))
                          : Scrollbar(
                              child: ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0xFFE2E8F0),
                                ),
                                itemBuilder: (context, index) {
                                  final entry = results[index];
                                  return ListTile(
                                    key: ValueKey<String>(
                                      'all-barangay-item-${entry.barangay.code}',
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    leading: CircleAvatar(
                                      radius: 6,
                                      backgroundColor: entry.badgeColor,
                                    ),
                                    title: Text(
                                      entry.barangay.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    subtitle: Text(
                                      entry.barangay.district,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${entry.totalCases} cases',
                                          style: TextStyle(
                                            color: entry.strokeColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          entry.tierLabel,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.of(dialogContext).pop();
                                      _selectBarangay(entry);
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
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
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${summary.barangay.district} • Code: ${summary.barangay.code.toUpperCase()}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: summary.badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: summary.badgeColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '${summary.totalCases} Cases · ${summary.tierLabel}',
                  style: TextStyle(
                    color: summary.strokeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: summary.workspaceSynced
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: summary.workspaceSynced
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  summary.workspaceSynced
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 15,
                  color: summary.workspaceSynced
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    bhwNames.isEmpty
                        ? (summary.workspaceSynced
                              ? 'Barangay workspace synced · no active BHW assigned'
                              : 'No synced barangay workspace or active BHW')
                        : 'Active BHW Stations (${bhwNames.length}): ${bhwNames.join(", ")}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: summary.workspaceSynced
                          ? const Color(0xFF166534)
                          : const Color(0xFF475569),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 460 ? 2 : 4;
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 6) / columns;
              final stats = <({String label, String value, IconData icon})>[
                (
                  label: 'Total cases',
                  value: '${summary.totalCases}',
                  icon: Icons.personal_injury_outlined,
                ),
                (
                  label: 'Morbidity',
                  value: '${summary.morbidityCount}',
                  icon: Icons.sick_outlined,
                ),
                (
                  label: 'Check-ups',
                  value: '${summary.checkupCount}',
                  icon: Icons.medical_services_outlined,
                ),
                (
                  label: 'Risk score',
                  value: '${summary.severityScore}',
                  icon: Icons.speed_rounded,
                ),
              ];
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: stats
                    .map(
                      (stat) => SizedBox(
                        width: tileWidth,
                        child: _executiveMiniStatCard(
                          label: stat.label,
                          value: stat.value,
                          accent: const Color(0xFF2563EB),
                          icon: stat.icon,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 8),
          // Secondary clinical categories row
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _miniStatPill('Communicable', summary.communicableCount),
              _miniStatPill('Non-Communicable', summary.nonCommunicableCount),
              if (summary.prenatalCount > 0)
                _miniStatPill('Prenatal', summary.prenatalCount),
              if (summary.immunizationCount > 0)
                _miniStatPill('Immunization', summary.immunizationCount),
              if (summary.mortalityCount > 0)
                _miniStatPill('Mortality', summary.mortalityCount),
              if (summary.referralCount > 0)
                _miniStatPill('Referrals', summary.referralCount),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Active Diseases & Conditions in Barangay:',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (sortedDiseases.isEmpty)
            const Text(
              'No cases matching current filter in this barangay.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sortedDiseases
                  .take(6)
                  .map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: summary.badgeColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${entry.value}',
                              style: TextStyle(
                                color: summary.strokeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _executiveMiniStatCard({
    required String label,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatPill(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Color(0xFF475569),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 17, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text(
                'Multi-Disease Barangay Concentration Matrix',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Cross-barangay distribution of leading diseases and clinical cases. Click any barangay row to focus on the map.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, 860),
                  child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: {
                      0: const FixedColumnWidth(160),
                      1: const FixedColumnWidth(96),
                      for (var i = 0; i < topDiseases.length; i++)
                        i + 2: const FlexColumnWidth(),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              'Barangay',
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Text(
                              'Total Cases',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          ...topDiseases.map(
                            (disease) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Text(
                                disease,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ...summaries.map((summary) {
                        return TableRow(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                          ),
                          children: [
                            InkWell(
                              onTap: () => _selectBarangay(summary),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
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
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        summary.barangay.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: summary.badgeColor.withValues(
                                  alpha: 0.12,
                                ),
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
                                  ? Colors.transparent
                                  : summary.fillColor.withValues(
                                      alpha:
                                          (0.18 +
                                                  0.42 *
                                                      count /
                                                      math.max(
                                                        1,
                                                        summary.totalCases,
                                                      ))
                                              .clamp(0.18, 0.60),
                                    );
                              return Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: cellColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: count > 0
                                        ? summary.badgeColor.withValues(
                                            alpha: 0.25,
                                          )
                                        : const Color(0xFFF1F5F9),
                                  ),
                                ),
                                child: Text(
                                  count == 0 ? '-' : '$count',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: count == 0
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF0F172A),
                                    fontSize: 11,
                                    fontWeight: count == 0
                                        ? FontWeight.normal
                                        : FontWeight.w800,
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
            ),
          ),
        ],
      ),
    );
  }
}
