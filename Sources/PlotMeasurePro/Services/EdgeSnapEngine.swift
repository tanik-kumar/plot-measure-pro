import AppKit
import CoreImage
import Foundation
import PDFKit

final class EdgeSnapEngine {
    struct EdgeMap {
        var width: Int
        var height: Int
        var bounds: CGRect
        var intensity: [UInt8]
    }

    private let context = CIContext(options: nil)
    private var cache: [Int: EdgeMap] = [:]

    func clearCache() {
        cache.removeAll()
    }

    func snap(point: CGPoint, on page: PDFPage, pageIndex: Int) -> CGPoint {
        let map: EdgeMap
        if let cached = cache[pageIndex] {
            map = cached
        } else {
            guard let generated = buildEdgeMap(for: page) else {
                return point
            }
            cache[pageIndex] = generated
            map = generated
        }

        let xScale = Double(map.width - 1) / max(map.bounds.width, 1)
        let yScale = Double(map.height - 1) / max(map.bounds.height, 1)
        let pixelX = Int(((point.x - map.bounds.minX) * xScale).rounded())
        let pixelY = Int(((point.y - map.bounds.minY) * yScale).rounded())

        let searchRadius = 14
        var bestScore = Int.min
        var bestPixel = CGPoint(x: pixelX, y: pixelY)

        for offsetY in -searchRadius...searchRadius {
            for offsetX in -searchRadius...searchRadius {
                let candidateX = pixelX + offsetX
                let candidateY = pixelY + offsetY
                guard candidateX >= 0, candidateX < map.width, candidateY >= 0, candidateY < map.height else {
                    continue
                }
                let intensity = Int(map.intensity[(candidateY * map.width) + candidateX])
                let distancePenalty = (offsetX * offsetX) + (offsetY * offsetY)
                let score = intensity * 4 - distancePenalty
                if score > bestScore {
                    bestScore = score
                    bestPixel = CGPoint(x: candidateX, y: candidateY)
                }
            }
        }

        let snappedX = map.bounds.minX + (bestPixel.x / xScale)
        let snappedY = map.bounds.minY + (bestPixel.y / yScale)
        return CGPoint(x: snappedX, y: snappedY)
    }

    private func buildEdgeMap(for page: PDFPage) -> EdgeMap? {
        let bounds = page.bounds(for: .mediaBox)
        let longestSide = max(bounds.width, bounds.height)
        let scale = 2200.0 / max(longestSide, 1)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)

        guard
            let tiff = image.tiffRepresentation,
            let ciImage = CIImage(data: tiff)
        else {
            return nil
        }

        let grayscale = ciImage.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.25,
            ]
        )
        let edgeImage = grayscale.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 8.0])
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(
            edgeImage,
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .R8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return EdgeMap(width: width, height: height, bounds: bounds, intensity: pixels)
    }
}
