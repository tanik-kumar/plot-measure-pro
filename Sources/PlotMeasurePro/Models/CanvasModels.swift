import CoreGraphics
import Foundation

struct CanvasOverlayState {
    var pageIndex: Int
    var activeTool: ToolMode
    var snapMode: SnapMode
    var measurements: [MeasurementPolygon]
    var draftMeasurement: MeasurementPolygon?
    var calibrationDraftPoints: [MeasurementPoint]
    var selectedMeasurementID: UUID?
    var selectedPointID: UUID?
    var calibration: CalibrationProfile?
    var showBoundingBox: Bool
    var showTriangulation: Bool
    var preferredLinearUnit: LinearUnitDefinition?
    var recognizedTexts: [RecognizedMapText]
    var selectedRecognizedTextID: UUID?
    var showRecognizedTextOverlay: Bool
}

enum CanvasGestureEvent {
    case canvasClick(point: CGPoint, pageIndex: Int, clickCount: Int)
    case closeDraft
    case selectMeasurement(UUID?)
    case selectPoint(measurementID: UUID, pointID: UUID)
    case deleteSelectedPoint
    case insertVertex(measurementID: UUID, afterSegmentIndex: Int, point: CGPoint)
    case beginVertexDrag(measurementID: UUID, pointID: UUID)
    case dragVertex(measurementID: UUID, pointID: UUID, point: CGPoint)
    case endVertexDrag(measurementID: UUID, pointID: UUID, point: CGPoint)
}
