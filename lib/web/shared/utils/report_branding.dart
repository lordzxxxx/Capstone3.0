import 'package:flutter/services.dart';
import 'package:mycapstone_project/shared/barangay_logo_assets.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/services/barangay_branding_service.dart';

/// The official marks used by print and spreadsheet reports.
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

// In-memory caches to make PDF generation instantaneous
final Map<String, ReportBranding> _brandingCache = {};
Uint8List? _cachedCityLogo;
Uint8List? _cachedHealthOfficeLogo;
Uint8List? _cachedDefaultBarangayLogo;
final Map<String, Uint8List?> _cachedAssetLogos = {};

Future<ReportBranding> loadReportBranding({
  required String barangayName,
}) async {
  final cacheKey = barangayName.trim().toLowerCase();
  final cached = _brandingCache[cacheKey];
  if (cached != null) {
    return cached;
  }

  // Load static city and health office logos in parallel (cached after first load)
  final staticLogos = await Future.wait([
    _cachedCityLogo != null ? Future.value(_cachedCityLogo) : _loadAsset('assets/logo2.png'),
    _cachedHealthOfficeLogo != null ? Future.value(_cachedHealthOfficeLogo) : _loadAsset('assets/logo3.png'),
  ]);
  _cachedCityLogo ??= staticLogos[0];
  _cachedHealthOfficeLogo ??= staticLogos[1];

  Uint8List? barangayLogo;
  var barangayLogoIsFallback = true;
  final barangay =
      MalaybalayBarangays.byName(barangayName) ??
      MalaybalayBarangays.byCode(barangayName);

  if (barangay != null) {
    // 1. Check local bundled asset FIRST - zero network delay
    final localAsset = resolveBarangayLogoAssetPath(
      barangayCode: barangay.code,
      barangayName: barangay.name,
    );
    if (localAsset != null) {
      if (_cachedAssetLogos.containsKey(localAsset)) {
        barangayLogo = _cachedAssetLogos[localAsset];
      } else {
        barangayLogo = await _loadAsset(localAsset);
        _cachedAssetLogos[localAsset] = barangayLogo;
      }
      if (barangayLogo != null) {
        barangayLogoIsFallback = false;
      }
    }

    // 2. Only if no local asset is available, attempt remote branding with strict timeout
    if (barangayLogo == null) {
      try {
        final profile = await BarangayBrandingService.instance
            .getBranding(barangay)
            .timeout(const Duration(milliseconds: 500));
        if (profile.hasCustomLogo) {
          barangayLogo = await _loadRemote(profile.logoUrl)
              .timeout(const Duration(milliseconds: 800));
          barangayLogoIsFallback = barangayLogo == null;
        }
      } catch (_) {
        // Fall back gracefully and instantly on timeout or offline
      }
    }
  }

  // Fallback default seal if no specific logo found
  if (barangayLogo == null) {
    _cachedDefaultBarangayLogo ??= await _loadAsset('assets/logo1.png');
    barangayLogo = _cachedDefaultBarangayLogo;
  }

  final branding = ReportBranding(
    cityLogo: _cachedCityLogo,
    healthOfficeLogo: _cachedHealthOfficeLogo,
    barangayLogo: barangayLogo,
    barangayName:
        barangay?.name ??
        (barangayName.trim().isEmpty
            ? 'Barangay Not Specified'
            : barangayName.trim()),
    barangayLogoIsFallback: barangayLogoIsFallback,
  );

  _brandingCache[cacheKey] = branding;
  return branding;
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
