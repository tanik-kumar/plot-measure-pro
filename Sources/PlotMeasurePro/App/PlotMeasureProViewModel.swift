import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class PlotMeasureProViewModel: ObservableObject {
    struct CalibrationFormState {
        var method: CalibrationMethod = .manualDistance
        var manualDistanceText = ""
        var manualUnitID = "meter"
        var ratioText = "4000"
        var paperDistanceText = "16"
        var paperUnitID = "inch"
        var groundDistanceText = "1"
        var groundUnitID = "mile"
    }

    struct AlertState: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    private struct EditorSnapshot {
        var project: PDFDocumentProject?
        var currentPageIndex: Int
        var selectedMeasurementID: UUID?
        var selectedPointID: UUID?
        var draftMeasurement: MeasurementPolygon?
        var calibrationDraftPoints: [MeasurementPoint]
    }

    @Published var project: PDFDocumentProject?
    @Published var pdfDocument: PDFDocument?
    @Published var projectFileURL: URL?
    @Published var currentPageIndex = 0
    @Published var selectedMeasurementID: UUID?
    @Published var selectedPointID: UUID?
    @Published var draftMeasurement: MeasurementPolygon?
    @Published var calibrationDraftPoints: [MeasurementPoint] = []
    @Published var activeTool: ToolMode = .polygon
    @Published var snapMode: SnapMode = .free
    @Published var showBoundingBox = false
    @Published var showTriangulation = false
    @Published var cursorPDFPoint: CGPoint?
    @Published var zoomScale: Double = 1
    @Published var calibrationForm = CalibrationFormState()
    @Published var ocrSuggestions: [OCRScaleSuggestion] = []
    @Published var recognizedMapTextsByPage: [Int: [RecognizedMapText]] = [:]
    @Published var selectedRecognizedTextID: UUID?
    @Published var selectedPDFText: String?
    @Published var alertState: AlertState?
    @Published var statusMessage = "Open a survey PDF to start."
    @Published var isRunningOCR = false
    @Published var isRunningMapTextOCR = false
    @Published var showRecognizedTextOverlay = true
    @Published var isShowingExportMenu = false

    private let projectStore = ProjectStore()
    private let exportService = ExportService()
    private let ocrDetector = OCRScaleDetector()
    private let edgeSnapEngine = EdgeSnapEngine()
    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []
    private var dragSessionActive = false

    var hasUndo: Bool { !undoStack.isEmpty }
    var hasRedo: Bool { !redoStack.isEmpty }

    var currentPage: PDFPageMeasurement? {
        project?.page(at: currentPageIndex)
    }

    var currentCalibration: CalibrationProfile? {
        currentPage?.calibration
    }

    var currentMeasurements: [MeasurementPolygon] {
        currentPage?.measurements ?? []
    }

    var selectedMeasurement: MeasurementPolygon? {
        if let id = selectedMeasurementID,
           let measurement = currentMeasurements.first(where: { $0.id == id }) {
            return measurement
        }
        if draftMeasurement?.id == selectedMeasurementID {
            return draftMeasurement
        }
        return nil
    }

    var currentRecognizedMapTexts: [RecognizedMapText] {
        recognizedMapTextsByPage[currentPageIndex] ?? []
    }

    var selectedRecognizedText: RecognizedMapText? {
        guard let selectedRecognizedTextID else { return nil }
        return currentRecognizedMapTexts.first { $0.id == selectedRecognizedTextID }
    }

    var selectedReadableText: String? {
        if let selectedPDFText, !selectedPDFText.isEmpty {
            return selectedPDFText
        }
        return selectedRecognizedText?.text
    }

    var overlayState: CanvasOverlayState {
        CanvasOverlayState(
            pageIndex: currentPageIndex,
            activeTool: activeTool,
            snapMode: snapMode,
            measurements: currentMeasurements,
            draftMeasurement: draftMeasurement,
            calibrationDraftPoints: calibrationDraftPoints,
            selectedMeasurementID: selectedMeasurementID,
            selectedPointID: selectedPointID,
            calibration: currentCalibration,
            showBoundingBox: showBoundingBox,
            showTriangulation: showTriangulation,
            preferredLinearUnit: project?.unitSettings.linearUnit(id: project?.unitSettings.preferredLinearUnitID ?? ""),
            recognizedTexts: currentRecognizedMapTexts,
            selectedRecognizedTextID: selectedRecognizedTextID,
            showRecognizedTextOverlay: showRecognizedTextOverlay
        )
    }

    var selectedAnalysis: MeasurementAnalysis? {
        guard let measurement = selectedMeasurement else { return nil }
        return MeasurementAnalyzer.analyze(measurement: measurement, calibration: currentCalibration)
    }

    init() {
        openBundledSampleIfPresent()
    }

    func openBundledSampleIfPresent() {
        let sampleURL = URL(fileURLWithPath: "/Users/tanik/Documents/My/PLOT/Larpur/R-Map-Larpur-Thana-No-305.pdf")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }
        do {
            try openPDF(at: sampleURL)
            statusMessage = "Loaded sample PDF. Calibrate the map before measuring."
        } catch {
            presentError(title: "Could Not Load Sample PDF", error: error)
        }
    }

    func openPDFPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try openPDF(at: url)
            } catch {
                presentError(title: "Could Not Open PDF", error: error)
            }
        }
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try openProject(at: url)
            } catch {
                presentError(title: "Could Not Open Project", error: error)
            }
        }
    }

    func saveProject() {
        guard let project else { return }
        if let projectFileURL {
            do {
                try projectStore.save(project: project, to: projectFileURL)
                statusMessage = "Project saved to \(projectFileURL.lastPathComponent)."
            } catch {
                presentError(title: "Save Failed", error: error)
            }
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        guard let project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(project.name).plotmeasure.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try projectStore.save(project: project, to: url)
                projectFileURL = url
                statusMessage = "Project saved to \(url.lastPathComponent)."
            } catch {
                presentError(title: "Save Failed", error: error)
            }
        }
    }

    func exportJSONReport() {
        guard let project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(project.name)-report.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let report = exportService.buildReport(project: project)
                try exportService.exportJSON(report: report, to: url)
                statusMessage = "JSON report exported."
            } catch {
                presentError(title: "Export Failed", error: error)
            }
        }
    }

    func exportCSVReport() {
        guard let project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(project.name)-report.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let report = exportService.buildReport(project: project)
                try exportService.exportCSV(report: report, to: url)
                statusMessage = "CSV report exported."
            } catch {
                presentError(title: "Export Failed", error: error)
            }
        }
    }

    func exportAnnotatedPDF() {
        guard let project, let pdfDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(project.name)-annotated.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try exportService.exportAnnotatedPDF(project: project, originalDocument: pdfDocument, to: url)
                statusMessage = "Annotated PDF exported."
            } catch {
                presentError(title: "Export Failed", error: error)
            }
        }
    }

    func openPDF(at url: URL) throws {
        guard let document = PDFDocument(url: url) else {
            throw ProjectStoreError.unreadablePDF
        }
        pdfDocument = document
        project = projectStore.createProject(for: url, pageCount: document.pageCount)
        projectFileURL = nil
        currentPageIndex = 0
        selectedMeasurementID = nil
        selectedPointID = nil
        draftMeasurement = nil
        calibrationDraftPoints = []
        ocrSuggestions = []
        recognizedMapTextsByPage = [:]
        selectedRecognizedTextID = nil
        selectedPDFText = nil
        edgeSnapEngine.clearCache()
        clearHistory()
        applyRotationsFromProject()
        statusMessage = "Opened \(url.lastPathComponent). Select a page and calibrate."
    }

    func openProject(at url: URL) throws {
        let loaded = try projectStore.loadProject(from: url)
        let document = try projectStore.loadPDFDocument(for: loaded)
        project = loaded
        pdfDocument = document
        projectFileURL = url
        currentPageIndex = min(currentPageIndex, max(document.pageCount - 1, 0))
        selectedMeasurementID = nil
        selectedPointID = nil
        draftMeasurement = nil
        calibrationDraftPoints = []
        ocrSuggestions = []
        recognizedMapTextsByPage = [:]
        selectedRecognizedTextID = nil
        selectedPDFText = nil
        edgeSnapEngine.clearCache()
        clearHistory()
        applyRotationsFromProject()
        statusMessage = "Loaded project \(url.lastPathComponent)."
    }

    func selectPage(index: Int) {
        guard let document = pdfDocument, index >= 0, index < document.pageCount else { return }
        currentPageIndex = index
        selectedMeasurementID = nil
        selectedPointID = nil
        draftMeasurement = nil
        calibrationDraftPoints = []
        ocrSuggestions = []
        selectedRecognizedTextID = nil
        selectedPDFText = nil
        statusMessage = "Page \(index + 1) selected."
    }

    func rotateCurrentPage(clockwise: Bool) {
        guard var project else { return }
        registerUndoSnapshot()
        guard let pageOffset = project.pages.firstIndex(where: { $0.pageIndex == currentPageIndex }) else { return }
        let delta = clockwise ? 90 : -90
        project.pages[pageOffset].rotationDegrees = normalizedRotation(project.pages[pageOffset].rotationDegrees + delta)
        self.project = project
        applyRotationsFromProject()
    }

    func setTool(_ tool: ToolMode) {
        activeTool = tool
        selectedPointID = nil
        if tool != .text {
            selectedPDFText = nil
        }
        if tool != .edit, tool != .pan {
            statusMessage = "Active tool: \(tool.title)."
        }
        if tool == .text {
            statusMessage = "Text mode: drag to select embedded PDF text, or run OCR to read scanned map text."
        }
    }

    func setCursor(point: CGPoint?, zoom: Double? = nil) {
        cursorPDFPoint = point
        if let zoom {
            zoomScale = zoom
        }
    }

    func closeDraftIfPossible() {
        guard var draft = draftMeasurement else { return }
        guard draft.kind != .distance else { return }
        guard draft.points.count >= 2 else { return }
        registerUndoSnapshot()
        if draft.kind == .polygon {
            guard draft.points.count >= 3 else {
                statusMessage = "Polygon needs at least three vertices."
                return
            }
            draft.isClosed = true
        }
        draft.updatedAt = .now
        commitDraft(draft)
    }

    func clearDraft() {
        draftMeasurement = nil
        calibrationDraftPoints = []
        selectedMeasurementID = nil
        selectedPointID = nil
        statusMessage = "Cleared current drawing."
    }

    func deleteSelectedMeasurement() {
        guard var project, let selectedMeasurementID else { return }
        guard let pageIndex = project.pages.firstIndex(where: { $0.pageIndex == currentPageIndex }) else { return }
        guard let measurementIndex = project.pages[pageIndex].measurements.firstIndex(where: { $0.id == selectedMeasurementID }) else { return }
        registerUndoSnapshot()
        project.pages[pageIndex].measurements.remove(at: measurementIndex)
        project.updatedAt = .now
        self.project = project
        self.selectedMeasurementID = nil
        self.selectedPointID = nil
        statusMessage = "Deleted measurement."
    }

    func deleteSelectedPoint() {
        guard let selectedMeasurementID, let selectedPointID else { return }
        registerUndoSnapshot()
        if draftMeasurement?.id == selectedMeasurementID {
            draftMeasurement?.points.removeAll { $0.id == selectedPointID }
            if draftMeasurement?.kind == .polygon, (draftMeasurement?.points.count ?? 0) < 3 {
                draftMeasurement?.isClosed = false
            }
        } else {
            mutateMeasurement(id: selectedMeasurementID) { measurement in
                measurement.points.removeAll { $0.id == selectedPointID }
                if measurement.kind == .polygon, measurement.points.count < 3 {
                    measurement.isClosed = false
                }
            }
        }
        self.selectedPointID = nil
        statusMessage = "Deleted vertex."
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot: snapshot)
        statusMessage = "Undo."
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot: snapshot)
        statusMessage = "Redo."
    }

    func scanCurrentPageForScale() {
        guard let page = pdfDocument?.page(at: currentPageIndex) else { return }
        isRunningOCR = true
        Task {
            do {
                let suggestions = try await ocrDetector.detectSuggestions(on: page)
                await MainActor.run {
                    self.ocrSuggestions = suggestions
                    self.isRunningOCR = false
                    self.statusMessage = suggestions.isEmpty ? "No scale text found." : "Found \(suggestions.count) scale suggestion(s)."
                }
            } catch {
                await MainActor.run {
                    self.isRunningOCR = false
                    self.presentError(title: "OCR Failed", error: error)
                }
            }
        }
    }

    func scanCurrentPageForMapText() {
        guard let page = pdfDocument?.page(at: currentPageIndex) else { return }
        isRunningMapTextOCR = true
        Task {
            do {
                let texts = try await ocrDetector.detectMapText(on: page)
                await MainActor.run {
                    self.recognizedMapTextsByPage[self.currentPageIndex] = texts
                    self.selectedRecognizedTextID = texts.first?.id
                    self.isRunningMapTextOCR = false
                    self.statusMessage = texts.isEmpty ? "No map text found." : "Read \(texts.count) text item(s) on page \(self.currentPageIndex + 1)."
                }
            } catch {
                await MainActor.run {
                    self.isRunningMapTextOCR = false
                    self.presentError(title: "Map Text OCR Failed", error: error)
                }
            }
        }
    }

    func clearCurrentPageMapText() {
        recognizedMapTextsByPage[currentPageIndex] = []
        selectedRecognizedTextID = nil
        statusMessage = "Cleared map text OCR for page \(currentPageIndex + 1)."
    }

    func selectRecognizedText(_ id: UUID?) {
        selectedRecognizedTextID = id
        if id != nil {
            selectedPDFText = nil
        }
    }

    func setSelectedPDFText(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        guard selectedPDFText != normalized else { return }
        selectedPDFText = normalized
        if normalized != nil, selectedRecognizedTextID != nil {
            selectedRecognizedTextID = nil
        }
    }

    func copySelectedText() {
        guard let selectedReadableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedReadableText, forType: .string)
        statusMessage = "Copied selected text."
    }

    func applyOCRSuggestion(_ suggestion: OCRScaleSuggestion) {
        switch suggestion.parsedKind {
        case .ratio(let denominator):
            calibrationForm.method = .ratioScale
            calibrationForm.ratioText = denominator.formatted()
            applyRatioCalibration()
        case .mapScale(let paperDistance, let paperUnitID, let groundDistance, let groundUnitID):
            calibrationForm.method = .imperialScale
            calibrationForm.paperDistanceText = paperDistance.formatted()
            calibrationForm.paperUnitID = paperUnitID
            calibrationForm.groundDistanceText = groundDistance.formatted()
            calibrationForm.groundUnitID = groundUnitID
            applyMapScaleCalibration()
        }
    }

    func applyManualCalibration(as method: CalibrationMethod = .manualDistance) {
        guard calibrationDraftPoints.count == 2 else {
            presentMessage(title: "Calibration Points Required", message: "Click two endpoints on the printed scale or a known line before applying calibration.")
            return
        }
        guard let distance = Double(calibrationForm.manualDistanceText),
              let unit = project?.unitSettings.linearUnit(id: calibrationForm.manualUnitID) else {
            presentMessage(title: "Invalid Calibration", message: "Enter a valid numeric distance and unit.")
            return
        }
        let pdfDistance = GeometryEngine.distance(calibrationDraftPoints[0].cgPoint, calibrationDraftPoints[1].cgPoint)
        do {
            let metersPerPoint = try CalibrationEngine.metersPerPDFPointForManualCalibration(
                pdfPointDistance: pdfDistance,
                realWorldDistance: distance,
                unit: unit
            )
            let label = "\(distance.formatted()) \(unit.symbol) over \(Int(pdfDistance.rounded())) PDF pt"
            applyCalibration(
                CalibrationProfile(
                    method: method,
                    metersPerPDFPoint: metersPerPoint,
                    label: label,
                    pageIndex: currentPageIndex,
                    referenceDistance: distance,
                    referenceUnitID: unit.id,
                    referenceStartPoint: calibrationDraftPoints.first,
                    referenceEndPoint: calibrationDraftPoints.last
                )
            )
        } catch {
            presentError(title: "Calibration Failed", error: error)
        }
    }

    func applyRatioCalibration() {
        guard let denominator = Double(calibrationForm.ratioText) else {
            presentMessage(title: "Invalid Ratio", message: "Enter a scale denominator such as 4000 for 1:4000.")
            return
        }
        do {
            let metersPerPoint = try CalibrationEngine.metersPerPDFPointForRatioScale(denominator: denominator)
            applyCalibration(
                CalibrationProfile(
                    method: .ratioScale,
                    metersPerPDFPoint: metersPerPoint,
                    label: "1:\(denominator.formatted())",
                    pageIndex: currentPageIndex,
                    ratioDenominator: denominator
                )
            )
        } catch {
            presentError(title: "Calibration Failed", error: error)
        }
    }

    func applyMapScaleCalibration() {
        guard
            let paperDistance = Double(calibrationForm.paperDistanceText),
            let groundDistance = Double(calibrationForm.groundDistanceText),
            let paperUnit = project?.unitSettings.linearUnit(id: calibrationForm.paperUnitID),
            let groundUnit = project?.unitSettings.linearUnit(id: calibrationForm.groundUnitID)
        else {
            presentMessage(title: "Invalid Scale", message: "Enter valid paper and ground scale values.")
            return
        }

        do {
            let metersPerPoint = try CalibrationEngine.metersPerPDFPointForMapScale(
                paperDistance: paperDistance,
                paperUnit: paperUnit,
                groundDistance: groundDistance,
                groundUnit: groundUnit
            )
            applyCalibration(
                CalibrationProfile(
                    method: .imperialScale,
                    metersPerPDFPoint: metersPerPoint,
                    label: "\(paperDistance.formatted()) \(paperUnit.symbol) = \(groundDistance.formatted()) \(groundUnit.symbol)",
                    pageIndex: currentPageIndex,
                    paperDistance: paperDistance,
                    paperUnitID: paperUnit.id,
                    groundDistance: groundDistance,
                    groundUnitID: groundUnit.id
                )
            )
        } catch {
            presentError(title: "Calibration Failed", error: error)
        }
    }

    func applyScaleBarCalibration() {
        applyManualCalibration(as: .scaleBar)
    }

    func updateLinearUnit(_ unit: LinearUnitDefinition) {
        guard var project else { return }
        registerUndoSnapshot()
        guard let index = project.unitSettings.linearUnits.firstIndex(where: { $0.id == unit.id }) else { return }
        project.unitSettings.linearUnits[index] = unit
        project.updatedAt = .now
        self.project = project
    }

    func updateAreaUnit(_ unit: AreaUnitDefinition) {
        guard var project else { return }
        registerUndoSnapshot()
        guard let index = project.unitSettings.areaUnits.firstIndex(where: { $0.id == unit.id }) else { return }
        project.unitSettings.areaUnits[index] = unit
        project.updatedAt = .now
        self.project = project
    }

    func setPreferredLinearUnit(id: String) {
        guard var project else { return }
        project.unitSettings.preferredLinearUnitID = id
        self.project = project
    }

    func setPreferredAreaUnit(id: String) {
        guard var project else { return }
        project.unitSettings.preferredAreaUnitID = id
        self.project = project
    }

    func updatePoint(measurementID: UUID, pointID: UUID, x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        registerUndoSnapshot()
        if draftMeasurement?.id == measurementID {
            guard let offset = draftMeasurement?.points.firstIndex(where: { $0.id == pointID }) else { return }
            draftMeasurement?.points[offset].x = x
            draftMeasurement?.points[offset].y = y
            draftMeasurement?.updatedAt = .now
        } else {
            mutateMeasurement(id: measurementID, registerUndo: false) { measurement in
                guard let offset = measurement.points.firstIndex(where: { $0.id == pointID }) else { return }
                measurement.points[offset].x = x
                measurement.points[offset].y = y
            }
        }
        selectedMeasurementID = measurementID
        selectedPointID = pointID
    }

    func updateMeasurementMetadata(measurementID: UUID, name: String, note: String) {
        registerUndoSnapshot()
        if draftMeasurement?.id == measurementID {
            draftMeasurement?.name = name
            draftMeasurement?.note = note
            draftMeasurement?.updatedAt = .now
        } else {
            mutateMeasurement(id: measurementID, registerUndo: false) { measurement in
                measurement.name = name
                measurement.note = note
            }
        }
    }

    func handleCanvasEvent(_ event: CanvasGestureEvent) {
        switch event {
        case let .canvasClick(point, pageIndex, clickCount):
            guard pageIndex == currentPageIndex else {
                selectPage(index: pageIndex)
                return
            }
            handleCanvasClick(point: point, clickCount: clickCount)
        case .closeDraft:
            closeDraftIfPossible()
        case let .selectMeasurement(id):
            selectedMeasurementID = id
            if id == nil {
                selectedPointID = nil
            }
        case let .selectRecognizedText(id):
            selectRecognizedText(id)
        case let .selectPoint(measurementID, pointID):
            selectedMeasurementID = measurementID
            selectedPointID = pointID
        case .deleteSelectedPoint:
            deleteSelectedPoint()
        case let .insertVertex(measurementID, afterSegmentIndex, point):
            registerUndoSnapshot()
            mutateMeasurement(id: measurementID) { measurement in
                let snapped = snappedPoint(point, pageIndex: measurement.pageIndex)
                measurement.points.insert(MeasurementPoint(point: snapped), at: afterSegmentIndex + 1)
            }
            selectedMeasurementID = measurementID
        case let .beginVertexDrag(measurementID, pointID):
            selectedMeasurementID = measurementID
            selectedPointID = pointID
            beginDragSession()
        case let .dragVertex(measurementID, pointID, point):
            mutateMeasurement(id: measurementID, registerUndo: false) { measurement in
                guard let offset = measurement.points.firstIndex(where: { $0.id == pointID }) else { return }
                measurement.points[offset].cgPoint = snappedPoint(point, pageIndex: measurement.pageIndex)
            }
        case let .endVertexDrag(measurementID, pointID, point):
            mutateMeasurement(id: measurementID, registerUndo: false) { measurement in
                guard let offset = measurement.points.firstIndex(where: { $0.id == pointID }) else { return }
                measurement.points[offset].cgPoint = snappedPoint(point, pageIndex: measurement.pageIndex)
            }
            dragSessionActive = false
            selectedMeasurementID = measurementID
            selectedPointID = pointID
        }
    }

    private func handleCanvasClick(point: CGPoint, clickCount: Int) {
        switch activeTool {
        case .pan:
            break
        case .text:
            selectedMeasurementID = nil
            selectedPointID = nil
            statusMessage = "Text mode: drag to select embedded PDF text or click OCR boxes after scanning."
        case .calibration:
            registerUndoSnapshot()
            let snapped = snappedPoint(point, pageIndex: currentPageIndex)
            calibrationDraftPoints.append(MeasurementPoint(point: snapped))
            calibrationDraftPoints = Array(calibrationDraftPoints.suffix(2))
            selectedMeasurementID = nil
            selectedPointID = nil
            if calibrationDraftPoints.count == 2 {
                statusMessage = "Enter the known scale distance in the inspector and apply calibration."
            }
        case .distance, .path, .polygon:
            registerUndoSnapshot()
            let kind = activeTool.measurementKind ?? .polygon
            let snapped = snappedPoint(point, pageIndex: currentPageIndex)
            if draftMeasurement == nil || draftMeasurement?.kind != kind {
                draftMeasurement = MeasurementPolygon(
                    name: defaultMeasurementName(for: kind),
                    kind: kind,
                    pageIndex: currentPageIndex
                )
            }
            draftMeasurement?.points.append(MeasurementPoint(point: snapped))
            draftMeasurement?.updatedAt = .now
            selectedMeasurementID = draftMeasurement?.id
            selectedPointID = draftMeasurement?.points.last?.id

            if kind == .distance, draftMeasurement?.points.count == 2, let draftMeasurement {
                commitDraft(draftMeasurement)
            } else if kind == .polygon, clickCount >= 2 {
                closeDraftIfPossible()
            }
        case .edit:
            if clickCount == 1 {
                statusMessage = "Edit mode: drag a vertex, double-click a segment to insert, or press Delete to remove a selected vertex."
            }
        }
    }

    private func applyCalibration(_ calibration: CalibrationProfile) {
        guard var project else { return }
        registerUndoSnapshot()
        guard let pageIndex = project.pages.firstIndex(where: { $0.pageIndex == currentPageIndex }) else { return }
        project.pages[pageIndex].calibration = calibration
        project.updatedAt = .now
        self.project = project
        calibrationDraftPoints = []
        statusMessage = "Calibration applied to page \(currentPageIndex + 1)."
    }

    private func commitDraft(_ draft: MeasurementPolygon) {
        guard var project else { return }
        guard let pageOffset = project.pages.firstIndex(where: { $0.pageIndex == draft.pageIndex }) else { return }
        project.pages[pageOffset].measurements.append(draft)
        project.updatedAt = .now
        self.project = project
        selectedMeasurementID = draft.id
        selectedPointID = nil
        draftMeasurement = nil
        statusMessage = "\(draft.kind.title) saved."
    }

    private func mutateMeasurement(
        id: UUID,
        registerUndo: Bool = true,
        _ update: (inout MeasurementPolygon) -> Void
    ) {
        guard var project else { return }
        if registerUndo {
            registerUndoSnapshot()
        }
        guard let pageOffset = project.pages.firstIndex(where: { $0.pageIndex == currentPageIndex }) else { return }
        guard let measurementOffset = project.pages[pageOffset].measurements.firstIndex(where: { $0.id == id }) else { return }
        update(&project.pages[pageOffset].measurements[measurementOffset])
        project.pages[pageOffset].measurements[measurementOffset].updatedAt = .now
        project.updatedAt = .now
        self.project = project
    }

    private func beginDragSession() {
        guard !dragSessionActive else { return }
        registerUndoSnapshot()
        dragSessionActive = true
    }

    private func registerUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    private func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func currentSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            project: project,
            currentPageIndex: currentPageIndex,
            selectedMeasurementID: selectedMeasurementID,
            selectedPointID: selectedPointID,
            draftMeasurement: draftMeasurement,
            calibrationDraftPoints: calibrationDraftPoints
        )
    }

    private func apply(snapshot: EditorSnapshot) {
        project = snapshot.project
        currentPageIndex = snapshot.currentPageIndex
        selectedMeasurementID = snapshot.selectedMeasurementID
        selectedPointID = snapshot.selectedPointID
        draftMeasurement = snapshot.draftMeasurement
        calibrationDraftPoints = snapshot.calibrationDraftPoints
        applyRotationsFromProject()
    }

    private func applyRotationsFromProject() {
        guard let pdfDocument, let project else { return }
        for pageMeasurement in project.pages {
            pdfDocument.page(at: pageMeasurement.pageIndex)?.rotation = pageMeasurement.rotationDegrees
        }
    }

    private func normalizedRotation(_ value: Int) -> Int {
        let normalized = value % 360
        return normalized < 0 ? normalized + 360 : normalized
    }

    private func defaultMeasurementName(for kind: MeasurementKind) -> String {
        let count = currentMeasurements.filter { $0.kind == kind }.count + 1
        return "\(kind.title) \(count)"
    }

    private func snappedPoint(_ point: CGPoint, pageIndex: Int) -> CGPoint {
        guard snapMode == .edge, let page = pdfDocument?.page(at: pageIndex) else {
            return point
        }
        return edgeSnapEngine.snap(point: point, on: page, pageIndex: pageIndex)
    }

    private func presentError(title: String, error: Error) {
        alertState = AlertState(title: title, message: error.localizedDescription)
    }

    private func presentMessage(title: String, message: String) {
        alertState = AlertState(title: title, message: message)
    }
}
