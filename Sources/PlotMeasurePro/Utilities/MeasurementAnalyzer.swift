import CoreGraphics
import Foundation

enum MeasurementAnalyzer {
    static func analyze(
        measurement: MeasurementPolygon,
        calibration: CalibrationProfile?
    ) -> MeasurementAnalysis {
        let points = measurement.points.map(\.cgPoint)
        let metersPerPoint = calibration?.metersPerPDFPoint ?? 0

        var segments: [SegmentMeasurement] = []
        let isClosed = measurement.kind == .polygon && measurement.isClosed
        let segmentCount = isClosed ? points.count : max(points.count - 1, 0)

        for index in 0..<segmentCount {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let lengthPDF = GeometryEngine.distance(start, end)
            let meters = lengthPDF * metersPerPoint
            let angle = isClosed ? GeometryEngine.internalAngles(points)[index] : nil
            segments.append(
                SegmentMeasurement(
                    startLabel: "P\(index + 1)",
                    endLabel: "P\(((index + 1) % points.count) + 1)",
                    lengthMeters: meters,
                    angleDegrees: angle
                )
            )
        }

        let perimeterPDF: Double
        let areaPDF: Double
        if measurement.kind == .polygon, measurement.isClosed {
            perimeterPDF = GeometryEngine.polygonPerimeter(points)
            areaPDF = GeometryEngine.polygonArea(points)
        } else {
            perimeterPDF = GeometryEngine.polylineLength(points)
            areaPDF = 0
        }

        let intersections = GeometryEngine.selfIntersections(points, closed: measurement.kind == .polygon && measurement.isClosed)
        let triangles = measurement.kind == .polygon && measurement.isClosed ? GeometryEngine.triangulate(points) : []
        return MeasurementAnalysis(
            segmentMeasurements: segments,
            perimeterMeters: perimeterPDF * metersPerPoint,
            areaSquareMeters: areaPDF * pow(metersPerPoint, 2),
            centroid: measurement.kind == .polygon && measurement.isClosed ? GeometryEngine.centroid(points) : nil,
            boundingBox: GeometryEngine.boundingBox(points),
            internalAngles: measurement.kind == .polygon && measurement.isClosed ? GeometryEngine.internalAngles(points) : [],
            isSelfIntersecting: !intersections.isEmpty,
            selfIntersectionPairs: intersections,
            triangles: triangles
        )
    }
}
