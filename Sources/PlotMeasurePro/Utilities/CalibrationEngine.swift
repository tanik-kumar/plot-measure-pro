import Foundation

enum CalibrationError: LocalizedError {
    case invalidDistance
    case invalidRatio
    case missingUnit

    var errorDescription: String? {
        switch self {
        case .invalidDistance:
            return "The entered calibration distance must be greater than zero."
        case .invalidRatio:
            return "The scale ratio must be greater than zero."
        case .missingUnit:
            return "A required unit definition could not be found."
        }
    }
}

enum CalibrationEngine {
    private static let metersPerPDFPointAtScale1 = 0.0254 / 72.0

    static func metersPerPDFPointForManualCalibration(
        pdfPointDistance: Double,
        realWorldDistance: Double,
        unit: LinearUnitDefinition
    ) throws -> Double {
        guard pdfPointDistance > 0, realWorldDistance > 0 else {
            throw CalibrationError.invalidDistance
        }
        return unit.toMeters(realWorldDistance) / pdfPointDistance
    }

    static func metersPerPDFPointForRatioScale(denominator: Double) throws -> Double {
        guard denominator > 0 else {
            throw CalibrationError.invalidRatio
        }
        return metersPerPDFPointAtScale1 * denominator
    }

    static func metersPerPDFPointForMapScale(
        paperDistance: Double,
        paperUnit: LinearUnitDefinition,
        groundDistance: Double,
        groundUnit: LinearUnitDefinition
    ) throws -> Double {
        guard paperDistance > 0, groundDistance > 0 else {
            throw CalibrationError.invalidDistance
        }
        let paperMeters = paperUnit.toMeters(paperDistance)
        let groundMeters = groundUnit.toMeters(groundDistance)
        let ratio = groundMeters / paperMeters
        return try metersPerPDFPointForRatioScale(denominator: ratio)
    }
}
