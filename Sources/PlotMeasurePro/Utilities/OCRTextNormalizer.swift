import Foundation

enum OCRTextNormalizer {
    private static let devanagariDigitMap: [Character: Character] = [
        "०": "0",
        "१": "1",
        "२": "2",
        "३": "3",
        "४": "4",
        "५": "5",
        "६": "6",
        "७": "7",
        "८": "8",
        "९": "9",
    ]

    private static let scaleUnitReplacements: [(String, String)] = [
        ("मीटर", "meter"),
        ("मि.", "meter"),
        ("मील", "mile"),
        ("फुट", "foot"),
        ("फीट", "foot"),
        ("इंच", "inch"),
        ("चेन", "chain"),
        ("चैन", "chain"),
        ("जरीब", "zarib"),
        ("जरिब", "zarib"),
        ("ज़रीब", "zarib"),
        ("ज़रिब", "zarib"),
    ]

    static func normalizedSearchText(_ raw: String) -> String {
        collapseWhitespace(normalizeDigits(stripInvisibleCharacters(from: raw)))
    }

    static func normalizedScaleText(_ raw: String) -> String {
        var text = normalizedSearchText(raw).lowercased()
        for (source, replacement) in scaleUnitReplacements {
            text = text.replacingOccurrences(of: source, with: replacement)
        }
        return collapseWhitespace(text)
    }

    private static func stripInvisibleCharacters(from raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func normalizeDigits(_ raw: String) -> String {
        String(raw.map { devanagariDigitMap[$0] ?? $0 })
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
