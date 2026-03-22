import Foundation

struct OCRScaleSuggestion: Identifiable, Hashable {
    enum ParsedKind: Hashable {
        case ratio(denominator: Double)
        case mapScale(paperDistance: Double, paperUnitID: String, groundDistance: Double, groundUnitID: String)
    }

    var id = UUID()
    var sourceText: String
    var parsedKind: ParsedKind
    var confidence: Double
}

enum ScaleParser {
    static func parseSuggestions(from textBlocks: [String]) -> [OCRScaleSuggestion] {
        let normalized = textBlocks.map { $0.lowercased() }
        var suggestions: [OCRScaleSuggestion] = []

        let ratioRegex = try? NSRegularExpression(pattern: #"1\s*[:=]\s*([0-9]+(?:[.,][0-9]+)?)"#)
        let mapRegex = try? NSRegularExpression(
            pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*(inch|inches|in|foot|feet|ft|meter|meters|m)\s*[=]\s*([0-9]+(?:[.,][0-9]+)?)\s*(mile|miles|meter|meters|m|foot|feet|ft|chain|chains|zarib|zaribs)"#
        )

        for block in normalized {
            let nsText = block as NSString
            if let match = ratioRegex?.firstMatch(in: block, range: NSRange(location: 0, length: nsText.length)),
               let denominator = value(from: nsText, at: match.range(at: 1)) {
                suggestions.append(
                    OCRScaleSuggestion(
                        sourceText: block,
                        parsedKind: .ratio(denominator: denominator),
                        confidence: 0.95
                    )
                )
            }

            if let match = mapRegex?.firstMatch(in: block, range: NSRange(location: 0, length: nsText.length)),
               let paper = value(from: nsText, at: match.range(at: 1)),
               let ground = value(from: nsText, at: match.range(at: 3)) {
                let paperUnit = normalizeUnit(nsText.substring(with: match.range(at: 2)))
                let groundUnit = normalizeUnit(nsText.substring(with: match.range(at: 4)))
                suggestions.append(
                    OCRScaleSuggestion(
                        sourceText: block,
                        parsedKind: .mapScale(
                            paperDistance: paper,
                            paperUnitID: paperUnit,
                            groundDistance: ground,
                            groundUnitID: groundUnit
                        ),
                        confidence: 0.88
                    )
                )
            }
        }

        return suggestions
    }

    private static func value(from string: NSString, at range: NSRange) -> Double? {
        guard range.location != NSNotFound else { return nil }
        return Double(string.substring(with: range).replacingOccurrences(of: ",", with: ""))
    }

    private static func normalizeUnit(_ raw: String) -> String {
        switch raw {
        case "inch", "inches", "in":
            return "inch"
        case "foot", "feet", "ft":
            return "foot"
        case "meter", "meters", "m":
            return "meter"
        case "mile", "miles":
            return "mile"
        case "chain", "chains":
            return "chain"
        case "zarib", "zaribs":
            return "zarib"
        default:
            return "meter"
        }
    }
}
