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

    test('monitoring counts only reported records for each source', () {
      final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
        morbidityRows: const [
          {'id': 'morb-1', 'barangay': 'Casisang', 'disease': 'Dengue'},
          {
            'id': 'baseline-casisang-morb-0',
            'barangay': 'Casisang',
            'disease': 'Influenza',
          },
        ],
        checkupRows: const [
          {'id': 'check-1', 'barangay': 'Casisang', 'diagnosis': 'Cough'},
        ],
        mortalityRows: const [
          {'id': 'death-1', 'barangay': 'Aglayan', 'causeOfDeath': 'Stroke'},
        ],
        prenatalRows: const [],
        immunizationRows: const [],
        referralRows: const [],
        patientRows: const [],
        bhwUsers: const [],
      );
      final morbidity = ChoBarangaySurveillanceEngine.buildSummaries(
        allCases: cases,
        bhwUsers: const [],
        syncedWorkspaceCodes: const {},
        categoryFilter: SurveillanceCaseCategory.morbidity,
      );
      final mortality = ChoBarangaySurveillanceEngine.buildSummaries(
        allCases: cases,
        bhwUsers: const [],
        syncedWorkspaceCodes: const {},
        categoryFilter: SurveillanceCaseCategory.mortality,
      );
      expect(morbidity.fold<int>(0, (total, row) => total + row.totalCases), 1);
      expect(mortality.fold<int>(0, (total, row) => total + row.totalCases), 1);
      final all = ChoBarangaySurveillanceEngine.buildSummaries(
        allCases: cases,
        bhwUsers: const [],
        syncedWorkspaceCodes: const {},
      );
      expect(all.fold<int>(0, (total, row) => total + row.totalCases), 3);
      final checkups = ChoBarangaySurveillanceEngine.buildSummaries(
        allCases: cases,
        bhwUsers: const [],
        syncedWorkspaceCodes: const {},
        categoryFilter: SurveillanceCaseCategory.checkups,
      );
      expect(checkups.fold<int>(0, (total, row) => total + row.totalCases), 1);
      expect(
        all.firstWhere((row) => row.barangay.code == 'casisang').checkupCount,
        1,
      );
      expect(morbidity.first.barangay.code, 'casisang');
      expect(mortality.first.barangay.code, 'aglayan');
      expect(
        morbidity.first.badgeColor,
        isNot(equals(morbidity.last.badgeColor)),
      );
    });

    test(
      'keeps communicable and NCD source classifications in program totals',
      () {
        final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
          morbidityRows: const [],
          checkupRows: const [
            {
              'id': 'comm-1',
              'barangay': 'Barangay 03',
              'diseaseType': 'Communicable',
              'chiefComplaint': 'Cough and fever after a sick contact',
            },
            {
              'id': 'ncd-1',
              'barangay': 'Barangay 03',
              'diseaseType': 'Non-Communicable',
              'chiefComplaint': 'BP monitoring for known hypertension',
            },
          ],
          mortalityRows: const [],
          prenatalRows: const [
            {'id': 'prenatal-1', 'barangay': 'Barangay 03'},
          ],
          immunizationRows: const [
            {'id': 'imm-1', 'barangay': 'Barangay 03', 'vaccine': 'MCV 1'},
          ],
          referralRows: const [
            {'id': 'referral-1', 'barangay': 'Barangay 03'},
          ],
          patientRows: const [],
          bhwUsers: const [],
        );
        final barangay3 = ChoBarangaySurveillanceEngine.buildSummaries(
          allCases: cases,
          bhwUsers: const [],
          syncedWorkspaceCodes: const {'POBLACION-03'},
        ).firstWhere((summary) => summary.barangay.code == 'poblacion-03');

        expect(barangay3.totalCases, 5);
        expect(barangay3.communicableCount, 1);
        expect(barangay3.nonCommunicableCount, 1);
        expect(barangay3.checkupCount, 2);
        expect(barangay3.prenatalCount, 1);
        expect(barangay3.immunizationCount, 1);
        expect(barangay3.referralCount, 1);
        expect(barangay3.workspaceSynced, isTrue);
      },
    );

    test('does not double-count an ID mirrored into a barangay workspace', () {
      final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
        morbidityRows: const [],
        checkupRows: const [
          {
            'id': 'checkup-03-01',
            'barangayCode': 'POBLACION-03',
            'diseaseType': 'Communicable',
            'chiefComplaint': 'Cough and fever',
            '_firestorePath': 'checkup_records/checkup-03-01',
          },
          {
            'id': 'checkup-03-01',
            'barangayCode': 'POBLACION-03',
            'diseaseType': 'Communicable',
            'chiefComplaint': 'Cough and fever',
            '_firestorePath':
                'barangays/POBLACION-03/checkup_records/checkup-03-01',
          },
        ],
        mortalityRows: const [],
        prenatalRows: const [],
        immunizationRows: const [],
        referralRows: const [],
        patientRows: const [],
        bhwUsers: const [],
      );

      expect(cases, hasLength(1));
      expect(cases.single.category, SurveillanceCaseCategory.communicable);
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

        // Every Malaybalay barangay remains mapped, including those without reports.
        expect(summaries.length, MalaybalayBarangays.all.length);
        expect(summaries.where((s) => s.totalCases > 0).length, 5);
        expect(summaries.any((s) => s.totalCases == 0), isTrue);
        expect(allCases.every((item) => item.isPersistedInFirestore), isTrue);

        // Casisang has the highest load -> Critical tier color
        final casisangSummary = summaries.firstWhere(
          (s) => s.barangay.code == 'casisang',
        );
        expect(casisangSummary.tier, BarangayEpidemiologicalTier.critical);
        expect(casisangSummary.assignedBhwUsers.first.name, 'Elena Santos');

        // Reported case load, rather than generated baselines, controls colors.
        final distinctTiers = summaries.map((s) => s.tier).toSet();
        expect(
          distinctTiers,
          containsAll(<BarangayEpidemiologicalTier>[
            BarangayEpidemiologicalTier.baseline,
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
                isDataTruncated: true,
                morbiditySourceLoaded: false,
                mortalitySourceLoaded: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Map counts may be incomplete'),
        findsOneWidget,
      );
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final before = map.mapController!.camera.zoom;
      final centerBefore = map.mapController!.camera.center;
      final zoomIn = find.byTooltip('Zoom in');
      await tester.ensureVisible(zoomIn);
      expect(zoomIn.hitTestable(), findsOneWidget);
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, greaterThan(before));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(centerBefore.latitude, 0.0001),
      );
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(centerBefore.longitude, 0.0001),
      );
      final zoomOut = find.byTooltip('Zoom out');
      expect(find.text('−'), findsOneWidget);
      expect(zoomOut.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(zoomOut).top,
        greaterThan(tester.getRect(zoomIn).top),
      );
      await tester.tap(zoomOut);
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, closeTo(before, 0.01));
      expect(find.text('Barangay Case & Color Directory'), findsOneWidget);
      expect(find.text('Mortality & Morbidity Monitoring'), findsOneWidget);
      expect(
        find.textContaining('Source unavailable or still loading'),
        findsNWidgets(2),
      );
      final browseAll = find.text('Browse all 46 barangays');
      await tester.ensureVisible(browseAll);
      await tester.tap(browseAll);
      await tester.pumpAndSettle();
      expect(find.text('Browse barangays'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('barangay-directory-search')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close barangay directory'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final width in <double>[768, 1024, 1440]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Layout failed at $width px',
        );
      }
    });

    testWidgets(
      'monitoring selects reported morbidity and mortality barangays',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
          morbidityRows: const [
            {
              'id': 'morb-casisang-1',
              'barangay': 'Casisang',
              'disease': 'Dengue',
            },
            {
              'id': 'morb-casisang-2',
              'barangay': 'Casisang',
              'disease': 'Influenza',
            },
          ],
          checkupRows: const [],
          mortalityRows: const [
            {
              'id': 'death-aglayan-1',
              'barangay': 'Aglayan',
              'causeOfDeath': 'Stroke',
            },
          ],
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
                  syncedWorkspaceCodes: const {},
                  windowLabel: 'Last 6 months',
                  onBarangaySelected: (barangay) => selected = barangay,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mortality & Morbidity Monitoring'), findsOneWidget);
        final reportedKpi = find.byKey(const ValueKey('heatmap-kpi-reported'));
        expect(
          find.descendant(of: reportedKpi, matching: find.text('3 cases')),
          findsOneWidget,
        );
        expect(find.text('Casisang (2)'), findsOneWidget);
        final mortalityView = find.byKey(
          const ValueKey('heatmap-view-mortality'),
        );
        await tester.ensureVisible(mortalityView);
        await tester.tap(mortalityView);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('1 death')),
          findsOneWidget,
        );
        expect(find.text('Barangay Mortality Directory'), findsOneWidget);
        final chooseCondition = find.byKey(
          const ValueKey('choose-condition-button'),
        );
        await tester.ensureVisible(chooseCondition);
        await tester.tap(chooseCondition);
        await tester.pumpAndSettle();
        expect(find.text('All Causes'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('condition-picker-search')),
          'Stroke',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('condition-Stroke')));
        await tester.pumpAndSettle();
        expect(find.text('Stroke by Barangay'), findsOneWidget);
        final morbidityView = find.byKey(
          const ValueKey('heatmap-view-morbidity'),
        );
        await tester.ensureVisible(morbidityView);
        await tester.tap(morbidityView);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('2 illnesses')),
          findsOneWidget,
        );
        expect(find.text('Barangay Morbidity Directory'), findsOneWidget);
        await tester.ensureVisible(chooseCondition);
        await tester.tap(chooseCondition);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('condition-Stroke')), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('condition-picker-search')),
          'Dengue',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('condition-Dengue Fever')));
        await tester.pumpAndSettle();
        expect(find.text('Dengue Fever by Barangay'), findsOneWidget);
        expect(
          find.descendant(of: reportedKpi, matching: find.text('1 illness')),
          findsOneWidget,
        );
        final conditionsView = find.byKey(
          const ValueKey('heatmap-view-conditions'),
        );
        await tester.ensureVisible(conditionsView);
        await tester.tap(conditionsView);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('3 cases')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('condition-source-all')));
        await tester.pumpAndSettle();
        expect(find.text('Communicable Diseases'), findsOneWidget);
        expect(find.text('Clinical Check-ups'), findsNothing);
        expect(find.text('Non-Communicable (NCD)'), findsNothing);
        await tester.tap(find.text('All record types').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(chooseCondition);
        await tester.tap(chooseCondition);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('condition-picker-search')),
          'Dengue',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('condition-Dengue Fever')));
        await tester.pumpAndSettle();
        expect(find.text('Dengue Fever by Barangay'), findsOneWidget);
        expect(
          find.descendant(of: reportedKpi, matching: find.text('1 case')),
          findsOneWidget,
        );
        final barangaySearch = find.byType(TextField).first;
        await tester.enterText(barangaySearch, 'no such barangay');
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('0 cases')),
          findsOneWidget,
        );
        expect(
          find.textContaining('No barangays match these filters'),
          findsOneWidget,
        );
        await tester.enterText(barangaySearch, '');
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('1 case')),
          findsOneWidget,
        );
        await tester.tap(chooseCondition);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('condition-all')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('3 cases')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('condition-source-all')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Communicable Diseases').last);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: reportedKpi, matching: find.text('2 cases')),
          findsOneWidget,
        );
        await tester.tap(chooseCondition);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('condition-Stroke')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('condition-all')));
        await tester.pumpAndSettle();
        final reset = find.text('Reset');
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('condition-source-all')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: reportedKpi, matching: find.text('3 cases')),
          findsOneWidget,
        );
        final overviewView = find.byKey(
          const ValueKey('heatmap-view-overview'),
        );
        await tester.ensureVisible(overviewView);
        await tester.tap(overviewView);
        await tester.pumpAndSettle();
        final morbidityRow = find.byKey(
          const ValueKey('monitoring-morbidity-casisang'),
        );
        await tester.ensureVisible(morbidityRow);
        await tester.tap(morbidityRow);
        await tester.pumpAndSettle();
        expect(selected?.code, 'casisang');
        expect(find.text('Barangay Morbidity Directory'), findsOneWidget);
        await tester.ensureVisible(overviewView);
        await tester.tap(overviewView);
        await tester.pumpAndSettle();
        final mortalityRow = find.byKey(
          const ValueKey('monitoring-mortality-aglayan'),
        );
        await tester.ensureVisible(mortalityRow);
        await tester.tap(mortalityRow);
        await tester.pumpAndSettle();
        expect(selected?.code, 'aglayan');
        expect(find.text('Barangay Mortality Directory'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('record category filters clinical check-up reports', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cases = ChoBarangaySurveillanceEngine.aggregateAllCases(
        morbidityRows: const [
          {'id': 'morb-1', 'barangay': 'Casisang', 'disease': 'Influenza'},
        ],
        checkupRows: const [
          {'id': 'check-1', 'barangay': 'Aglayan', 'diagnosis': 'Dengue'},
        ],
        mortalityRows: const [],
        prenatalRows: const [],
        immunizationRows: const [],
        referralRows: const [],
        patientRows: const [],
        bhwUsers: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChoBarangaySurveillanceMap(
                allCases: cases,
                bhwUsers: const [],
                syncedWorkspaceCodes: const {},
                windowLabel: 'Last 6 months',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('heatmap-view-conditions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('condition-source-all')));
      await tester.pumpAndSettle();
      expect(find.text('Clinical Check-ups'), findsOneWidget);
      await tester.tap(find.text('Clinical Check-ups'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('heatmap-kpi-reported')),
          matching: find.text('1 case'),
        ),
        findsOneWidget,
      );
      final selector = find.byKey(const ValueKey('choose-condition-button'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('condition-Dengue Fever')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('condition-Influenza')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('condition-Dengue Fever')));
      await tester.pumpAndSettle();
      expect(find.text('Dengue Fever by Barangay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

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

      // Switch to the dedicated condition explorer before using the directory.
      final conditionView = find.byKey(
        const ValueKey('heatmap-view-conditions'),
      );
      await tester.ensureVisible(conditionView);
      await tester.tap(conditionView);
      await tester.pumpAndSettle();

      // Browse, search for a barangay below the initially visible rows,
      // then select it to focus the map.
      final browseAll = find.text('Browse all 46 barangays');
      await tester.ensureVisible(browseAll);
      await tester.tap(browseAll);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('barangay-directory-search')),
        'Casisang',
      );
      await tester.pumpAndSettle();
      selected = null;
      await tester.tap(
        find.byKey(const ValueKey<String>('all-barangay-item-casisang')),
      );
      await tester.pumpAndSettle();
      expect(selected?.code, 'casisang');
      expect(find.text('Browse barangays'), findsNothing);
    });
  });
}
