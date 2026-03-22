import CoreGraphics
import Foundation

struct RecognizedMapText: Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var normalizedText: String
    var confidence: Double
    var pageIndex: Int
    var boundingBox: CGRect
}
