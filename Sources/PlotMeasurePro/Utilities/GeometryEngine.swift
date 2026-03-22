import CoreGraphics
import Foundation

enum GeometryEngine {
    static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }

    static func polylineLength(_ points: [CGPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + distance(pair.0, pair.1)
        }
    }

    static func polygonPerimeter(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return polylineLength(points) }
        return polylineLength(points) + distance(points.last!, points.first!)
    }

    static func signedArea(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        var total = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            total += (current.x * next.y) - (next.x * current.y)
        }
        return total / 2.0
    }

    static func polygonArea(_ points: [CGPoint]) -> Double {
        abs(signedArea(points))
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard points.count > 2 else {
            guard !points.isEmpty else { return nil }
            let avgX = points.map(\.x).reduce(0, +) / Double(points.count)
            let avgY = points.map(\.y).reduce(0, +) / Double(points.count)
            return CGPoint(x: avgX, y: avgY)
        }

        let area = signedArea(points)
        guard abs(area) > 1e-9 else {
            let avgX = points.map(\.x).reduce(0, +) / Double(points.count)
            let avgY = points.map(\.y).reduce(0, +) / Double(points.count)
            return CGPoint(x: avgX, y: avgY)
        }

        var x = 0.0
        var y = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let factor = (current.x * next.y) - (next.x * current.y)
            x += (current.x + next.x) * factor
            y += (current.y + next.y) * factor
        }

        let divisor = 6.0 * area
        return CGPoint(x: x / divisor, y: y / divisor)
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func internalAngles(_ points: [CGPoint]) -> [Double] {
        guard points.count > 2 else { return [] }
        let orientation = signedArea(points) >= 0 ? 1.0 : -1.0
        return points.indices.map { index in
            let prev = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let v1 = CGPoint(x: prev.x - current.x, y: prev.y - current.y)
            let v2 = CGPoint(x: next.x - current.x, y: next.y - current.y)
            let dot = (v1.x * v2.x) + (v1.y * v2.y)
            let len = max(distance(prev, current) * distance(next, current), 1e-9)
            let clamped = max(-1.0, min(1.0, dot / len))
            let unsigned = acos(clamped) * 180.0 / .pi
            let cross = ((v1.x * v2.y) - (v1.y * v2.x)) * orientation
            return cross >= 0 ? 360.0 - unsigned : unsigned
        }
    }

    static func selfIntersections(_ points: [CGPoint], closed: Bool) -> [(Int, Int)] {
        let count = points.count
        guard count >= 4 else { return [] }

        let segmentCount = closed ? count : count - 1
        var hits: [(Int, Int)] = []
        for firstIndex in 0..<segmentCount {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % count]
            for secondIndex in (firstIndex + 1)..<segmentCount {
                if areAdjacent(firstIndex, secondIndex, segmentCount: segmentCount, closed: closed) {
                    continue
                }
                let secondStart = points[secondIndex]
                let secondEnd = points[(secondIndex + 1) % count]
                if segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) {
                    hits.append((firstIndex, secondIndex))
                }
            }
        }
        return hits
    }

    static func triangulate(_ points: [CGPoint]) -> [[CGPoint]] {
        guard points.count >= 3, selfIntersections(points, closed: true).isEmpty else {
            return []
        }

        var vertices = Array(points.indices)
        let isClockwise = signedArea(points) < 0
        var triangles: [[CGPoint]] = []

        func isEar(at offset: Int) -> Bool {
            let prevIndex = vertices[(offset - 1 + vertices.count) % vertices.count]
            let currentIndex = vertices[offset]
            let nextIndex = vertices[(offset + 1) % vertices.count]

            let a = points[prevIndex]
            let b = points[currentIndex]
            let c = points[nextIndex]

            if !isConvex(a, b, c, clockwise: isClockwise) {
                return false
            }

            for testIndex in vertices where testIndex != prevIndex && testIndex != currentIndex && testIndex != nextIndex {
                if pointInTriangle(points[testIndex], a, b, c) {
                    return false
                }
            }
            return true
        }

        while vertices.count > 3 {
            var clippedEar = false
            for offset in vertices.indices {
                guard isEar(at: offset) else { continue }
                let prevIndex = vertices[(offset - 1 + vertices.count) % vertices.count]
                let currentIndex = vertices[offset]
                let nextIndex = vertices[(offset + 1) % vertices.count]
                triangles.append([points[prevIndex], points[currentIndex], points[nextIndex]])
                vertices.remove(at: offset)
                clippedEar = true
                break
            }
            if !clippedEar {
                return []
            }
        }

        if vertices.count == 3 {
            triangles.append(vertices.map { points[$0] })
        }
        return triangles
    }

    static func pointDistanceToSegment(_ point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint) -> Double {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return distance(point, segmentStart)
        }
        let t = max(0.0, min(1.0, ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / lengthSquared))
        let projection = CGPoint(x: segmentStart.x + t * dx, y: segmentStart.y + t * dy)
        return distance(point, projection)
    }

    private static func areAdjacent(_ lhs: Int, _ rhs: Int, segmentCount: Int, closed: Bool) -> Bool {
        if abs(lhs - rhs) == 1 {
            return true
        }
        return closed && ((lhs == 0 && rhs == segmentCount - 1) || (rhs == 0 && lhs == segmentCount - 1))
    }

    private static func segmentsIntersect(_ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint) -> Bool {
        let d1 = direction(b1, b2, a1)
        let d2 = direction(b1, b2, a2)
        let d3 = direction(a1, a2, b1)
        let d4 = direction(a1, a2, b2)

        if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
            return true
        }

        if d1 == 0 && onSegment(b1, b2, a1) { return true }
        if d2 == 0 && onSegment(b1, b2, a2) { return true }
        if d3 == 0 && onSegment(a1, a2, b1) { return true }
        if d4 == 0 && onSegment(a1, a2, b2) { return true }
        return false
    }

    private static func direction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        ((c.x - a.x) * (b.y - a.y)) - ((b.x - a.x) * (c.y - a.y))
    }

    private static func onSegment(_ a: CGPoint, _ b: CGPoint, _ point: CGPoint) -> Bool {
        point.x >= min(a.x, b.x) - 1e-9 &&
            point.x <= max(a.x, b.x) + 1e-9 &&
            point.y >= min(a.y, b.y) - 1e-9 &&
            point.y <= max(a.y, b.y) + 1e-9
    }

    private static func isConvex(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, clockwise: Bool) -> Bool {
        let cross = ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x))
        return clockwise ? cross < 0 : cross > 0
    }

    private static func pointInTriangle(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let area = abs(direction(a, b, c))
        let a1 = abs(direction(point, a, b))
        let a2 = abs(direction(point, b, c))
        let a3 = abs(direction(point, c, a))
        return abs(area - (a1 + a2 + a3)) < 1e-6
    }
}
