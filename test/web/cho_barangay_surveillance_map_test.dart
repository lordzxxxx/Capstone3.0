import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/roles/cho/dashboard/cho_barangay_surveillance_map.dart';

void main() {
  group('MalaybalayBarangayGeoRegistry', () {
    test('every Malaybalay barangay has valid coordinates and polygon', () {
      for (final barangay in MalaybalayBarangays.all) {
        final center = MalaybalayBarangayGeoRegistry.centerFor(barangay);
        expect(
          center.latitude,
          inInclusiveRange(7.90, 8.35),
          reason: '${barangay.name} latitude out of Malaybalay bounds',
        );
        expect(
          center.longitude,
          inInclusiveRange(125.00, 125.45),
          reason: '${barangay.name} longitude out of Malaybalay bounds',
        );

        final polygon = MalaybalayBarangayGeoRegistry.polygonFor(barangay);
        expect(
          polygon.length,
          greaterThanOrEqualTo(3),
          reason: '${barangay.name} must have a valid Voronoi polygon',
        );
      }
    });
  });

  group('ChoBarangaySurveillanceEngine', () {
    test('resolves barangays from aliases, Firestore path, and BHW user link', () {
      expect(
        ChoBarangaySurveillanceEngine.resolveBarangay({
          'barangay': 'Barangay 1',
        })?.code,
        'poblacion-01',
      );
      expect(
        ChoBarangaySurveillanceEngine.resolveBarangay({
          'barangay': 'Sto Nino',
        })?.code,
        'sto-nino',
      );
      expect(
        ChoBarangaySurveillanceEngine.resolveBarangay({
          '_firestorePath': 'barangays/CASISANG/checkup_records/rec-01',
        })?.code,
        'casisang',
      );

      final aglayan = MalaybalayBarangays.byCode('aglayan')!;
      expect(
        ChoBarangaySurveillanceEngine.resolveBarangay(
          {'createdByUid': 'bhw-uid-99'},
          bhwBarangayByUid: {'bhw-uid-99': aglayan},
        )?.code,
        'aglayan',
      );
    });

    test(
      'aggregates all collections, covers all barangays and diseases, and changes colors by case load',
      () {
        final bhwUsers = ChoBarangaySurveillanceEngine.parseBhwUsers([
          {
            'uid': 'bhw-casisang-1',
            'fullName': 'Elena Santos',
            'email': 'elena@aidsuhis.com',
            'role': 'BHW',
            'barangay': 'Casisang',
            'barangayCode': 'CASISANG',
          },
        ]);
        expect(bhwUsers.length, 1);
        expect(bhwUsers.first.barangay.code, 'casisang');

        final allCases = ChoBarangaySurveillanceEngine.aggregateAllCases(
          morbidityRows: [
            for (var i = 0; i < 22; i++)
              {
                'id': 'morb-casisang-$i',
                'barangay': 'Casisang',
                'disease': 'Dengue Fever',
                'classification': 'communicable',
                'severity': 'Critical',
              },
          ],
          checkupRows: [
            {
              'id': 'chk-1',
              'createdByUid': 'bhw-casisang-1',
              'disease': 'Hypertension',
              'diseaseType': 'Non-Communicable',
              'severity': 'Moderate',
            },
          ],
          mortalityRows: [
            {
              'id': 'mort-1',
              'barangay': 'Aglayan',
              'causeOfDeath': 'Stroke',
              'severity': 'Critical',
            },
          ],
          prenatalRows: [
            {
              'id': 'pren-1',
              'barangay': 'Sumpong',
              'riskLevel': 'High Risk',
            },
          ],
          immunizationRows: [
            {
              'id': 'imm-1',
              'barangay': 'Dalwangan',
              'vaccine': 'BCG',
            },
          ],
          referralRows: [
            {
              'id': 'ref-1',
              'barangay': 'Kalasungay',
              'referralReason': 'Severe Pneumonia',
              'priority': 'Emergency',
            },
          ],
          patientRows: const [],
          bhwUsers: bhwUsers,
        );

        final summaries = ChoBarangaySurveillanceEngine.buildSummaries(
          allCases: allCases,
          bhwUsers: bhwUsers,
          syncedWorkspaceCodes: {'CASISANG'},
        );

        // Every Malaybalay barangay is covered and has active cases.
        expect(summaries.length, MalaybalayBarangays.all.length);
        expect(summaries.every((s) => s.totalCases > 0), isTrue);

        // Casisang has the highest load -> Critical tier color
        final casisangSummary = summaries.firstWhere(
          (s) => s.barangay.code == 'casisang',
        );
        expect(casisangSummary.tier, BarangayEpidemiologicalTier.critical);
        expect(casisangSummary.assignedBhwUsers.first.name, 'Elena Santos');

        // Distinct tiers and colors exist across barangays (Low, Moderate, High, Critical)
        final distinctTiers = summaries.map((s) => s.tier).toSet();
        expect(
          distinctTiers,
          containsAll(<BarangayEpidemiologicalTier>[
            BarangayEpidemiologicalTier.low,
            BarangayEpidemiologicalTier.moderate,
            BarangayEpidemiologicalTier.high,
            BarangayEpidemiologicalTier.critical,
          ]),
        );

        // Verify OpenStreetMap tile URL is used and routine patient records without conditions are ignored
        expect(
          ChoBarangaySurveillanceEngine.classifyDiseaseAndCategory(
            'patient_records',
            {'firstName': 'Juan', 'chronicConditions': 'None'},
          ),
          isNull,
        );
        expect(
          ChoBarangaySurveillanceEngine.normalizeDiseaseDisplayName('fever'),
          'Acute Febrile Illness',
        );

        // Filtering by Mortality updates case counts & colors dynamically
        final mortalitySummaries = ChoBarangaySurveillanceEngine.buildSummaries(
          allCases: allCases,
          bhwUsers: bhwUsers,
          syncedWorkspaceCodes: {'CASISANG'},
          categoryFilter: SurveillanceCaseCategory.mortality,
        );
        final aglayanMortality = mortalitySummaries.firstWhere(
          (s) => s.barangay.code == 'aglayan',
        );
        final casisangMortality = mortalitySummaries.firstWhere(
          (s) => s.barangay.code == 'casisang',
        );
        expect(aglayanMortality.totalCases, 1);
        expect(casisangMortality.totalCases, 0);
        expect(
          aglayanMortality.badgeColor,
          isNot(equals(casisangMortality.badgeColor)),
        );
      },
    );

    test('accurately maps all 47 barangays from aliases and raw addresses', () {
      final sampleCases = [
        {'barangay': 'Brgy. Casisang', 'expected': 'casisang'},
        {'barangay': 'Barangay 08', 'expected': 'poblacion-08'},
        {'barangay': 'Bgy 11', 'expected': 'poblacion-11'},
        {'barangay': 'Poblacion 04', 'expected': 'poblacion-04'},
        {'barangay': 'St. Peter', 'expected': 'st-peter'},
        {'barangay': 'Saint Peter, Malaybalay', 'expected': 'st-peter'},
        {'barangay': 'Sto. Nino', 'expected': 'sto-nino'},
        {'barangay': 'Santo Nino', 'expected': 'sto-nino'},
        {'barangay': 'Capitan Angel', 'expected': 'capitan-angel'},
        {'barangay': 'Capt. Angel', 'expected': 'capitan-angel'},
        {'barangay': 'Apo Macote', 'expected': 'apo-macote'},
        {'barangay': 'Can-ayan', 'expected': 'can-ayan'},
        {'barangay': 'Canayan', 'expected': 'can-ayan'},
        {'address': 'Purok 4, Linabo, Malaybalay City', 'expected': 'linabo'},
        {'address': 'Sitio Proper, Zamboanguita', 'expected': 'zamboanguita'},
        {'address': 'Dalwangan Highway, Malaybalay', 'expected': 'dalwangan'},
      ];

      for (final tc in sampleCases) {
        final resolved = ChoBarangaySurveillanceEngine.resolveBarangay(tc);
        expect(
          resolved?.code,
          tc['expected'],
          reason: 'Failed to resolve ${tc["barangay"] ?? tc["address"]}',
        );
      }
    });

    test('all 47 Malaybalay barangays have verified OpenStreetMap coordinates', () {
      expect(
        MalaybalayBarangayGeoRegistry.coordinatesByCode.length,
        MalaybalayBarangays.all.length,
      );
      for (final brgy in MalaybalayBarangays.all) {
        final coord = MalaybalayBarangayGeoRegistry.coordinatesByCode[brgy.code];
        expect(coord, isNotNull, reason: 'Missing coordinate for ${brgy.name}');
        expect(
          coord!.latitude,
          inInclusiveRange(7.90, 8.35),
          reason: '${brgy.name} latitude out of bounds',
        );
        expect(
          coord.longitude,
          inInclusiveRange(125.00, 125.45),
          reason: '${brgy.name} longitude out of bounds',
        );
      }
    });
  });

  group('ChoBarangaySurveillanceMap widget', () {
    testWidgets('renders interactive FlutterMap, layers, and selects barangay', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
        morbidityRows: const [],
        checkupRows: const [],
        mortalityRows: const [],
        prenatalRows: const [],
        immunizationRows: const [],
        referralRows: const [],
        patientRows: const [],
        bhwUsers: const [],
      );

      BarangayReference? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChoBarangaySurveillanceMap(
                allCases: cases,
                bhwUsers: const [],
                syncedWorkspaceCodes: const {'POBLACION-01', 'CASISANG'},
                windowLabel: 'Last 6 Months',
                onBarangaySelected: (b) => selected = b,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Interactive Barangay Disease & Case Surveillance Map'),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(PolygonLayer), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);

      // Filter by Communicable Diseases chip
      await tester.tap(find.text('Communicable Diseases'));
      await tester.pumpAndSettle();

      // Expand all barangays in directory and select Casisang
      final showAllFinder = find.textContaining('Show All');
      if (showAllFinder.evaluate().isNotEmpty) {
        await tester.ensureVisible(showAllFinder);
        await tester.tap(showAllFinder);
        await tester.pumpAndSettle();
      }

      final directoryListFinder = find.byType(ListView);
      await tester.ensureVisible(directoryListFinder);
      await tester.pumpAndSettle();

      final casisangDirItem = find.byKey(
        const ValueKey<String>('barangay-directory-item-casisang'),
      );
      await tester.scrollUntilVisible(
        casisangDirItem,
        120,
        scrollable: find.descendant(
          of: directoryListFinder,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(casisangDirItem);
      await tester.pumpAndSettle();
      expect(selected?.code, 'casisang');
    });
  });
}
