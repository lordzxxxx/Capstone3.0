# CHO surveillance map

The CHO dashboard draws 46 separate Malaybalay barangay zones. The barangay count agrees with the Philippine Statistics Authority's [Malaybalay PSGC listing](https://psa.gov.ph/classification/psgc/barangays/1001312000). Dumalaguing is not in the city registry.

## Boundary reference

The encoded polygons in `cho_barangay_surveillance_map.dart` come from the 2015 barangay shapefile in [altcoder/philippines-psgc-shapefiles](https://github.com/altcoder/philippines-psgc-shapefiles), filtered by `ADM3_PCODE = PH101312000` and matched to the application's 46 barangay codes. The polygons are simplified and rounded for web rendering. They are a historical visualization reference, not surveyed or currently certified cadastral boundaries. The source and year are disclosed in the dashboard.

The release-browser regression test checks all decoded points remain inside the Malaybalay bounding range. This is important because bitwise complement decoding of negative polyline deltas produced invalid coordinates in Flutter Web even when the same data passed native tests. A local GIS comparison against the source shapefile found all 46 simplified polygons valid and contiguous; the lowest area overlap with its source polygon was about 94.5% for a small Poblacion barangay.

## Case colors

The map aggregates reported cases by normalized barangay code. Overview, Mortality, Morbidity, and Diseases & Conditions are separate views. Mortality offers a searchable cause-of-death selector; Morbidity offers a searchable illness selector. Diseases & Conditions shows available record categories first, then condition names from that category. Source categories such as Clinical Check-ups include reports from that collection even when a report is also classified as communicable or non-communicable. Each selector includes an aggregate option. Reset clears filters within the current view. The selected view, condition, district, and color metric recompute the per-barangay counts, score, legend, polygon fills, summary cards, directory, and concentration matrix. Barangays outside a district or search filter are muted while all 46 city boundaries remain visible. Zero values are neutral gray; positive tiers use progressively darker red shades. Thresholds are calculated from nonzero values in the selected view, so the numeric ranges must be read with the active filter.

Only mapped clinical reports are counted. The former `baseline-*` generated illness and check-up records are excluded from all map views, including Overview, even if they were previously written to Firestore. The CHO and BHW dashboards no longer generate these records when a barangay has no reports. Existing Firestore documents are left untouched; a separate reviewed data-cleanup process would be needed to remove them from storage. The map shows a source-availability notice while source subscriptions have not loaded. Mortality uses `mortality_records`; Morbidity uses `morbidity_records`. A zero count means no matching reports were returned by the loaded sources, not that a barangay is disease-free.

Dashboard source subscriptions are capped at 2,500 records per collection. When any collection reaches that cap, the map displays an incomplete-count notice; the displayed totals must not be read as a complete historical census.

The city mask is cut from the same polygon geometry as the fills. Selecting a polygon or directory row opens that barangay's inspector. Zoom controls change the current camera zoom without recentering; Reset returns to the city view.
