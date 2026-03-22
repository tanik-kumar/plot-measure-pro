import AppKit
import Foundation
import PDFKit
import Vision

struct OCRScaleDetector {
    func detectSuggestions(on page: PDFPage) async throws -> [OCRScaleSuggestion] {
        let image = renderedImage(for: page)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        try handler.perform([request])
        let strings = request.results?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
        return ScaleParser.parseSuggestions(from: strings)
            .sorted { $0.confidence > $1.confidence }
    }

    private func renderedImage(for page: PDFPage) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let longestSide = max(bounds.width, bounds.height)
        let scale = 2400.0 / max(longestSide, 1)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }
}
