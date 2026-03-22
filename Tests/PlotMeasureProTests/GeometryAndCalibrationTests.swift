import CoreGraphics
import XCTest
@testable import PlotMeasurePro

final class GeometryAndCalibrationTests: XCTestCase {
    func testSquareAreaPerimeterAndCentroid() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10),
        ]

        XCTAssertEqual(GeometryEngine.polygonArea(points), 100, accuracy: 0.0001)
        XCTAssertEqual(GeometryEngine.polygonPerimeter(points), 40, accuracy: 0.0001)
        XCTAssertEqual(GeometryEngine.centroid(points)?.x, 5, accuracy: 0.0001)
        XCTAssertEqual(GeometryEngine.centroid(points)?.y, 5, accuracy: 0.0001)
        XCTAssertTrue(GeometryEngine.selfIntersections(points, closed: true).isEmpty)
    }

    func testRectangleAnalysisUsesCalibration() {
        let measurement = MeasurementPolygon(
            name: "Rect",
            kind: .polygon,
            pageIndex: 0,
            points: [
                MeasurementPoint(x: 0, y: 0),
                MeasurementPoint(x: 4, y: 0),
                MeasurementPoint(x: 4, y: 2),
                MeasurementPoint(x: 0, y: 2),
            ],
            isClosed: true
        )
        let calibration = CalibrationProfile(
            method: .manualDistance,
            metersPerPDFPoint: 2.0,
            label: "Manual",
            pageIndex: 0
        )

        let analysis = MeasurementAnalyzer.analyze(measurement: measurement, calibration: calibration)
        XCTAssertEqual(analysis.perimeterMeters, 24, accuracy: 0.0001)
        XCTAssertEqual(analysis.areaSquareMeters, 32, accuracy: 0.0001)
    }

    func testTriangleArea() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 8, y: 0),
            CGPoint(x: 4, y: 3),
        ]

        XCTAssertEqual(GeometryEngine.polygonArea(points), 12, accuracy: 0.0001)
        XCTAssertTrue(GeometryEngine.selfIntersections(points, closed: true).isEmpty)
    }

    func testConcavePolygonAreaAndTriangulation() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 8, y: 0),
            CGPoint(x: 8, y: 8),
            CGPoint(x: 4, y: 4),
            CGPoint(x: 0, y: 8),
        ]

        XCTAssertEqual(GeometryEngine.polygonArea(points), 48, accuracy: 0.0001)
        XCTAssertFalse(GeometryEngine.triangulate(points).isEmpty)
    }

    func testSelfIntersectingPolygonIsDetected() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10),
            CGPoint(x: 10, y: 0),
        ]

        XCTAssertFalse(GeometryEngine.selfIntersections(points, closed: true).isEmpty)
    }

    func testManualCalibration() throws {
        let unit = UnitSettings.defaultProfile.linearUnit(id: "meter")!
        let metersPerPoint = try CalibrationEngine.metersPerPDFPointForManualCalibration(
            pdfPointDistance: 50,
            realWorldDistance: 100,
            unit: unit
        )
        XCTAssertEqual(metersPerPoint, 2, accuracy: 0.0001)
    }

    func testRatioCalibration() throws {
        let metersPerPoint = try CalibrationEngine.metersPerPDFPointForRatioScale(denominator: 4000)
        XCTAssertEqual(metersPerPoint, (0.0254 / 72.0) * 4000, accuracy: 1e-9)
    }

    func testImperialCalibration() throws {
        let settings = UnitSettings.defaultProfile
        let inches = settings.linearUnit(id: "inch")!
        let miles = settings.linearUnit(id: "mile")!
        let metersPerPoint = try CalibrationEngine.metersPerPDFPointForMapScale(
            paperDistance: 16,
            paperUnit: inches,
            groundDistance: 1,
            groundUnit: miles
        )
        XCTAssertGreaterThan(metersPerPoint, 0)
    }

    func testDevanagariDigitsNormalizeForOCRText() {
        XCTAssertEqual(
            OCRTextNormalizer.normalizedSearchText("खेसरा १२३४"),
            "खेसरा 1234"
        )
    }

    func testScaleParserReadsDevanagariScaleText() {
        let suggestions = ScaleParser.parseSuggestions(from: [
            "१ : ४०००",
            "१६ इंच = १ मील",
        ])

        XCTAssertTrue(
            suggestions.contains {
                if case .ratio(let denominator) = $0.parsedKind {
                    return denominator == 4000
                }
                return false
            }
        )

        XCTAssertTrue(
            suggestions.contains {
                if case .mapScale(let paperDistance, let paperUnitID, let groundDistance, let groundUnitID) = $0.parsedKind {
                    return paperDistance == 16 &&
                        paperUnitID == "inch" &&
                        groundDistance == 1 &&
                        groundUnitID == "mile"
                }
                return false
            }
        )
    }
}
