import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct ExportService {
    private enum OverlayPalette {
        static let savedDistance = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.00, alpha: 1.0)
        static let savedPath = NSColor(srgbRed: 0.00, green: 0.78, blue: 1.00, alpha: 1.0)
        static let savedPolygon = NSColor(srgbRed: 0.10, green: 0.82, blue: 0.35, alpha: 1.0)
        static let invalidPolygon = NSColor(srgbRed: 1.00, green: 0.12, blue: 0.12, alpha: 1.0)
        static let centroid = NSColor(srgbRed: 0.00, green: 0.88, blue: 1.00, alpha: 1.0)
        static let calibration = NSColor(srgbRed: 0.02, green: 0.70, blue: 0.95, alpha: 1.0)
    }

    private enum SummaryPalette {
        static let panelFill = NSColor(calibratedWhite: 1.0, alpha: 0.92)
        static let panelBorder = NSColor.black.withAlphaComponent(0.12)
        static let title = NSColor(calibratedWhite: 0.10, alpha: 1.0)
        static let body = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        static let secondary = NSColor(calibratedWhite: 0.28, alpha: 1.0)
        static let warning = NSColor.systemRed
        static let divider = NSColor.black.withAlphaComponent(0.08)
        static let labelFill = NSColor.white.withAlphaComponent(0.90)
        static let labelText = NSColor(calibratedWhite: 0.10, alpha: 1.0)
    }

    private struct PageExportStyle {
        let scale: CGFloat
        let margin: CGFloat
        let panelWidth: CGFloat
        let panelPadding: CGFloat
        let sectionSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let outerStroke: CGFloat
        let middleStroke: CGFloat
        let polygonStroke: CGFloat
        let polylineStroke: CGFloat
        let fillAlpha: CGFloat
        let pointDiameter: CGFloat
        let centroidDiameter: CGFloat
        let mapLabelFontSize: CGFloat
        let mapCalloutFontSize: CGFloat
        let panelTitleFontSize: CGFloat
        let panelBodyFontSize: CGFloat
        let panelCaptionFontSize: CGFloat
        let mapLabelPaddingX: CGFloat
        let mapLabelPaddingY: CGFloat
    }

    private struct SummaryParagraph {
        let text: String
        let font: NSFont
        let color: NSColor
        let spacingAfter: CGFloat
    }

    private struct ReportPageStyle {
        let pageBounds: CGRect
        let contentRect: CGRect
        let titleFont: NSFont
        let subtitleFont: NSFont
        let bodyFont: NSFont
        let captionFont: NSFont
    }

    private struct ExportUnitSet {
        let meter: LinearUnitDefinition?
        let foot: LinearUnitDefinition?
        let squareMeter: AreaUnitDefinition?
        let squareFoot: AreaUnitDefinition?
        let decimal: AreaUnitDefinition?
    }

    func buildReport(project: PDFDocumentProject) -> ExportReport {
        let rows = project.pages.flatMap { page in
            page.measurements.map { measurement in
                let analysis = MeasurementAnalyzer.analyze(measurement: measurement, calibration: page.calibration)
                let areaMap = Dictionary(uniqueKeysWithValues: project.unitSettings.areaUnits.map { unit in
                    (unit.id, unit.fromSquareMeters(analysis.areaSquareMeters))
                })
                return MeasurementExportRow(
                    measurementName: measurement.name,
                    pageIndex: page.pageIndex,
                    kind: measurement.kind.rawValue,
                    pointCount: measurement.points.count,
                    sideLengthsMeters: analysis.segmentMeasurements.map(\.lengthMeters),
                    perimeterMeters: analysis.perimeterMeters,
                    areaSquareMeters: analysis.areaSquareMeters,
                    areasByUnit: areaMap,
                    calibrationMethod: page.calibration?.method.rawValue ?? "uncalibrated",
                    timestamp: .now
                )
            }
        }

        return ExportReport(
            projectName: project.name,
            sourcePDFPath: project.pdfFilePath,
            generatedAt: .now,
            rows: rows
        )
    }

    func exportJSON(report: ExportReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    func exportCSV(report: ExportReport, to url: URL) throws {
        var lines = [
            "plot_name,page_number,kind,point_count,perimeter_m,area_sq_m,side_lengths_m,calibration_method,timestamp",
        ]

        let formatter = ISO8601DateFormatter()
        for row in report.rows {
            let sideLengths = row.sideLengthsMeters.map { String(format: "%.6f", $0) }.joined(separator: "|")
            let escapedName = row.measurementName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append(
                "\"\(escapedName)\",\(row.pageIndex + 1),\(row.kind),\(row.pointCount),\(row.perimeterMeters),\(row.areaSquareMeters),\"\(sideLengths)\",\(row.calibrationMethod),\(formatter.string(from: row.timestamp))"
            )
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAnnotatedPDF(project: PDFDocumentProject, originalDocument: PDFDocument, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var defaultMediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let preferredLinearUnit = project.unitSettings.linearUnit(id: project.unitSettings.preferredLinearUnitID)
        let preferredAreaUnit = project.unitSettings.areaUnit(id: project.unitSettings.preferredAreaUnitID)
        let exportUnits = ExportUnitSet(
            meter: project.unitSettings.linearUnit(id: "meter"),
            foot: project.unitSettings.linearUnit(id: "foot"),
            squareMeter: project.unitSettings.areaUnit(id: "sqm"),
            squareFoot: project.unitSettings.areaUnit(id: "sqft"),
            decimal: project.unitSettings.areaUnit(id: "decimal")
        )

        for pageIndex in 0..<originalDocument.pageCount {
            guard let page = originalDocument.page(at: pageIndex) else { continue }
            let sourceBounds = page.bounds(for: .mediaBox)
            let pageBounds = CGRect(x: 0, y: 0, width: sourceBounds.width, height: sourceBounds.height)
            let style = pageStyle(for: pageBounds)
            var mediaBox = pageBounds
            let mediaBoxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size) as CFData
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary)

            context.saveGState()
            if let pageRef = page.pageRef {
                let transform = pageRef.getDrawingTransform(.mediaBox, rect: pageBounds, rotate: 0, preserveAspectRatio: true)
                context.concatenate(transform)
                context.drawPDFPage(pageRef)
            } else {
                context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
                page.draw(with: .mediaBox, to: context)
            }
            context.restoreGState()

            if let pageMeasurement = project.page(at: pageIndex) {
                drawPageMeasurements(
                    pageMeasurement,
                    exportUnits: exportUnits,
                    preferredLinearUnit: preferredLinearUnit,
                    preferredAreaUnit: preferredAreaUnit,
                    style: style,
                    in: context
                )
            }

            BrandRenderer.drawWatermark(in: context, pageBounds: pageBounds)
            context.endPDFPage()
        }

        for pageMeasurement in project.pages where !pageMeasurement.measurements.isEmpty {
            drawSummaryReportPages(
                pageMeasurement,
                projectName: project.name,
                unitSettings: project.unitSettings,
                exportUnits: exportUnits,
                preferredLinearUnit: preferredLinearUnit,
                preferredAreaUnit: preferredAreaUnit,
                in: context
            )
        }

        context.closePDF()
    }

    private func pageStyle(for pageBounds: CGRect) -> PageExportStyle {
        let shortEdge = max(min(pageBounds.width, pageBounds.height), 480)
        let scale = min(max(shortEdge / 900, 0.78), 1.18)
        let panelWidth = min(max(pageBounds.width * 0.31, 230 * scale), 330 * scale)

        return PageExportStyle(
            scale: scale,
            margin: 18 * scale,
            panelWidth: panelWidth,
            panelPadding: 10 * scale,
            sectionSpacing: 8 * scale,
            paragraphSpacing: 4 * scale,
            outerStroke: 0.80 * scale,
            middleStroke: 0.28 * scale,
            polygonStroke: 0.48 * scale,
            polylineStroke: 0.44 * scale,
            fillAlpha: 0.07,
            pointDiameter: 5.6 * scale,
            centroidDiameter: 4.0 * scale,
            mapLabelFontSize: 6.4 * scale,
            mapCalloutFontSize: 7.1 * scale,
            panelTitleFontSize: 11.4 * scale,
            panelBodyFontSize: 7.8 * scale,
            panelCaptionFontSize: 6.9 * scale,
            mapLabelPaddingX: 3.0 * scale,
            mapLabelPaddingY: 1.6 * scale
        )
    }

    private func drawPageMeasurements(
        _ pageMeasurement: PDFPageMeasurement,
        exportUnits: ExportUnitSet,
        preferredLinearUnit: LinearUnitDefinition?,
        preferredAreaUnit: AreaUnitDefinition?,
        style: PageExportStyle,
        in context: CGContext
    ) {
        drawCalibrationReference(pageMeasurement.calibration, style: style, in: context)
        for measurement in pageMeasurement.measurements {
            drawMeasurement(
                measurement,
                calibration: pageMeasurement.calibration,
                exportUnits: exportUnits,
                preferredLinearUnit: preferredLinearUnit,
                preferredAreaUnit: preferredAreaUnit,
                style: style,
                in: context
            )
        }
    }

    private func drawMeasurement(
        _ measurement: MeasurementPolygon,
        calibration: CalibrationProfile?,
        exportUnits: ExportUnitSet,
        preferredLinearUnit: LinearUnitDefinition?,
        preferredAreaUnit: AreaUnitDefinition?,
        style: PageExportStyle,
        in context: CGContext
    ) {
        let points = measurement.points.map(\.cgPoint)
        guard !points.isEmpty else { return }

        let analysis = MeasurementAnalyzer.analyze(measurement: measurement, calibration: calibration)
        let color = overlayColor(for: measurement, isInvalid: analysis.isSelfIntersecting)
        let strokeWidth = measurement.kind == .polygon ? style.polygonStroke : style.polylineStroke

        if measurement.kind == .polygon, measurement.isClosed, points.count >= 3 {
            drawPolygonFill(points: points, color: color, style: style, in: context)
        }

        if points.count > 1 {
            drawStroke(
                points: points,
                closePath: measurement.kind == .polygon && measurement.isClosed,
                color: color,
                lineWidth: strokeWidth,
                style: style,
                in: context
            )
        }

        drawVertices(points: points, color: color, style: style, in: context)
        drawPointLabels(points: points, color: color, style: style, in: context)

        if measurement.kind == .polygon, measurement.isClosed, let centroid = analysis.centroid {
            drawCentroid(at: centroid, style: style, in: context)
        }

        drawMeasurementCallout(
            measurement: measurement,
            analysis: analysis,
            exportUnits: exportUnits,
            preferredLinearUnit: preferredLinearUnit,
            preferredAreaUnit: preferredAreaUnit,
            color: color,
            style: style,
            in: context
        )
    }

    private func drawPolygonFill(points: [CGPoint], color: NSColor, style: PageExportStyle, in context: CGContext) {
        guard points.count >= 3 else { return }
        context.saveGState()
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
        context.setFillColor(color.withAlphaComponent(style.fillAlpha).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private func drawStroke(
        points: [CGPoint],
        closePath: Bool,
        color: NSColor,
        lineWidth: CGFloat,
        style: PageExportStyle,
        in context: CGContext
    ) {
        guard points.count > 1 else { return }
        stroke(
            points: points,
            closePath: closePath,
            color: NSColor.black.withAlphaComponent(0.50),
            lineWidth: lineWidth + style.outerStroke,
            in: context
        )
        stroke(
            points: points,
            closePath: closePath,
            color: NSColor.white.withAlphaComponent(0.88),
            lineWidth: lineWidth + style.middleStroke,
            in: context
        )
        stroke(points: points, closePath: closePath, color: color, lineWidth: lineWidth, in: context)
    }

    private func stroke(
        points: [CGPoint],
        closePath: Bool,
        color: NSColor,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        context.beginPath()
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        if closePath {
            context.closePath()
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawVertices(points: [CGPoint], color: NSColor, style: PageExportStyle, in context: CGContext) {
        for point in points {
            let outerRect = CGRect(
                x: point.x - style.pointDiameter / 2,
                y: point.y - style.pointDiameter / 2,
                width: style.pointDiameter,
                height: style.pointDiameter
            )
            let middleRect = outerRect.insetBy(dx: style.scale * 1.0, dy: style.scale * 1.0)
            let innerRect = outerRect.insetBy(dx: style.scale * 2.2, dy: style.scale * 2.2)

            context.saveGState()
            context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
            context.fillEllipse(in: outerRect)
            context.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
            context.fillEllipse(in: middleRect)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: innerRect)
            context.restoreGState()
        }
    }

    private func drawCentroid(at point: CGPoint, style: PageExportStyle, in context: CGContext) {
        let rect = CGRect(
            x: point.x - style.centroidDiameter / 2,
            y: point.y - style.centroidDiameter / 2,
            width: style.centroidDiameter,
            height: style.centroidDiameter
        )
        context.saveGState()
        context.setFillColor(OverlayPalette.centroid.cgColor)
        context.fillEllipse(in: rect)
        context.restoreGState()
    }

    private func drawPointLabels(points: [CGPoint], color: NSColor, style: PageExportStyle, in context: CGContext) {
        guard points.count <= 30 else { return }
        let font = NSFont.monospacedSystemFont(ofSize: max(5.8, style.mapLabelFontSize), weight: .semibold)
        for (index, point) in points.enumerated() {
            drawMapLabel(
                "P\(index + 1)",
                at: CGPoint(
                    x: point.x + style.pointDiameter * 0.45,
                    y: point.y + style.pointDiameter * 0.35
                ),
                font: font,
                tint: color,
                style: style,
                in: context
            )
        }
    }

    private func drawCalibrationReference(
        _ calibration: CalibrationProfile?,
        style: PageExportStyle,
        in context: CGContext
    ) {
        guard let start = calibration?.referenceStartPoint?.cgPoint,
              let end = calibration?.referenceEndPoint?.cgPoint else { return }

        context.saveGState()
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(max(0.8, 1.0 * style.scale))
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        context.setStrokeColor(OverlayPalette.calibration.cgColor)
        context.setLineWidth(max(0.45, 0.65 * style.scale))
        context.setLineDash(phase: 0, lengths: [4 * style.scale, 3 * style.scale])
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        context.restoreGState()

        drawCalibrationMarker(at: start, style: style, in: context)
        drawCalibrationMarker(at: end, style: style, in: context)

        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        drawMapLabel(
            "Cal",
            at: CGPoint(x: midpoint.x + 4 * style.scale, y: midpoint.y + 4 * style.scale),
            font: NSFont.systemFont(ofSize: max(5.8, style.mapLabelFontSize), weight: .bold),
            tint: OverlayPalette.calibration,
            style: style,
            in: context
        )
    }

    private func drawCalibrationMarker(at point: CGPoint, style: PageExportStyle, in context: CGContext) {
        let diameter = max(4.6, style.pointDiameter * 0.9)
        let outerRect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        let innerRect = outerRect.insetBy(dx: max(0.8, style.scale * 0.8), dy: max(0.8, style.scale * 0.8))

        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
        context.fillEllipse(in: outerRect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(max(0.35, 0.45 * style.scale))
        context.strokeEllipse(in: outerRect)
        context.setFillColor(OverlayPalette.calibration.cgColor)
        context.fillEllipse(in: innerRect)
        context.restoreGState()
    }

    private func drawMeasurementCallout(
        measurement: MeasurementPolygon,
        analysis: MeasurementAnalysis,
        exportUnits: ExportUnitSet,
        preferredLinearUnit: LinearUnitDefinition?,
        preferredAreaUnit: AreaUnitDefinition?,
        color: NSColor,
        style: PageExportStyle,
        in context: CGContext
    ) {
        let anchor: CGPoint
        if measurement.kind == .polygon, measurement.isClosed, let centroid = analysis.centroid {
            anchor = centroid
        } else if let lastPoint = measurement.points.last?.cgPoint {
            anchor = lastPoint
        } else {
            return
        }

        let title = measurement.name.isEmpty ? measurement.kind.title : measurement.name
        let detail: String
        switch measurement.kind {
        case .polygon:
            guard measurement.isClosed else {
                detail = "Open polygon"
                break
            }
            detail = formatRequestedArea(analysis.areaSquareMeters, units: exportUnits)
        case .distance, .path:
            detail = "Length \(formatDualLength(analysis.perimeterMeters, units: exportUnits))"
        }

        let callout = measurement.kind == .polygon ? detail : "\(title)  \(detail)"
        drawMapLabel(
            callout,
            at: CGPoint(x: anchor.x + 8 * style.scale, y: anchor.y + 10 * style.scale),
            font: NSFont.systemFont(ofSize: style.mapCalloutFontSize, weight: .semibold),
            tint: color,
            style: style,
            in: context
        )
    }

    private func drawSegmentLabels(
        measurement: MeasurementPolygon,
        analysis: MeasurementAnalysis,
        exportUnits: ExportUnitSet,
        color: NSColor,
        style: PageExportStyle,
        in context: CGContext
    ) {
        guard !analysis.segmentMeasurements.isEmpty else { return }
        guard analysis.segmentMeasurements.count <= 14 else { return }

        let font = NSFont.monospacedSystemFont(ofSize: max(5.8, style.mapLabelFontSize - 0.2), weight: .medium)
        for index in analysis.segmentMeasurements.indices {
            let start = measurement.points[index].cgPoint
            let end = measurement.points[(index + 1) % measurement.points.count].cgPoint
            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), 1)
            let offset = CGPoint(x: (-dy / length) * 6 * style.scale, y: (dx / length) * 6 * style.scale)
            let labelPoint = CGPoint(x: midpoint.x + offset.x, y: midpoint.y + offset.y)
            let text = formatCompactDualLength(analysis.segmentMeasurements[index].lengthMeters, units: exportUnits)
            drawMapLabel(
                text,
                at: labelPoint,
                font: font,
                tint: color,
                style: style,
                in: context
            )
        }
    }

    private func drawSummaryReportPages(
        _ pageMeasurement: PDFPageMeasurement,
        projectName: String,
        unitSettings: UnitSettings,
        exportUnits: ExportUnitSet,
        preferredLinearUnit: LinearUnitDefinition?,
        preferredAreaUnit: AreaUnitDefinition?,
        in context: CGContext
    ) {
        let reportStyle = reportPageStyle()
        let paragraphs = reportParagraphs(
            for: pageMeasurement,
            projectName: projectName,
            exportUnits: exportUnits,
            orderedAreaUnits: orderedAreaUnits(from: unitSettings, preferred: preferredAreaUnit),
            preferredLinearUnit: preferredLinearUnit,
            preferredAreaUnit: preferredAreaUnit,
            titleFont: reportStyle.titleFont,
            bodyFont: reportStyle.bodyFont,
            captionFont: reportStyle.captionFont,
            subtitleFont: reportStyle.subtitleFont
        )

        var paragraphIndex = 0
        let width = reportStyle.contentRect.width

        while paragraphIndex < paragraphs.count {
            var mediaBox = reportStyle.pageBounds
            let mediaBoxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size) as CFData
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary)

            context.saveGState()
            context.setFillColor(NSColor.white.cgColor)
            context.fill(reportStyle.pageBounds)
            context.restoreGState()

            BrandRenderer.drawWatermark(in: context, pageBounds: reportStyle.pageBounds)

            var currentTop = reportStyle.contentRect.maxY
            while paragraphIndex < paragraphs.count {
                let paragraph = paragraphs[paragraphIndex]
                let height = textHeight(paragraph.text, font: paragraph.font, width: width)
                if currentTop - height < reportStyle.contentRect.minY {
                    break
                }

                let rect = CGRect(
                    x: reportStyle.contentRect.minX,
                    y: currentTop - height,
                    width: width,
                    height: height
                )
                drawWrappedText(paragraph.text, in: rect, font: paragraph.font, color: paragraph.color, in: context)
                currentTop = rect.minY - paragraph.spacingAfter

                if paragraph.text == "Measurements" {
                    let dividerY = currentTop + 4
                    context.saveGState()
                    context.setStrokeColor(SummaryPalette.divider.cgColor)
                    context.setLineWidth(0.6)
                    context.move(to: CGPoint(x: reportStyle.contentRect.minX, y: dividerY))
                    context.addLine(to: CGPoint(x: reportStyle.contentRect.maxX, y: dividerY))
                    context.strokePath()
                    context.restoreGState()
                    currentTop -= 4
                }

                paragraphIndex += 1
            }

            context.endPDFPage()
        }
    }

    private func reportParagraphs(
        for pageMeasurement: PDFPageMeasurement,
        projectName: String,
        exportUnits: ExportUnitSet,
        orderedAreaUnits: [AreaUnitDefinition],
        preferredLinearUnit: LinearUnitDefinition?,
        preferredAreaUnit: AreaUnitDefinition?,
        titleFont: NSFont,
        bodyFont: NSFont,
        captionFont: NSFont,
        subtitleFont: NSFont
    ) -> [SummaryParagraph] {
        var paragraphs: [SummaryParagraph] = []
        paragraphs.append(
            SummaryParagraph(
                text: "Annotated Measurement Report",
                font: titleFont,
                color: SummaryPalette.title,
                spacingAfter: 4
            )
        )
        paragraphs.append(
            SummaryParagraph(
                text: projectName,
                font: subtitleFont,
                color: SummaryPalette.body,
                spacingAfter: 8
            )
        )
        paragraphs.append(
            SummaryParagraph(
                text: "Page \(pageMeasurement.pageIndex + 1)  •  \(pageMeasurement.measurements.count) item(s)",
                font: captionFont,
                color: SummaryPalette.secondary,
                spacingAfter: 8
            )
        )

        let calibrationText = calibrationSummary(pageMeasurement.calibration)
        paragraphs.append(
            SummaryParagraph(
                text: "Calibration: \(calibrationText)",
                font: bodyFont,
                color: SummaryPalette.body,
                spacingAfter: 6
            )
        )
        if let calibrationPlace = calibrationPlaceSummary(pageMeasurement.calibration) {
            paragraphs.append(
                SummaryParagraph(
                    text: "Calibrated Place: \(calibrationPlace)",
                    font: captionFont,
                    color: SummaryPalette.body,
                    spacingAfter: 10
                )
            )
        }

        paragraphs.append(
            SummaryParagraph(
                text: "Measurements",
                font: captionFont,
                color: SummaryPalette.secondary,
                spacingAfter: 6
            )
        )

        for (index, measurement) in pageMeasurement.measurements.enumerated() {
            let analysis = MeasurementAnalyzer.analyze(measurement: measurement, calibration: pageMeasurement.calibration)
            let headerColor = overlayColor(for: measurement, isInvalid: analysis.isSelfIntersecting)
            let title = measurement.name.isEmpty ? "Measurement \(index + 1)" : measurement.name
            paragraphs.append(
                SummaryParagraph(
                    text: "\(title)  •  \(measurement.kind.title)",
                    font: NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold),
                    color: headerColor,
                    spacingAfter: 3
                )
            )
            paragraphs.append(
                SummaryParagraph(
                    text: "Points: \(measurement.points.count)",
                    font: captionFont,
                    color: SummaryPalette.secondary,
                    spacingAfter: 6
                )
            )

            if measurement.kind == .polygon, measurement.isClosed {
                paragraphs.append(
                    SummaryParagraph(
                        text: "Perimeter: \(formatDualLength(analysis.perimeterMeters, units: exportUnits))",
                        font: bodyFont,
                        color: SummaryPalette.body,
                        spacingAfter: 3
                    )
                )
                paragraphs.append(
                    SummaryParagraph(
                        text: "Area: \(formatRequestedArea(analysis.areaSquareMeters, units: exportUnits))",
                        font: bodyFont,
                        color: SummaryPalette.body,
                        spacingAfter: 3
                    )
                )
                let areaDetails = orderedAreaUnits.map { unit in
                    "\(unit.symbol) \(formatNumber(unit.fromSquareMeters(analysis.areaSquareMeters), digits: 4))"
                }.joined(separator: "  •  ")
                paragraphs.append(
                    SummaryParagraph(
                        text: "All Units: \(areaDetails)",
                        font: captionFont,
                        color: SummaryPalette.body,
                        spacingAfter: 6
                    )
                )
            } else {
                paragraphs.append(
                    SummaryParagraph(
                        text: "Length: \(formatDualLength(analysis.perimeterMeters, units: exportUnits))",
                        font: bodyFont,
                        color: SummaryPalette.body,
                        spacingAfter: 6
                    )
                )
            }

            if !analysis.segmentMeasurements.isEmpty {
                let segmentDetails = analysis.segmentMeasurements.map { segment in
                    "\(segment.startLabel)-\(segment.endLabel) \(formatDualLength(segment.lengthMeters, units: exportUnits))"
                }.joined(separator: "  •  ")
                paragraphs.append(
                    SummaryParagraph(
                        text: "Sides: \(segmentDetails)",
                        font: captionFont,
                        color: SummaryPalette.body,
                        spacingAfter: 6
                    )
                )
            }

            if !measurement.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paragraphs.append(
                    SummaryParagraph(
                        text: "Note: \(measurement.note)",
                        font: captionFont,
                        color: SummaryPalette.body,
                        spacingAfter: 6
                    )
                )
            }

            if analysis.isSelfIntersecting {
                paragraphs.append(
                    SummaryParagraph(
                        text: "Warning: self-intersecting polygon detected. Verify points before using the area value.",
                        font: captionFont,
                        color: SummaryPalette.warning,
                        spacingAfter: 6
                    )
                )
            }

            if index < pageMeasurement.measurements.count - 1 {
                paragraphs.append(
                    SummaryParagraph(
                        text: "",
                        font: captionFont,
                        color: SummaryPalette.body,
                        spacingAfter: 6
                    )
                )
            }
        }

        return paragraphs
    }

    private func reportPageStyle() -> ReportPageStyle {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return ReportPageStyle(
            pageBounds: bounds,
            contentRect: CGRect(x: 42, y: 58, width: bounds.width - 84, height: bounds.height - 116),
            titleFont: .systemFont(ofSize: 15, weight: .bold),
            subtitleFont: .systemFont(ofSize: 10, weight: .semibold),
            bodyFont: .systemFont(ofSize: 8.4, weight: .regular),
            captionFont: .systemFont(ofSize: 7.5, weight: .medium)
        )
    }

    private func drawMapLabel(
        _ text: String,
        at point: CGPoint,
        font: NSFont,
        tint: NSColor,
        style: PageExportStyle,
        in context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: SummaryPalette.labelText,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: size.width + style.mapLabelPaddingX * 2,
            height: size.height + style.mapLabelPaddingY * 2
        )

        context.saveGState()
        let backgroundPath = NSBezierPath(
            roundedRect: rect,
            xRadius: 5 * style.scale,
            yRadius: 5 * style.scale
        )
        SummaryPalette.labelFill.setFill()
        backgroundPath.fill()
        tint.withAlphaComponent(0.65).setStroke()
        backgroundPath.lineWidth = max(0.3, 0.45 * style.scale)
        backgroundPath.stroke()

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        attributed.draw(at: CGPoint(x: rect.minX + style.mapLabelPaddingX, y: rect.minY + style.mapLabelPaddingY))
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private func drawWrappedText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        in context: CGContext
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(measured.height)
    }

    private func orderedAreaUnits(from settings: UnitSettings, preferred: AreaUnitDefinition?) -> [AreaUnitDefinition] {
        guard let preferred else { return settings.areaUnits }
        var ordered: [AreaUnitDefinition] = [preferred]
        ordered.append(contentsOf: settings.areaUnits.filter { $0.id != preferred.id })
        return ordered
    }

    private func calibrationSummary(_ calibration: CalibrationProfile?) -> String {
        guard let calibration else { return "Not calibrated" }
        let label = calibration.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty {
            return "\(calibration.method.title) • \(label)"
        }
        return "\(calibration.method.title) • \(formatNumber(calibration.metersPerPDFPoint, digits: 6)) m / PDF pt"
    }

    private func calibrationPlaceSummary(_ calibration: CalibrationProfile?) -> String? {
        guard let start = calibration?.referenceStartPoint?.cgPoint,
              let end = calibration?.referenceEndPoint?.cgPoint else { return nil }
        return "(\(formatNumber(start.x, digits: 1)), \(formatNumber(start.y, digits: 1))) to (\(formatNumber(end.x, digits: 1)), \(formatNumber(end.y, digits: 1)))"
    }

    private func formatCompactDualLength(_ meters: Double, units: ExportUnitSet) -> String {
        let feetText: String
        if let foot = units.foot {
            feetText = "\(formatNumber(foot.fromMeters(meters), digits: 1)) ft"
        } else {
            feetText = "\(formatNumber(meters * 3.280839895, digits: 1)) ft"
        }

        let meterText: String
        if let meterUnit = units.meter {
            meterText = "\(formatNumber(meterUnit.fromMeters(meters), digits: 2)) m"
        } else {
            meterText = "\(formatNumber(meters, digits: 2)) m"
        }

        return "\(feetText) / \(meterText)"
    }

    private func formatDualLength(_ meters: Double, units: ExportUnitSet) -> String {
        let feetText: String
        if let foot = units.foot {
            feetText = "\(formatNumber(foot.fromMeters(meters), digits: 2)) ft"
        } else {
            feetText = "\(formatNumber(meters * 3.280839895, digits: 2)) ft"
        }

        let meterText: String
        if let meterUnit = units.meter {
            meterText = "\(formatNumber(meterUnit.fromMeters(meters), digits: 2)) m"
        } else {
            meterText = "\(formatNumber(meters, digits: 2)) m"
        }

        return "\(feetText) / \(meterText)"
    }

    private func formatRequestedArea(_ squareMeters: Double, units: ExportUnitSet) -> String {
        let decimalText: String
        if let decimal = units.decimal {
            decimalText = "\(formatNumber(decimal.fromSquareMeters(squareMeters), digits: 4)) decimal"
        } else {
            decimalText = "\(formatNumber(squareMeters / 40.468564224, digits: 4)) decimal"
        }

        let squareFeetText: String
        if let squareFoot = units.squareFoot {
            squareFeetText = "\(formatNumber(squareFoot.fromSquareMeters(squareMeters), digits: 2)) sq ft"
        } else {
            squareFeetText = "\(formatNumber(squareMeters * 10.763910417, digits: 2)) sq ft"
        }

        let squareMetersText: String
        if let squareMeter = units.squareMeter {
            squareMetersText = "\(formatNumber(squareMeter.fromSquareMeters(squareMeters), digits: 2)) sq m"
        } else {
            squareMetersText = "\(formatNumber(squareMeters, digits: 2)) sq m"
        }

        return "\(decimalText)  •  \(squareFeetText)  •  \(squareMetersText)"
    }

    private func formatLength(_ meters: Double, preferred: LinearUnitDefinition?) -> String {
        if let preferred {
            let converted = preferred.fromMeters(meters)
            if preferred.id == "meter" {
                return "\(formatNumber(converted, digits: 2)) \(preferred.symbol)"
            }
            return "\(formatNumber(converted, digits: 2)) \(preferred.symbol)  (\(formatNumber(meters, digits: 2)) m)"
        }
        return "\(formatNumber(meters, digits: 2)) m"
    }

    private func formatArea(_ squareMeters: Double, preferred: AreaUnitDefinition?) -> String {
        if let preferred {
            let converted = preferred.fromSquareMeters(squareMeters)
            if preferred.id == "sqm" {
                return "\(formatNumber(converted, digits: 2)) \(preferred.symbol)"
            }
            return "\(formatNumber(converted, digits: 4)) \(preferred.symbol)  (\(formatNumber(squareMeters, digits: 2)) sq m)"
        }
        return "\(formatNumber(squareMeters, digits: 2)) sq m"
    }

    private func formatNumber(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func overlayColor(for measurement: MeasurementPolygon, isInvalid: Bool) -> NSColor {
        if measurement.kind == .polygon, isInvalid {
            return OverlayPalette.invalidPolygon
        }
        switch measurement.kind {
        case .distance:
            return OverlayPalette.savedDistance
        case .path:
            return OverlayPalette.savedPath
        case .polygon:
            return OverlayPalette.savedPolygon
        }
    }
}
