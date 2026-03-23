import CoreGraphics
import Foundation

struct LinearUnitDefinition: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var metersPerUnit: Double
    var isEditable: Bool = true

    func toMeters(_ value: Double) -> Double {
        value * metersPerUnit
    }

    func fromMeters(_ meters: Double) -> Double {
        meters / metersPerUnit
    }
}

struct AreaUnitDefinition: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var squareMetersPerUnit: Double
    var isEditable: Bool = true

    func fromSquareMeters(_ value: Double) -> Double {
        value / squareMetersPerUnit
    }
}

struct UnitSettings: Codable, Hashable {
    var linearUnits: [LinearUnitDefinition]
    var areaUnits: [AreaUnitDefinition]
    var preferredLinearUnitID: String
    var preferredAreaUnitID: String

    static let defaultProfile = UnitSettings(
        linearUnits: [
            LinearUnitDefinition(id: "meter", name: "Meter", symbol: "m", metersPerUnit: 1.0, isEditable: false),
            LinearUnitDefinition(id: "foot", name: "Foot", symbol: "ft", metersPerUnit: 0.3048, isEditable: false),
            LinearUnitDefinition(id: "inch", name: "Inch", symbol: "in", metersPerUnit: 0.0254, isEditable: false),
            LinearUnitDefinition(id: "chain", name: "Chain", symbol: "chain", metersPerUnit: 20.1168),
            LinearUnitDefinition(id: "zarib", name: "Zarib", symbol: "zarib", metersPerUnit: 20.1168),
            LinearUnitDefinition(id: "mile", name: "Mile", symbol: "mi", metersPerUnit: 1609.344, isEditable: false),
        ],
        areaUnits: [
            AreaUnitDefinition(id: "sqm", name: "Square Meter", symbol: "sq m", squareMetersPerUnit: 1.0, isEditable: false),
            AreaUnitDefinition(id: "sqft", name: "Square Foot", symbol: "sq ft", squareMetersPerUnit: 0.09290304, isEditable: false),
            AreaUnitDefinition(id: "acre", name: "Acre", symbol: "acre", squareMetersPerUnit: 4046.8564224, isEditable: false),
            AreaUnitDefinition(id: "hectare", name: "Hectare", symbol: "ha", squareMetersPerUnit: 10_000.0, isEditable: false),
            AreaUnitDefinition(id: "decimal", name: "Decimal", symbol: "decimal", squareMetersPerUnit: 40.468564224),
            AreaUnitDefinition(id: "bigha", name: "Bigha", symbol: "bigha", squareMetersPerUnit: 2722.84667776),
            AreaUnitDefinition(id: "kattha", name: "Kattha", symbol: "kattha", squareMetersPerUnit: 136.142333888),
            AreaUnitDefinition(id: "dhur", name: "Dhur", symbol: "dhur", squareMetersPerUnit: 6.8071166944),
        ],
        preferredLinearUnitID: "meter",
        preferredAreaUnitID: "sqm"
    )

    func linearUnit(id: String) -> LinearUnitDefinition? {
        linearUnits.first { $0.id == id }
    }

    func areaUnit(id: String) -> AreaUnitDefinition? {
        areaUnits.first { $0.id == id }
    }
}

enum MeasurementKind: String, Codable, CaseIterable, Identifiable {
    case distance
    case path
    case polygon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance:
            return "Distance"
        case .path:
            return "Path"
        case .polygon:
            return "Polygon"
        }
    }
}

enum ToolMode: String, Codable, CaseIterable, Identifiable {
    case pan
    case text
    case calibration
    case distance
    case path
    case polygon
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan:
            return "Pan"
        case .text:
            return "Text"
        case .calibration:
            return "Calibrate"
        case .distance:
            return "Distance"
        case .path:
            return "Path"
        case .polygon:
            return "Area"
        case .edit:
            return "Edit"
        }
    }

    var measurementKind: MeasurementKind? {
        switch self {
        case .distance:
            return .distance
        case .path:
            return .path
        case .polygon:
            return .polygon
        case .pan, .text, .calibration, .edit:
            return nil
        }
    }
}

enum SnapMode: String, Codable, CaseIterable, Identifiable {
    case free
    case edge

    var id: String { rawValue }
}

enum CalibrationMethod: String, Codable, CaseIterable, Identifiable {
    case manualDistance
    case ratioScale
    case imperialScale
    case scaleBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualDistance:
            return "Manual"
        case .ratioScale:
            return "1:N Ratio"
        case .imperialScale:
            return "Map Scale"
        case .scaleBar:
            return "Scale Bar"
        }
    }
}

struct MeasurementPoint: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var x: Double
    var y: Double
    var note: String = ""

    init(id: UUID = UUID(), x: Double, y: Double, note: String = "") {
        self.id = id
        self.x = x
        self.y = y
        self.note = note
    }

    init(id: UUID = UUID(), point: CGPoint, note: String = "") {
        self.init(id: id, x: point.x, y: point.y, note: note)
    }

    var cgPoint: CGPoint {
        get { CGPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }
}

struct MeasurementPolygon: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: MeasurementKind
    var pageIndex: Int
    var points: [MeasurementPoint]
    var isClosed: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: MeasurementKind,
        pageIndex: Int,
        points: [MeasurementPoint] = [],
        isClosed: Bool = false,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pageIndex = pageIndex
        self.points = points
        self.isClosed = isClosed
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CalibrationProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var method: CalibrationMethod
    var metersPerPDFPoint: Double
    var label: String
    var pageIndex: Int
    var createdAt: Date = .now
    var referenceDistance: Double?
    var referenceUnitID: String?
    var referenceStartPoint: MeasurementPoint?
    var referenceEndPoint: MeasurementPoint?
    var paperDistance: Double?
    var paperUnitID: String?
    var groundDistance: Double?
    var groundUnitID: String?
    var ratioDenominator: Double?
}

struct PDFPageMeasurement: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pageIndex: Int
    var rotationDegrees: Int = 0
    var calibration: CalibrationProfile?
    var measurements: [MeasurementPolygon] = []
}

struct PDFDocumentProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pdfFilePath: String
    var pdfBookmarkData: Data?
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var unitSettings: UnitSettings = .defaultProfile
    var pages: [PDFPageMeasurement]

    func page(at index: Int) -> PDFPageMeasurement? {
        pages.first { $0.pageIndex == index }
    }
}

struct SegmentMeasurement: Identifiable, Hashable {
    var id = UUID()
    var startLabel: String
    var endLabel: String
    var lengthMeters: Double
    var angleDegrees: Double?
}

struct MeasurementAnalysis {
    var segmentMeasurements: [SegmentMeasurement]
    var perimeterMeters: Double
    var areaSquareMeters: Double
    var centroid: CGPoint?
    var boundingBox: CGRect?
    var internalAngles: [Double]
    var isSelfIntersecting: Bool
    var selfIntersectionPairs: [(Int, Int)]
    var triangles: [[CGPoint]]
}

struct MeasurementExportRow: Codable, Hashable {
    var measurementName: String
    var pageIndex: Int
    var kind: String
    var pointCount: Int
    var sideLengthsMeters: [Double]
    var perimeterMeters: Double
    var areaSquareMeters: Double
    var areasByUnit: [String: Double]
    var calibrationMethod: String
    var timestamp: Date
}

struct ExportReport: Codable, Hashable {
    var projectName: String
    var sourcePDFPath: String
    var generatedAt: Date
    var rows: [MeasurementExportRow]
}
