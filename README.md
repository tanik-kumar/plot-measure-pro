# PlotMeasure Pro

PlotMeasure Pro is a native macOS land-measurement app built with `SwiftUI` and `PDFKit`. It opens scanned or vector cadastral PDFs, calibrates map scale in PDF page coordinates, lets you draw/edit plot boundaries, and exports the results as reports or annotated PDFs.

## What is implemented

- Native macOS UI with left sidebar, PDF canvas, right inspector, toolbar, and status bar
- PDF import, page navigation, page rotation, zoom, and pan
- Calibration methods:
  - manual two-point distance calibration
  - `1:N` ratio calibration
  - map scale calibration such as `16 inches = 1 mile`
  - scale-bar calibration using two clicked endpoints and entered bar value
- Measurement tools:
  - distance
  - path length
  - polygon area
- Live overlay rendering with:
  - point labels `P1`, `P2`, ...
  - side length labels
  - polygon fill
  - centroid
  - optional bounding box
  - optional triangulation debug overlay
  - invalid/self-intersecting polygon warning
- Editing:
  - drag vertices
  - insert a vertex by double-clicking a segment in edit mode
  - delete selected vertex
  - numeric point-coordinate edits in the inspector
  - undo/redo snapshot history
- OCR-assisted scale suggestion scanning with Vision
- Edge snapping using Core Image edge detection for scanned maps
- Save/load full project state as JSON
- Export:
  - JSON report
  - CSV report
  - annotated PDF
- Bihar/India land units with configurable defaults:
  - sq ft
  - sq m
  - acre
  - hectare
  - decimal
  - bigha
  - kattha
  - dhur

## Folder structure

```text
PlotMeasurePro/
├── Package.swift
├── README.md
├── Docs/
│   └── plotmeasure-pro-preview.svg
├── Scripts/
│   └── package_app.sh
├── Sources/PlotMeasurePro/
│   ├── App/
│   ├── Models/
│   ├── Services/
│   ├── Utilities/
│   └── Views/
└── Tests/PlotMeasureProTests/
    └── GeometryAndCalibrationTests.swift
```

## Build and run

### Xcode

1. Open `Package.swift` in Xcode 16 or newer.
2. Select the `PlotMeasurePro` executable scheme.
3. Run on macOS.

### Command line

The local sandbox in this environment requires `--disable-sandbox` for SwiftPM. On a regular local machine you usually do not need that flag.

```bash
cd PlotMeasurePro
SWIFT_MODULECACHE_PATH=/tmp/plotmeasure-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/plotmeasure-module-cache \
swift build --disable-sandbox --scratch-path /tmp/plotmeasure-scratch
swift run --disable-sandbox PlotMeasurePro
```

### Tests

```bash
cd PlotMeasurePro
SWIFT_MODULECACHE_PATH=/tmp/plotmeasure-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/plotmeasure-module-cache \
swift test --disable-sandbox --scratch-path /tmp/plotmeasure-test-scratch
```

## Packaging the macOS app

Run:

```bash
cd PlotMeasurePro
./Scripts/package_app.sh
```

This creates `dist/PlotMeasure Pro.app`.

## How calibration works

The app stores every clicked vertex in native PDF page coordinates, not screen coordinates. That means zooming and panning never change the actual geometry.

### Manual calibration

1. Click two known points on the map or printed scale bar.
2. Enter the real-world distance and unit.
3. The app computes:

```text
metersPerPDFPoint = realWorldMeters / pdfCoordinateDistance
```

Every later segment length becomes:

```text
realWorldMeters = pdfDistance * metersPerPDFPoint
```

Polygon area is then:

```text
realWorldAreaSqM = pdfArea * (metersPerPDFPoint ^ 2)
```

### Ratio calibration (`1:N`)

PDF pages use printer points, where `72 PDF points = 1 inch` on the page. For a true `1:N` map:

```text
metersPerPDFPoint = (0.0254 / 72) * N
```

This method assumes the PDF page geometry is faithful to the printed map scale. For scanned maps, manual calibration is usually more reliable.

### Map-scale calibration (`16 inches = 1 mile`)

The app converts both paper distance and ground distance to meters, derives the ratio, then applies the same `1:N` formula internally.

## MVP and V2

### MVP

- PDF import and page navigation
- manual calibration
- polygon measurement
- perimeter and area in multiple land units
- save/load JSON project

### V2 in this codebase

- OCR scale suggestion scanning
- edge snapping from scanned map edges
- drag editing, vertex insertion, undo/redo
- annotated PDF / CSV / JSON export

## Preview stub

Use `Docs/plotmeasure-pro-preview.svg` as a quick layout stub for documentation or planning.

## Performance optimization recommendations

- Cache page edge maps per page and invalidate only on rotation or document change.
- Add thumbnail/page raster caches for OCR and snap assists rather than re-rendering on every request.
- Move OCR and edge-map generation onto detached background tasks with cancellation.
- For very dense polygons, cache measurement analysis until points change.
- If documents become very large, keep only the active page’s overlay geometry in memory and lazy-load the rest.

## Packaging and signing guidance

For local packaging, the provided script builds a release executable and wraps it in a `.app` bundle. For distribution:

1. Sign the app:

```bash
codesign --force --deep --sign "Developer ID Application: YOUR NAME" "dist/PlotMeasure Pro.app"
```

2. Verify:

```bash
codesign --verify --deep --strict --verbose=2 "dist/PlotMeasure Pro.app"
spctl --assess --type execute --verbose "dist/PlotMeasure Pro.app"
```

3. Notarize for distribution with `notarytool`, then staple the ticket.

## Roadmap

- Assisted boundary tracing from detected edges
- Loupe / magnifier around the pointer
- multi-plot comparison workflows
- GIS export formats such as GeoJSON / shapefile handoff
- optional OpenCV integration for stronger edge and contour extraction
- richer project library and batch reporting
