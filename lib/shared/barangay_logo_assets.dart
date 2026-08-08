String? resolveBarangayLogoAssetPath({
  String? barangayCode,
  String? barangayName,
}) {
  final normalizedCode = _normalizeValue(barangayCode);
  if (normalizedCode.isNotEmpty) {
    final asset = _barangayLogoAssetByCode[normalizedCode];
    if (asset != null && asset.isNotEmpty) {
      return asset;
    }
  }

  final normalizedName = _normalizeValue(barangayName);
  if (normalizedName.isEmpty) {
    return null;
  }

  for (final entry in _barangayLogoAssetByName.entries) {
    if (entry.key == normalizedName) {
      return entry.value;
    }
  }

  return null;
}

String _normalizeValue(String? value) {
  return (value ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '-',
  );
}

const Map<String, String> _barangayLogoAssetByCode = <String, String>{
  'poblacion-01': 'assets/logo/brgy-1-logo-270x270-1.png',
  'poblacion-02': 'assets/logo/Barangay-2-Edit-270x270-1.png',
  'poblacion-03': 'assets/logo/Barangay3logo.png',
  'poblacion-04': 'assets/logo/Barabgay-4-size-1-270x270-1 (1).png',
  'poblacion-05': 'assets/logo/Barangay-5-Edit-270x270-1.png',
  'poblacion-06': 'assets/logo/barangay-6-logo-2019-270x270-1.png',
  'poblacion-07': 'assets/logo/BARANGAY-7-270x270-1.png',
  'poblacion-08': 'assets/logo/brgy.-8-270x270-1.png',
  'poblacion-09': 'assets/logo/barangay-9.jpg',
  'poblacion-10': 'assets/logo/brgy.10-270x270-1.png',
  'poblacion-11': 'assets/logo/barangay-11.png',
  'aglayan': 'assets/logo/Barangay-Aglayan-270x270-1.png',
  'apo-macote': 'assets/logo/BARANGAY-APO-MACOTE-270x270-1.png',
  'bangcud': 'assets/logo/BRGY.-BANGCUD-270x270-1.png',
  'busdi': 'assets/logo/BRGY.-BUSDI-270x270-1.png',
  'cabangahan': 'assets/logo/BARANGAY-CABANGAHAN-270x270-1.png',
  'caburacanan': 'assets/logo/CABURACANAN-LOGO-ws-270x270-1.png',
  'can-ayan': 'assets/logo/can-ayan-logo-270x270-1.png',
  'capitan-angel':
      'assets/logo/Barangay-Capitan-Angel-Edit-Recovered-270x270-1.png',
  'casisang': 'assets/logo/BARANGAY-CASISANG-Recovered-270x270-1.png',
  'dalwangan': 'assets/logo/DALWANGAN-270x270-1.png',
  'imbayao': 'assets/logo/imbayao-logo-720-1-150x150-1.png',
  'indalasa': 'assets/logo/Indalasa-edit-270x270-1.png',
  'kalasungay': 'assets/logo/barangay-kalasungay.png',
  'kibalabag': 'assets/logo/kibalabag-300x300-1.jpg',
  'kulaman': 'assets/logo/kulaman-logo-270x270-1.png',
  'laguitas': 'assets/logo/Barangay-Laguitas-270x270-1.png',
  'linabo': 'assets/logo/linabo-logo-2-1-270x270-1.png',
  'magsaysay': 'assets/logo/magsaysay-3-300x300-1.jpg',
  'maligaya': 'assets/logo/maligaya-logo-270x270-1.png',
  'managok': 'assets/logo/managok-300x300-1.jpg',
  'manalog': 'assets/logo/MANALOG-LOGO-300x300-1.png',
  'mapayag': 'assets/logo/mapayag-logo-old-270x270-1.png',
  'mapulo': 'assets/logo/mapulo-logo-1-270x270-1.png',
  'miglamin': 'assets/logo/miglamin-logo-270x270-1.png',
  'patpat': 'assets/logo/patpat-300x300-1.jpg',
  'san-jose': 'assets/logo/san-jose-3-300x300-1.jpg',
  'san-martin': 'assets/logo/SAN-MARTIN-LOGO-1-270x270-1.png',
  'silae': 'assets/logo/BARANGAY-SILAE-270x270-1.png',
  'simaya': 'assets/logo/SIMAYA-LOGO-270x270-1.png',
  'sinanglanan': 'assets/logo/sinanglanan-3-300x300-1.jpg',
  'sto-nino': 'assets/logo/sto.-nino-logo-270x270-1.png',
  'st-peter': 'assets/logo/barangay-st.peter-logo-size-270x270-1.png',
  'sumpong': 'assets/logo/sumpong-logo-270x270-1.png',
  'santo-nino': 'assets/logo/sto.-nino-logo-270x270-1.png',
  'violeta': 'assets/logo/VIOLETA-270x270-1.png',
  'zamboanguita': 'assets/logo/barangay-zamboanguitalogo-270x270-1.png',
};

const Map<String, String> _barangayLogoAssetByName = <String, String>{
  'barangay-01': 'assets/logo/brgy-1-logo-270x270-1.png',
  'barangay-02': 'assets/logo/Barangay-2-Edit-270x270-1.png',
  'barangay-03': 'assets/logo/Barangay3logo.png',
  'barangay-04': 'assets/logo/Barabgay-4-size-1-270x270-1 (1).png',
  'barangay-05': 'assets/logo/Barangay-5-Edit-270x270-1.png',
  'barangay-06': 'assets/logo/barangay-6-logo-2019-270x270-1.png',
  'barangay-07': 'assets/logo/BARANGAY-7-270x270-1.png',
  'barangay-08': 'assets/logo/brgy.-8-270x270-1.png',
  'barangay-09': 'assets/logo/barangay-9.jpg',
  'barangay-10': 'assets/logo/brgy.10-270x270-1.png',
  'barangay-11': 'assets/logo/barangay-11.png',
  'aglayan': 'assets/logo/Barangay-Aglayan-270x270-1.png',
  'apo-macote': 'assets/logo/BARANGAY-APO-MACOTE-270x270-1.png',
  'bangcud': 'assets/logo/BRGY.-BANGCUD-270x270-1.png',
  'busdi': 'assets/logo/BRGY.-BUSDI-270x270-1.png',
  'cabangahan': 'assets/logo/BARANGAY-CABANGAHAN-270x270-1.png',
  'caburacanan': 'assets/logo/CABURACANAN-LOGO-ws-270x270-1.png',
  'can-ayan': 'assets/logo/can-ayan-logo-270x270-1.png',
  'capitan-angel':
      'assets/logo/Barangay-Capitan-Angel-Edit-Recovered-270x270-1.png',
  'casisang': 'assets/logo/BARANGAY-CASISANG-Recovered-270x270-1.png',
  'dalwangan': 'assets/logo/DALWANGAN-270x270-1.png',
  'imbayao': 'assets/logo/imbayao-logo-720-1-150x150-1.png',
  'indalasa': 'assets/logo/Indalasa-edit-270x270-1.png',
  'kalasungay': 'assets/logo/barangay-kalasungay.png',
  'kibalabag': 'assets/logo/kibalabag-300x300-1.jpg',
  'kulaman': 'assets/logo/kulaman-logo-270x270-1.png',
  'laguitas': 'assets/logo/Barangay-Laguitas-270x270-1.png',
  'linabo': 'assets/logo/linabo-logo-2-1-270x270-1.png',
  'magsaysay': 'assets/logo/magsaysay-3-300x300-1.jpg',
  'maligaya': 'assets/logo/maligaya-logo-270x270-1.png',
  'managok': 'assets/logo/managok-300x300-1.jpg',
  'manalog': 'assets/logo/MANALOG-LOGO-300x300-1.png',
  'mapayag': 'assets/logo/mapayag-logo-old-270x270-1.png',
  'mapulo': 'assets/logo/mapulo-logo-1-270x270-1.png',
  'miglamin': 'assets/logo/miglamin-logo-270x270-1.png',
  'patpat': 'assets/logo/patpat-300x300-1.jpg',
  'san-jose': 'assets/logo/san-jose-3-300x300-1.jpg',
  'san-martin': 'assets/logo/SAN-MARTIN-LOGO-1-270x270-1.png',
  'silae': 'assets/logo/BARANGAY-SILAE-270x270-1.png',
  'simaya': 'assets/logo/SIMAYA-LOGO-270x270-1.png',
  'sinanglanan': 'assets/logo/sinanglanan-3-300x300-1.jpg',
  'sto-nino': 'assets/logo/sto.-nino-logo-270x270-1.png',
  'st-peter': 'assets/logo/barangay-st.peter-logo-size-270x270-1.png',
  'santo-nino': 'assets/logo/sto.-nino-logo-270x270-1.png',
  'violeta': 'assets/logo/VIOLETA-270x270-1.png',
  'sumpong': 'assets/logo/sumpong-logo-270x270-1.png',
  'zamboanguita': 'assets/logo/barangay-zamboanguitalogo-270x270-1.png',
};
