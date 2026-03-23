import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: PlotMeasureProViewModel

    var body: some View {
        HSplitView {
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 320)

            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    PDFCanvasRepresentable(viewModel: viewModel)
                        .background(Color(nsColor: .textBackgroundColor))

                    BrandWatermarkView()
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                }

                Divider()

                HStack {
                    StatusBarView(viewModel: viewModel)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            InspectorView(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    viewModel.openPDFPanel()
                } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                }
                .help("Open PDF")

                Button {
                    viewModel.openProjectPanel()
                } label: {
                    Label("Open Project", systemImage: "folder")
                }
                .help("Open Project")

                Button {
                    viewModel.saveProject()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save Project")
            }

            ToolbarItemGroup {
                Picker("Tool", selection: Binding(
                    get: { viewModel.activeTool },
                    set: { viewModel.setTool($0) }
                )) {
                    ForEach(ToolMode.allCases) { tool in
                        Text(tool.title).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 500)
                .help("Select active tool")
            }

            ToolbarItemGroup {
                Button {
                    viewModel.closeDraftIfPossible()
                } label: {
                    Label("Close Shape", systemImage: "seal")
                }
                .help("Close Shape")

                Button {
                    viewModel.rotateCurrentPage(clockwise: false)
                } label: {
                    Label("Rotate Left", systemImage: "rotate.left")
                }
                .help("Rotate Page Left")

                Button {
                    viewModel.rotateCurrentPage(clockwise: true)
                } label: {
                    Label("Rotate Right", systemImage: "rotate.right")
                }
                .help("Rotate Page Right")

                Button {
                    NotificationCenter.default.post(name: .plotMeasureZoomOut, object: nil)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                Button {
                    NotificationCenter.default.post(name: .plotMeasureZoomIn, object: nil)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .help("Zoom In")

                Button {
                    NotificationCenter.default.post(name: .plotMeasureZoomToFit, object: nil)
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to Page")

                Button {
                    viewModel.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.hasUndo)
                .help("Undo")

                Button {
                    viewModel.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!viewModel.hasRedo)
                .help("Redo")

                Menu {
                    Button("Export JSON Report…") {
                        viewModel.exportJSONReport()
                    }
                    Button("Export CSV Report…") {
                        viewModel.exportCSVReport()
                    }
                    Button("Export Annotated PDF…") {
                        viewModel.exportAnnotatedPDF()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export")
            }
        }
        .alert(item: $viewModel.alertState) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: PlotMeasureProViewModel

    var body: some View {
        List {
            projectSection
            pagesSection
            measurementsSection
        }
        .listStyle(.sidebar)
    }

    private var projectSection: some View {
        Section("Project") {
            if let project = viewModel.project {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.headline)
                    Text(project.pdfFilePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("No project loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pagesSection: some View {
        Section("Pages") {
            if let project = viewModel.project {
                ForEach(Array(project.pages), id: \.id) { page in
                    pageRow(for: page)
                }
            }
        }
    }

    private var measurementsSection: some View {
        Section("Measurements") {
            if viewModel.currentMeasurements.isEmpty {
                Text("No saved measurements on this page")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.currentMeasurements), id: \.id) { measurement in
                    measurementRow(for: measurement)
                }
            }
        }
    }

    private func pageRow(for page: PDFPageMeasurement) -> some View {
        Button {
            viewModel.selectPage(index: page.pageIndex)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Page \(page.pageIndex + 1)")
                    if page.calibration != nil {
                        Text("Calibrated")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if viewModel.currentPageIndex == page.pageIndex {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func measurementRow(for measurement: MeasurementPolygon) -> some View {
        let analysis = MeasurementAnalyzer.analyze(
            measurement: measurement,
            calibration: viewModel.currentCalibration
        )
        return Button {
            viewModel.handleCanvasEvent(.selectMeasurement(measurement.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(measurement.name)
                    Spacer()
                    Text(measurement.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "Perimeter %.2f m", analysis.perimeterMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct InspectorView: View {
    @ObservedObject var viewModel: PlotMeasureProViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                calibrationSection
                textOCRSection
                resultsSection
                displaySection
                pointSection
                segmentSection
                unitSettingsSection
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var calibrationSection: some View {
        GroupBox("Calibration") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Method", selection: $viewModel.calibrationForm.method) {
                    ForEach(CalibrationMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.currentCalibration != nil {
                    Text("Current: \(viewModel.currentCalibration?.label ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Current page is not calibrated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch viewModel.calibrationForm.method {
                case .manualDistance, .scaleBar:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Click two endpoints on the PDF, then enter the real-world distance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Distance", text: $viewModel.calibrationForm.manualDistanceText)
                            Picker("Unit", selection: $viewModel.calibrationForm.manualUnitID) {
                                ForEach(viewModel.project?.unitSettings.linearUnits ?? []) { unit in
                                    Text(unit.symbol).tag(unit.id)
                                }
                            }
                            .frame(width: 120)
                        }
                        HStack {
                            Button("Apply Manual") {
                                viewModel.applyManualCalibration()
                            }
                            .disabled(viewModel.calibrationDraftPoints.count != 2)

                            Button("Apply Scale Bar") {
                                viewModel.applyScaleBarCalibration()
                            }
                            .disabled(viewModel.calibrationDraftPoints.count != 2)
                        }
                    }
                case .ratioScale:
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Scale denominator (N in 1:N)", text: $viewModel.calibrationForm.ratioText)
                        Button("Apply Ratio") {
                            viewModel.applyRatioCalibration()
                        }
                    }
                case .imperialScale:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Paper", text: $viewModel.calibrationForm.paperDistanceText)
                            Picker("Paper Unit", selection: $viewModel.calibrationForm.paperUnitID) {
                                ForEach(viewModel.project?.unitSettings.linearUnits ?? []) { unit in
                                    Text(unit.symbol).tag(unit.id)
                                }
                            }
                            .frame(width: 120)
                        }
                        HStack {
                            TextField("Ground", text: $viewModel.calibrationForm.groundDistanceText)
                            Picker("Ground Unit", selection: $viewModel.calibrationForm.groundUnitID) {
                                ForEach(viewModel.project?.unitSettings.linearUnits ?? []) { unit in
                                    Text(unit.symbol).tag(unit.id)
                                }
                            }
                            .frame(width: 120)
                        }
                        Button("Apply Map Scale") {
                            viewModel.applyMapScaleCalibration()
                        }
                    }
                }

                Divider()

                HStack {
                    Button(viewModel.isRunningOCR ? "Scanning…" : "OCR Scale Suggestions") {
                        viewModel.scanCurrentPageForScale()
                    }
                    .disabled(viewModel.isRunningOCR)

                    if !viewModel.ocrSuggestions.isEmpty {
                        Text("\(viewModel.ocrSuggestions.count) found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(viewModel.ocrSuggestions) { suggestion in
                    Button {
                        viewModel.applyOCRSuggestion(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.sourceText)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                            Text("\(Int(suggestion.confidence * 100))% confidence")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultsSection: some View {
        GroupBox("Results") {
            VStack(alignment: .leading, spacing: 8) {
                if let measurement = viewModel.selectedMeasurement,
                   let analysis = viewModel.selectedAnalysis,
                   let project = viewModel.project {
                    MeasurementMetadataEditor(
                        measurement: measurement,
                        onCommit: { name, note in
                            viewModel.updateMeasurementMetadata(
                                measurementID: measurement.id,
                                name: name,
                                note: note
                            )
                        }
                    )

                    Text(String(format: "Perimeter: %.4f m", analysis.perimeterMeters))
                    Text(String(format: "Area: %.4f sq m", analysis.areaSquareMeters))

                    if let centroid = analysis.centroid {
                        Text(String(format: "Centroid: (%.2f, %.2f)", centroid.x, centroid.y))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if analysis.isSelfIntersecting {
                        Text("Warning: polygon is self-intersecting.")
                            .foregroundStyle(.orange)
                    }

                    Divider()

                    ForEach(project.unitSettings.areaUnits) { unit in
                        Text(String(format: "%@: %.4f", unit.symbol, unit.fromSquareMeters(analysis.areaSquareMeters)))
                            .font(.caption)
                    }
                } else {
                    Text("Select a saved measurement or keep drawing to inspect results.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var textOCRSection: some View {
        GroupBox("Text & OCR") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use Text mode for native PDF text selection, or run OCR to read scanned map labels and Devanagari parcel text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(viewModel.isRunningMapTextOCR ? "Reading…" : "Read OCR Text") {
                        viewModel.scanCurrentPageForMapText()
                    }
                    .disabled(viewModel.isRunningMapTextOCR)

                    Button("Clear OCR") {
                        viewModel.clearCurrentPageMapText()
                    }
                    .disabled(viewModel.currentRecognizedMapTexts.isEmpty)

                    Button("Copy Selected Text") {
                        viewModel.copySelectedText()
                    }
                    .disabled(viewModel.selectedReadableText == nil)
                }

                Toggle("Show OCR boxes on map", isOn: $viewModel.showRecognizedTextOverlay)

                if let selectedReadableText = viewModel.selectedReadableText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedReadableText)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.05))
                            )

                        if let selectedRecognizedText = viewModel.selectedRecognizedText,
                           selectedRecognizedText.normalizedText != selectedRecognizedText.text {
                            Text("Normalized: \(selectedRecognizedText.normalizedText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No text selected. Use Text mode for embedded PDF text or click an OCR box/result after scanning.")
                        .foregroundStyle(.secondary)
                }

                if viewModel.currentRecognizedMapTexts.isEmpty {
                    Text("No map text loaded for this page.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(viewModel.currentRecognizedMapTexts.count) text item(s) on this page")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(viewModel.currentRecognizedMapTexts.prefix(40))) { recognizedText in
                        Button {
                            viewModel.selectRecognizedText(recognizedText.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recognizedText.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if recognizedText.normalizedText != recognizedText.text {
                                    Text(recognizedText.normalizedText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Text("\(Int(recognizedText.confidence * 100))% confidence")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        viewModel.selectedRecognizedTextID == recognizedText.id
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.primary.opacity(0.04)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.currentRecognizedMapTexts.count > 40 {
                        Text("Showing first 40 items in the inspector.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displaySection: some View {
        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Snap", selection: $viewModel.snapMode) {
                    ForEach(SnapMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show bounding box", isOn: $viewModel.showBoundingBox)
                Toggle("Show triangulation", isOn: $viewModel.showTriangulation)

                Picker("Primary Length Unit", selection: Binding(
                    get: { viewModel.project?.unitSettings.preferredLinearUnitID ?? "meter" },
                    set: { viewModel.setPreferredLinearUnit(id: $0) }
                )) {
                    ForEach(viewModel.project?.unitSettings.linearUnits ?? []) { unit in
                        Text(unit.symbol).tag(unit.id)
                    }
                }

                Picker("Primary Area Unit", selection: Binding(
                    get: { viewModel.project?.unitSettings.preferredAreaUnitID ?? "sqm" },
                    set: { viewModel.setPreferredAreaUnit(id: $0) }
                )) {
                    ForEach(viewModel.project?.unitSettings.areaUnits ?? []) { unit in
                        Text(unit.symbol).tag(unit.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pointSection: some View {
        GroupBox("Points") {
            VStack(alignment: .leading, spacing: 8) {
                if let measurement = viewModel.selectedMeasurement {
                    ForEach(Array(measurement.points.enumerated()), id: \.element.id) { index, point in
                        PointEditorRow(
                            index: index,
                            point: point,
                            isSelected: viewModel.selectedPointID == point.id,
                            onSelect: {
                                viewModel.handleCanvasEvent(.selectPoint(measurementID: measurement.id, pointID: point.id))
                            },
                            onCommit: { x, y in
                                viewModel.updatePoint(measurementID: measurement.id, pointID: point.id, x: x, y: y)
                            }
                        )
                    }
                } else {
                    Text("No vertices selected.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var segmentSection: some View {
        GroupBox("Segments") {
            VStack(alignment: .leading, spacing: 8) {
                if let analysis = viewModel.selectedAnalysis {
                    ForEach(Array(analysis.segmentMeasurements.enumerated()), id: \.element.id) { index, segment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(segment.startLabel) → \(segment.endLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "Length %.4f m", segment.lengthMeters))
                            if let angle = segment.angleDegrees, index < analysis.internalAngles.count {
                                Text(String(format: "Internal angle %.2f°", angle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No segment data available.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unitSettingsSection: some View {
        GroupBox("Unit Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Editable units let you match local Bihar land-measure definitions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let project = viewModel.project {
                    Text("Linear Units")
                        .font(.headline)
                    ForEach(Array(project.unitSettings.linearUnits), id: \.id) { unit in
                        EditableLinearUnitRow(unit: unit) { updated in
                            viewModel.updateLinearUnit(updated)
                        }
                    }

                    Divider()

                    Text("Area Units")
                        .font(.headline)
                    ForEach(Array(project.unitSettings.areaUnits), id: \.id) { unit in
                        EditableAreaUnitRow(unit: unit) { updated in
                            viewModel.updateAreaUnit(updated)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PointEditorRow: View {
    let index: Int
    let point: MeasurementPoint
    let isSelected: Bool
    var onSelect: () -> Void
    var onCommit: (Double, Double) -> Void

    @State private var xText: String
    @State private var yText: String

    init(
        index: Int,
        point: MeasurementPoint,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onCommit: @escaping (Double, Double) -> Void
    ) {
        self.index = index
        self.point = point
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onCommit = onCommit
        _xText = State(initialValue: String(format: "%.3f", point.x))
        _yText = State(initialValue: String(format: "%.3f", point.y))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("P\(index + 1)") {
                onSelect()
            }
            .buttonStyle(.borderless)
            .fontWeight(isSelected ? .bold : .regular)

            HStack {
                TextField("x", text: $xText)
                TextField("y", text: $yText)
                Button("Update") {
                    if let x = Double(xText), let y = Double(yText) {
                        onCommit(x, y)
                    }
                }
            }
        }
    }
}

private struct MeasurementMetadataEditor: View {
    let measurement: MeasurementPolygon
    var onCommit: (String, String) -> Void

    @State private var name: String
    @State private var note: String

    init(measurement: MeasurementPolygon, onCommit: @escaping (String, String) -> Void) {
        self.measurement = measurement
        self.onCommit = onCommit
        _name = State(initialValue: measurement.name)
        _note = State(initialValue: measurement.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Measurement name", text: $name)
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(2...4)
            Button("Update Plot Details") {
                onCommit(name, note)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct EditableLinearUnitRow: View {
    let unit: LinearUnitDefinition
    var onCommit: (LinearUnitDefinition) -> Void

    @State private var text: String

    init(unit: LinearUnitDefinition, onCommit: @escaping (LinearUnitDefinition) -> Void) {
        self.unit = unit
        self.onCommit = onCommit
        _text = State(initialValue: String(format: "%.8f", unit.metersPerUnit))
    }

    var body: some View {
        HStack {
            Text(unit.name)
            Spacer()
            TextField("Meters", text: $text)
                .frame(width: 120)
            if unit.isEditable {
                Button("Apply") {
                    guard let value = Double(text), value > 0 else { return }
                    var updated = unit
                    updated.metersPerUnit = value
                    onCommit(updated)
                }
            } else {
                Text(unit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

private struct EditableAreaUnitRow: View {
    let unit: AreaUnitDefinition
    var onCommit: (AreaUnitDefinition) -> Void

    @State private var text: String

    init(unit: AreaUnitDefinition, onCommit: @escaping (AreaUnitDefinition) -> Void) {
        self.unit = unit
        self.onCommit = onCommit
        _text = State(initialValue: String(format: "%.8f", unit.squareMetersPerUnit))
    }

    var body: some View {
        HStack {
            Text(unit.name)
            Spacer()
            TextField("sq m", text: $text)
                .frame(width: 120)
            if unit.isEditable {
                Button("Apply") {
                    guard let value = Double(text), value > 0 else { return }
                    var updated = unit
                    updated.squareMetersPerUnit = value
                    onCommit(updated)
                }
            } else {
                Text(unit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

private struct StatusBarView: View {
    @ObservedObject var viewModel: PlotMeasureProViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text(viewModel.statusMessage)
                .lineLimit(1)
            separator
            Text("Cursor: \(cursorText)")
            separator
            Text(String(format: "Zoom: %.2fx", viewModel.zoomScale))
            separator
            Text("Scale: \(viewModel.currentCalibration?.label ?? "Uncalibrated")")
            separator
            Text("Unit: \(viewModel.project?.unitSettings.preferredAreaUnitID ?? "sqm")")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
    }

    private var cursorText: String {
        guard let point = viewModel.cursorPDFPoint else { return "—" }
        return String(format: "(%.2f, %.2f)", point.x, point.y)
    }

    private var separator: some View {
        Text("•")
            .foregroundStyle(.secondary)
    }
}
