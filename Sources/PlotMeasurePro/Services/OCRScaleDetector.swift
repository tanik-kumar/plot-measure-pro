import AppKit
import Foundation
import PDFKit
import Vision

struct OCRScaleDetector {
    func detectSuggestions(on page: PDFPage) async throws -> [OCRScaleSuggestion] {
        let observations = try recognizedTextObservations(on: page, longestSide: 2400)
        let strings = observations.map(\.text)
        return ScaleParser.parseSuggestions(from: strings)
            .sorted { $0.confidence > $1.confidence }
    }

    func detectMapText(on page: PDFPage) async throws -> [RecognizedMapText] {
        let observations = try recognizedTextObservations(on: page, longestSide: 3600)
        let pageBounds = page.bounds(for: .mediaBox)
        let pageIndex = page.document?.index(for: page) ?? 0

        return observations
            .map { observation in
                RecognizedMapText(
                    text: observation.text,
                    normalizedText: OCRTextNormalizer.normalizedSearchText(observation.text),
                    confidence: observation.confidence,
                    pageIndex: pageIndex,
                    boundingBox: pageRect(for: observation.normalizedBoundingBox, in: pageBounds)
                )
            }
            .sorted(by: readingOrder)
    }

    private struct OCRObservation {
        var text: String
        var confidence: Double
        var normalizedBoundingBox: CGRect
    }

    private let preferredRecognitionLanguages = ["hi-IN", "mr-IN", "ne-NP", "en-US"]
    private let customWords = [
        "खेसरा", "खाता", "थाना", "मौजा", "रकबा", "जमाबंदी",
        "मीटर", "फुट", "फीट", "इंच", "चेन", "जरीब",
    ]

    private func recognizedTextObservations(on page: PDFPage, longestSide: CGFloat) throws -> [OCRObservation] {
        let image = renderedImage(for: page, longestSide: longestSide)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        do {
            return try performRecognition(on: cgImage, recognitionLanguages: preferredRecognitionLanguages)
        } catch {
            return try performRecognition(on: cgImage, recognitionLanguages: [])
        }
    }

    private func performRecognition(on cgImage: CGImage, recognitionLanguages: [String]) throws -> [OCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.customWords = customWords
        request.minimumTextHeight = 0.003
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = recognitionLanguages.isEmpty
        }
        if !recognitionLanguages.isEmpty {
            request.recognitionLanguages = recognitionLanguages
        }

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = OCRTextNormalizer.normalizedSearchText(candidate.string)
            guard !text.isEmpty else { return nil }
            return OCRObservation(
                text: text,
                confidence: Double(candidate.confidence),
                normalizedBoundingBox: observation.boundingBox
            )
        }
    }

    private func pageRect(for normalizedRect: CGRect, in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.minX + normalizedRect.minX * pageBounds.width,
            y: pageBounds.minY + normalizedRect.minY * pageBounds.height,
            width: normalizedRect.width * pageBounds.width,
            height: normalizedRect.height * pageBounds.height
        )
    }

    private func readingOrder(_ lhs: RecognizedMapText, _ rhs: RecognizedMapText) -> Bool {
        let rowTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.7
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > rowTolerance {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func renderedImage(for page: PDFPage, longestSide: CGFloat) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let pageLongestSide = max(bounds.width, bounds.height)
        let scale = longestSide / max(pageLongestSide, 1)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }
}
