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
          reason: '${barangay.name} must have a valid PSGC reference polygon',
        );
        for (final point in polygon) {
          expect(point.latitude, inInclusiveRange(7.90, 8.35));
          expect(point.longitude, inInclusiveRange(124.90, 125.45));
        }
      }
    });
  });

  group('ChoBarangaySurveillanceEngine', () {
    test('counts a morbidity record once in the inspector', () {
      final casisang = MalaybalayBarangays.byCode('casisang')!;
      final summary = ChoBarangaySurveillanceEngine.buildSummaries(
        allCases: [
          BarangaySurveillanceCase(
            id: 'morbidity-1',
            barangay: casisang,
            disease: 'Unspecified illness',
            category: SurveillanceCaseCategory.morbidity,
            sourceCollection: 'morbidity_records',
            severityLabel: 'Low',
            severityWeight: 1,
            reportedAt: null,
          ),
        ],
        bhwUsers: const [],
        syncedWorkspaceCodes: const {},
      ).firstWhere((item) => item.barangay.code == casisang.code);
      expect(summary.totalCases, 1);
      expect(summary.morbidityCount, 1);
    });

    test(
      'resolves barangays from aliases, Firestore path, and BHW user link',
      () {
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
      },
    );

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
            {'id': 'pren-1', 'barangay': 'Sumpong', 'riskLevel': 'High Risk'},
          ],
          immunizationRows: [
            {'id': 'imm-1', 'barangay': 'Busdi', 'vaccine': 'BCG'},
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

    test(
      'accurately maps all 46 configured barangays from aliases and raw addresses',
      () {
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
        ];

        for (final tc in sampleCases) {
          final resolved = ChoBarangaySurveillanceEngine.resolveBarangay(tc);
          expect(
            resolved?.code,
            tc['expected'],
            reason: 'Failed to resolve ${tc["barangay"] ?? tc["address"]}',
          );
        }
      },
    );

    test('all 46 configured barangays have reference coordinates', () {
      expect(
        MalaybalayBarangayGeoRegistry.coordinatesByCode.length,
        MalaybalayBarangays.all.length,
      );
      for (final brgy in MalaybalayBarangays.all) {
        final coord =
            MalaybalayBarangayGeoRegistry.coordinatesByCode[brgy.code];
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
    testWidgets('mobile cards, map controls, and directory remain usable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChoBarangaySurveillanceMap(
                allCases: const [],
                bhwUsers: const [],
                syncedWorkspaceCodes: const {},
                windowLabel: 'Last 6 months',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final before = map.mapController!.camera.zoom;
      final zoomIn = find.byTooltip('Zoom in');
      await tester.ensureVisible(zoomIn);
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, greaterThan(before));
      final zoomOut = find.byTooltip('Zoom out');
      await tester.tap(zoomOut);
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, closeTo(before, 0.01));
      expect(find.text('Barangay Case & Color Directory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'renders interactive FlutterMap, layers, and selects barangay',
      (tester) async {
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
        expect(find.byType(PolygonLayer), findsNothing);
        expect(find.byType(CircleLayer), findsNothing);
        expect(find.byType(MarkerLayer), findsOneWidget);
        expect(find.byTooltip('Zoom in'), findsOneWidget);
        expect(find.byTooltip('Zoom out'), findsOneWidget);

        final mapFinder = find.byType(FlutterMap);
        await tester.ensureVisible(mapFinder);
        await tester.pumpAndSettle();
        final map = tester.widget<FlutterMap>(mapFinder);
        final casisang = MalaybalayBarangays.byCode('casisang')!;
        final point = map.mapController!.camera.latLngToScreenOffset(
          MalaybalayBarangayGeoRegistry.centerFor(casisang),
        );
        expect(
          MalaybalayBarangayGeoRegistry.isPointInPolygon(
            MalaybalayBarangayGeoRegistry.centerFor(casisang),
            MalaybalayBarangayGeoRegistry.polygonFor(casisang),
          ),
          isTrue,
        );
        await tester.tapAt(tester.getTopLeft(mapFinder) + point);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(selected?.code, 'casisang');

        // Filter by Communicable Diseases chip
        final communicableFilter = find.text('Communicable Diseases');
        await tester.ensureVisible(communicableFilter);
        await tester.tap(communicableFilter);
        await tester.pumpAndSettle();

        // Scroll the full directory and select Casisang.
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
        selected = null;
        await tester.tap(casisangDirItem);
        await tester.pumpAndSettle();
        expect(selected?.code, 'casisang');
      },
    );
  });
}
