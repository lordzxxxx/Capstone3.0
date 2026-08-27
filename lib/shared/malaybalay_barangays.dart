class BarangayReference {
  final String name;
  final String district;
  final String code;

  const BarangayReference({
    required this.name,
    required this.district,
    required this.code,
  });

  String get searchLabel => '$name $district $code'.toLowerCase();
}

class MalaybalayBarangays {
  static const List<String> districtOrder = <String>[
    'Poblacion District',
    'South Highway District',
    'North Highway District',
    'Basakan District',
    'Upper Pulangi District',
  ];

  static const List<BarangayReference> all = <BarangayReference>[
    BarangayReference(
      name: 'Barangay 01',
      district: 'Poblacion District',
      code: 'poblacion-01',
    ),
    BarangayReference(
      name: 'Barangay 02',
      district: 'Poblacion District',
      code: 'poblacion-02',
    ),
    BarangayReference(
      name: 'Barangay 03',
      district: 'Poblacion District',
      code: 'poblacion-03',
    ),
    BarangayReference(
      name: 'Barangay 04',
      district: 'Poblacion District',
      code: 'poblacion-04',
    ),
    BarangayReference(
      name: 'Barangay 05',
      district: 'Poblacion District',
      code: 'poblacion-05',
    ),
    BarangayReference(
      name: 'Barangay 06',
      district: 'Poblacion District',
      code: 'poblacion-06',
    ),
    BarangayReference(
      name: 'Barangay 07',
      district: 'Poblacion District',
      code: 'poblacion-07',
    ),
    BarangayReference(
      name: 'Barangay 08',
      district: 'Poblacion District',
      code: 'poblacion-08',
    ),
    BarangayReference(
      name: 'Barangay 09',
      district: 'Poblacion District',
      code: 'poblacion-09',
    ),
    BarangayReference(
      name: 'Barangay 10',
      district: 'Poblacion District',
      code: 'poblacion-10',
    ),
    BarangayReference(
      name: 'Barangay 11',
      district: 'Poblacion District',
      code: 'poblacion-11',
    ),
    BarangayReference(
      name: 'Aglayan',
      district: 'South Highway District',
      code: 'aglayan',
    ),
    BarangayReference(
      name: 'Bangcud',
      district: 'South Highway District',
      code: 'bangcud',
    ),
    BarangayReference(
      name: 'Cabangahan',
      district: 'South Highway District',
      code: 'cabangahan',
    ),
    BarangayReference(
      name: 'Casisang',
      district: 'South Highway District',
      code: 'casisang',
    ),
    BarangayReference(
      name: 'Magsaysay',
      district: 'South Highway District',
      code: 'magsaysay',
    ),
    BarangayReference(
      name: 'San Jose',
      district: 'South Highway District',
      code: 'san-jose',
    ),
    BarangayReference(
      name: 'Kalasungay',
      district: 'North Highway District',
      code: 'kalasungay',
    ),
    BarangayReference(
      name: 'Laguitas',
      district: 'North Highway District',
      code: 'laguitas',
    ),
    BarangayReference(
      name: 'Manalog',
      district: 'North Highway District',
      code: 'manalog',
    ),
    BarangayReference(
      name: 'Miglamin',
      district: 'North Highway District',
      code: 'miglamin',
    ),
    BarangayReference(
      name: 'Patpat',
      district: 'North Highway District',
      code: 'patpat',
    ),
    BarangayReference(
      name: 'Dalwangan',
      district: 'North Highway District',
      code: 'dalwangan',
    ),
    BarangayReference(
      name: 'Sumpong',
      district: 'North Highway District',
      code: 'sumpong',
    ),
    BarangayReference(
      name: 'Apo Macote',
      district: 'Basakan District',
      code: 'apo-macote',
    ),
    BarangayReference(
      name: 'Imbayao',
      district: 'Basakan District',
      code: 'imbayao',
    ),
    BarangayReference(
      name: 'Kibalabag',
      district: 'Basakan District',
      code: 'kibalabag',
    ),
    BarangayReference(
      name: 'Linabo',
      district: 'Basakan District',
      code: 'linabo',
    ),
    BarangayReference(
      name: 'Maligaya',
      district: 'Basakan District',
      code: 'maligaya',
    ),
    BarangayReference(
      name: 'Managok',
      district: 'Basakan District',
      code: 'managok',
    ),
    BarangayReference(
      name: 'Mapayag',
      district: 'Basakan District',
      code: 'mapayag',
    ),
    BarangayReference(
      name: 'San Martin',
      district: 'Basakan District',
      code: 'san-martin',
    ),
    BarangayReference(
      name: 'Simaya',
      district: 'Basakan District',
      code: 'simaya',
    ),
    BarangayReference(
      name: 'Sinanglanan',
      district: 'Basakan District',
      code: 'sinanglanan',
    ),
    BarangayReference(
      name: 'Sto. Nino',
      district: 'Basakan District',
      code: 'sto-nino',
    ),
    BarangayReference(
      name: 'St. Peter',
      district: 'Basakan District',
      code: 'st-peter',
    ),
    BarangayReference(
      name: 'Violeta',
      district: 'Basakan District',
      code: 'violeta',
    ),
    BarangayReference(
      name: 'Busdi',
      district: 'Upper Pulangi District',
      code: 'busdi',
    ),
    BarangayReference(
      name: 'Caburacanan',
      district: 'Upper Pulangi District',
      code: 'caburacanan',
    ),
    BarangayReference(
      name: 'Indalasa',
      district: 'Upper Pulangi District',
      code: 'indalasa',
    ),
    BarangayReference(
      name: 'Kulaman',
      district: 'Upper Pulangi District',
      code: 'kulaman',
    ),
    BarangayReference(
      name: 'Mapulo',
      district: 'Upper Pulangi District',
      code: 'mapulo',
    ),
    BarangayReference(
      name: 'Silae',
      district: 'Upper Pulangi District',
      code: 'silae',
    ),
    BarangayReference(
      name: 'Zamboanguita',
      district: 'Upper Pulangi District',
      code: 'zamboanguita',
    ),
    BarangayReference(
      name: 'Can-ayan',
      district: 'Upper Pulangi District',
      code: 'can-ayan',
    ),
    BarangayReference(
      name: 'Capitan Angel',
      district: 'Upper Pulangi District',
      code: 'capitan-angel',
    ),
    BarangayReference(
      name: 'Dumalaguing',
      district: 'Upper Pulangi District',
      code: 'dumalaguing',
    ),
  ];

  static const List<String> roleOptions = <String>[
    'BHW',
    'CHO',
    'DOCTOR',
    'CHO_SUPER_ADMIN',
    // Preserve the legacy elevated role used by existing user documents.
    'SUPER_ADMIN',
  ];

  static BarangayReference? byName(String? name) {
    if (name == null) return null;
    final normalized = name.trim().toLowerCase();
    for (final barangay in all) {
      if (barangay.name.toLowerCase() == normalized) {
        return barangay;
      }
    }
    return null;
  }

  static BarangayReference? byCode(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toLowerCase();
    for (final barangay in all) {
      if (barangay.code.toLowerCase() == normalized) {
        return barangay;
      }
    }
    return null;
  }

  static String _normalizeSearchValue(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Iterable<String> _searchAliases(BarangayReference barangay) sync* {
    yield barangay.name;
    yield barangay.district;
    yield barangay.code;
    yield barangay.code.replaceAll('-', ' ');
    yield '${barangay.name} ${barangay.district} ${barangay.code}';
    yield '${barangay.name} ${barangay.district.replaceAll(' District', '')}';
    yield barangay.name.replaceAll('.', '');
    yield barangay.name.replaceAll('-', ' ');

    final numberedBarangayMatch = RegExp(
      r'^barangay\s*0*(\d+)$',
      caseSensitive: false,
    ).firstMatch(barangay.name.trim());
    if (numberedBarangayMatch != null) {
      final plainNumber = numberedBarangayMatch.group(1);
      if (plainNumber != null && plainNumber.isNotEmpty) {
        yield 'barangay $plainNumber';
        yield plainNumber;
      }
    }
  }

  static List<BarangayReference> search(String query, {String? district}) {
    final normalizedDistrict = _normalizeSearchValue(district ?? '');
    final normalizedQuery = _normalizeSearchValue(query);
    final queryTerms = normalizedQuery.isEmpty
        ? const <String>[]
        : normalizedQuery.split(' ');

    return all.where((barangay) {
      if (normalizedDistrict.isNotEmpty &&
          _normalizeSearchValue(barangay.district) != normalizedDistrict) {
        return false;
      }

      if (queryTerms.isEmpty) {
        return true;
      }

      final haystacks = _searchAliases(
        barangay,
      ).map(_normalizeSearchValue).where((value) => value.isNotEmpty).toList();

      return queryTerms.every(
        (term) => haystacks.any((candidate) => candidate.contains(term)),
      );
    }).toList();
  }

  static Map<String, List<BarangayReference>> groupedByDistrict() {
    final grouped = <String, List<BarangayReference>>{};
    for (final barangay in all) {
      grouped.putIfAbsent(barangay.district, () => <BarangayReference>[]);
      grouped[barangay.district]!.add(barangay);
    }
    return grouped;
  }
}
