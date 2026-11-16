# CHO surveillance map

The CHO dashboard draws 46 separate Malaybalay barangay zones. The barangay count agrees with the Philippine Statistics Authority's [Malaybalay PSGC listing](https://psa.gov.ph/classification/psgc/barangays/1001312000). Dumalaguing is not in the city registry.

## Boundary reference

The encoded polygons in `cho_barangay_surveillance_map.dart` come from the 2015 barangay shapefile in [altcoder/philippines-psgc-shapefiles](https://github.com/altcoder/philippines-psgc-shapefiles), filtered by `ADM3_PCODE = PH101312000` and matched to the application's 46 barangay codes. The polygons are simplified and rounded for web rendering. They are a historical visualization reference, not surveyed or currently certified cadastral boundaries. The source and year are disclosed in the dashboard.

The release-browser regression test checks all decoded points remain inside the Malaybalay bounding range. This is important because bitwise complement decoding of negative polyline deltas produced invalid coordinates in Flutter Web even when the same data passed native tests. A local GIS comparison against the source shapefile found all 46 simplified polygons valid and contiguous; the lowest area overlap with its source polygon was about 94.5% for a small Poblacion barangay.

## Case colors

The map aggregates cases by normalized barangay code. The selected category, disease, and color metric recompute the per-barangay counts, score, thresholds, legend, and polygon colors. Zero values are neutral gray; positive tiers use progressively darker red shades. Thresholds are calculated from the nonzero barangay values in the current view, so the displayed numeric ranges must be read with the selected filter. The directory lists all matching barangays, sorted by reported cases; its progress line compares each count with the highest current count.

The city mask is cut from the same polygon geometry as the fills. Selecting a polygon or directory row opens that barangay's inspector. Zoom controls change the current camera zoom; Reset returns to the city view.
