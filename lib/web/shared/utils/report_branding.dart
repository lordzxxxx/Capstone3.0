import 'package:flutter/services.dart';
import 'package:mycapstone_project/shared/barangay_logo_assets.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';

/// The official marks used by print and spreadsheet reports.
///
/// The barangay mark is resolved from the selected barangay at export time.
/// A locally bundled seal is retained as a safe fallback when a barangay has
/// no configured custom logo or its remote asset is unavailable.
class ReportBranding {
  const ReportBranding({
    required this.cityLogo,
    required this.healthOfficeLogo,
    required this.barangayLogo,
    required this.barangayName,
    required this.barangayLogoIsFallback,
  });

  final Uint8List? cityLogo;
  final Uint8List? healthOfficeLogo;
  final Uint8List? barangayLogo;
  final String barangayName;
  final bool barangayLogoIsFallback;
}

Future<ReportBranding> loadReportBranding({
  required String barangayName,
}) async {
  final cityLogo = await _loadAsset('assets/logo2.png');
  final healthOfficeLogo = await _loadAsset('assets/logo3.png');

  Uint8List? barangayLogo;
  var barangayLogoIsFallback = true;
  final barangay =
      MalaybalayBarangays.byName(barangayName) ??
      MalaybalayBarangays.byCode(barangayName);

  if (barangay != null) {
    try {
      final profile = await BarangayBrandingService.instance.getBranding(
        barangay,
      );
      if (profile.hasCustomLogo) {
        barangayLogo = await _loadRemote(profile.logoUrl);
        barangayLogoIsFallback = barangayLogo == null;
      }
    } catch (_) {
      // Local assets remain the reliable path when Firestore or Storage is
      // unavailable during export.
    }

    if (barangayLogo == null) {
      final localAsset = resolveBarangayLogoAssetPath(
        barangayCode: barangay.code,
        barangayName: barangay.name,
      );
      if (localAsset != null) {
        barangayLogo = await _loadAsset(localAsset);
        barangayLogoIsFallback = false;
      }
    }
  }

  barangayLogo ??= await _loadAsset('assets/logo1.png');

  return ReportBranding(
    cityLogo: cityLogo,
    healthOfficeLogo: healthOfficeLogo,
    barangayLogo: barangayLogo,
    barangayName:
        barangay?.name ??
        (barangayName.trim().isEmpty
            ? 'Barangay Not Specified'
            : barangayName.trim()),
    barangayLogoIsFallback: barangayLogoIsFallback,
  );
}

Future<Uint8List?> _loadAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _loadRemote(String url) async {
  try {
    final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
