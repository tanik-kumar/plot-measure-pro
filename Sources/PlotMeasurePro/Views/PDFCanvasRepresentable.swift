import AppKit
import PDFKit
import SwiftUI

extension Notification.Name {
    static let plotMeasureZoomIn = Notification.Name("PlotMeasurePro.ZoomIn")
    static let plotMeasureZoomOut = Notification.Name("PlotMeasurePro.ZoomOut")
    static let plotMeasureZoomToFit = Notification.Name("PlotMeasurePro.ZoomToFit")
    static let plotMeasureZoomActualSize = Notification.Name("PlotMeasurePro.ZoomActualSize")
}

struct PDFCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: PlotMeasureProViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> PlotPDFView {
        let pdfView = PlotPDFView()
        pdfView.onCanvasEvent = { event in
            context.coordinator.viewModel.handleCanvasEvent(event)
        }
        pdfView.onCursorUpdate = { point, zoom in
            context.coordinator.viewModel.setCursor(point: point, zoom: zoom)
        }
        return pdfView
    }

    func updateNSView(_ nsView: PlotPDFView, context: Context) {
        nsView.update(
            document: viewModel.pdfDocument,
            pageIndex: viewModel.currentPageIndex,
            overlayState: viewModel.overlayState
        )
    }

    final class Coordinator: NSObject {
        let viewModel: PlotMeasureProViewModel

        init(viewModel: PlotMeasureProViewModel) {
            self.viewModel = viewModel
        }
    }
}

@MainActor
final class PlotPDFView: PDFView {
    private final class OverlayView: NSView {
        weak var owner: PlotPDFView?

        override var isOpaque: Bool {
            false
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let owner else { return }
            owner.drawOverlay(in: dirtyRect)
        }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseMoved(with event: NSEvent) {
            NSCursor.arrow.set()
            owner?.mouseMoved(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            NSCursor.arrow.set()
            owner?.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            NSCursor.arrow.set()
            owner?.mouseDragged(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            NSCursor.arrow.set()
            owner?.mouseUp(with: event)
        }

        override func scrollWheel(with event: NSEvent) {
            owner?.forwardScrollWheelFromOverlay(event)
        }

        override func magnify(with event: NSEvent) {
            owner?.magnify(with: event)
        }

        override func smartMagnify(with event: NSEvent) {
            owner?.smartMagnify(with: event)
        }
    }

    private enum MarkerStyle {
        case measurement
        case calibration
    }

    private enum OverlayPalette {
        static let draftDistance = NSColor(srgbRed: 1.00, green: 0.33, blue: 0.00, alpha: 1.0)
        static let draftPath = NSColor(srgbRed: 1.00, green: 0.33, blue: 0.00, alpha: 1.0)
        static let draftPolygon = NSColor(srgbRed: 1.00, green: 0.05, blue: 0.55, alpha: 1.0)
        static let selectedDistance = NSColor(srgbRed: 1.00, green: 0.05, blue: 0.55, alpha: 1.0)
        static let selectedPath = NSColor(srgbRed: 1.00, green: 0.05, blue: 0.55, alpha: 1.0)
        static let selectedPolygon = NSColor(srgbRed: 1.00, green: 0.05, blue: 0.55, alpha: 1.0)
        static let savedDistance = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.00, alpha: 1.0)
        static let savedPath = NSColor(srgbRed: 0.00, green: 0.78, blue: 1.00, alpha: 1.0)
        static let savedPolygon = NSColor(srgbRed: 0.10, green: 0.82, blue: 0.35, alpha: 1.0)
        static let invalidPolygon = NSColor(srgbRed: 1.00, green: 0.12, blue: 0.12, alpha: 1.0)
        static let calibration = NSColor(srgbRed: 0.00, green: 0.88, blue: 1.00, alpha: 1.0)
        static let centroid = NSColor(srgbRed: 0.00, green: 0.88, blue: 1.00, alpha: 1.0)
        static let ocrBox = NSColor(srgbRed: 0.12, green: 0.82, blue: 1.00, alpha: 1.0)
        static let selectedOCRBox = NSColor(srgbRed: 1.00, green: 0.70, blue: 0.12, alpha: 1.0)
    }

    var onCanvasEvent: ((CanvasGestureEvent) -> Void)?
    var onCursorUpdate: ((CGPoint?, Double) -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private let overlayView = OverlayView(frame: .zero)
    private var overlayState = CanvasOverlayState(
        pageIndex: 0,
        activeTool: .polygon,
        snapMode: .free,
        measurements: [],
        draftMeasurement: nil,
        calibrationDraftPoints: [],
        selectedMeasurementID: nil,
        selectedPointID: nil,
        calibration: nil,
        showBoundingBox: false,
        showTriangulation: false,
        preferredLinearUnit: nil,
        recognizedTexts: [],
        selectedRecognizedTextID: nil,
        showRecognizedTextOverlay: true
    )
    private var activeDrag: (measurementID: UUID, pointID: UUID)?
    private var hoverPagePoint: CGPoint?
    private var hoverPageIndex: Int?
    private weak var observedClipView: NSClipView?
    private weak var observedScrollView: NSScrollView?
    private weak var magnificationHostView: NSView?
    private var magnifyGestureRecognizer: NSMagnificationGestureRecognizer?
    private var magnifyEventMonitor: Any?
    private var cursorEventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        overlayView.discardCursorRects()
        overlayView.addCursorRect(overlayView.bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    func update(document: PDFDocument?, pageIndex: Int, overlayState: CanvasOverlayState) {
        if self.document !== document {
            self.document = document
            autoScales = true
            attachScrollObserversIfNeeded()
        }
        clearSelectionIfNeeded()
        self.overlayState = overlayState
        if let document, pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex), currentPage != page {
            go(to: page)
        }
        invalidateOverlay()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        clearSelectionIfNeeded()
        NSCursor.arrow.set()
        let shouldRedrawForHover = overlayNeedsHoverPreview()
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let (page, pdfPoint) = pagePoint(for: viewPoint) else {
            let hadHover = hoverPagePoint != nil || hoverPageIndex != nil
            hoverPagePoint = nil
            hoverPageIndex = nil
            if shouldRedrawForHover && hadHover {
                invalidateOverlay()
            }
            onCursorUpdate?(nil, scaleFactor)
            return
        }
        let pageIndex = document?.index(for: page) ?? overlayState.pageIndex
        let hoverChanged = hoverPageIndex != pageIndex || hoverPointChanged(from: hoverPagePoint, to: pdfPoint)
        hoverPagePoint = pdfPoint
        hoverPageIndex = pageIndex
        if shouldRedrawForHover && hoverChanged {
            invalidateOverlay()
        }
        if pageIndex == overlayState.pageIndex {
            onCursorUpdate?(pdfPoint, scaleFactor)
        } else {
            onCursorUpdate?(nil, scaleFactor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        clearSelectionIfNeeded()
        NSCursor.arrow.set()
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let (page, pdfPoint) = pagePoint(for: viewPoint) else {
            return
        }
        let pageIndex = document?.index(for: page) ?? overlayState.pageIndex

        if overlayState.activeTool == .edit {
            if let vertex = hitVertex(at: viewPoint) {
                activeDrag = vertex
                onCanvasEvent?(.selectPoint(measurementID: vertex.measurementID, pointID: vertex.pointID))
                onCanvasEvent?(.beginVertexDrag(measurementID: vertex.measurementID, pointID: vertex.pointID))
                return
            }

            if event.clickCount >= 2, let segment = hitSegment(at: viewPoint) {
                onCanvasEvent?(.insertVertex(measurementID: segment.measurementID, afterSegmentIndex: segment.segmentIndex, point: pdfPoint))
                return
            }

            onCanvasEvent?(.selectMeasurement(hitMeasurement(at: viewPoint)))
            return
        }

        if overlayState.activeTool == .polygon, shouldCloseDraft(at: viewPoint) {
            onCanvasEvent?(.closeDraft)
            return
        }

        onCanvasEvent?(.canvasClick(point: pdfPoint, pageIndex: pageIndex, clickCount: event.clickCount))
    }

    override func mouseDragged(with event: NSEvent) {
        clearSelectionIfNeeded()
        NSCursor.arrow.set()
        guard let activeDrag else {
            invalidateOverlay()
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let (_, pdfPoint) = pagePoint(for: viewPoint) else { return }
        hoverPagePoint = pdfPoint
        hoverPageIndex = overlayState.pageIndex
        invalidateOverlay()
        onCanvasEvent?(.dragVertex(measurementID: activeDrag.measurementID, pointID: activeDrag.pointID, point: pdfPoint))
    }

    override func mouseUp(with event: NSEvent) {
        clearSelectionIfNeeded()
        NSCursor.arrow.set()
        guard let activeDrag else {
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let (_, pdfPoint) = pagePoint(for: viewPoint) else { return }
        onCanvasEvent?(.endVertexDrag(measurementID: activeDrag.measurementID, pointID: activeDrag.pointID, point: pdfPoint))
        self.activeDrag = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onCanvasEvent?(.deleteSelectedPoint)
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldHandleZoomScroll(event) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : (event.deltaY * 8)
            if delta > 0 {
                zoomOutFromUI(nil)
            } else if delta < 0 {
                zoomInFromUI(nil)
            }
            return
        }
        super.scrollWheel(with: event)
        invalidateOverlay()
    }

    override func magnify(with event: NSEvent) {
        applyMagnificationDelta(event.magnification)
    }

    override func smartMagnify(with event: NSEvent) {
        if autoScales || scaleFactor <= scaleFactorForSizeToFit * 1.05 {
            setZoomScale(min(maxScaleFactor, scaleFactorForSizeToFit * 2))
        } else {
            zoomToFitFromUI(nil)
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        invalidateOverlay()
    }

    override func layout() {
        super.layout()
        if overlayView.superview !== self {
            addSubview(overlayView, positioned: .above, relativeTo: nil)
        }
        overlayView.frame = bounds
        attachScrollObserversIfNeeded()
        invalidateOverlay()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        overlayView.frame = bounds
        invalidateOverlay()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        invalidateOverlay()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        invalidateOverlay()
    }

    func drawOverlay(in dirtyRect: NSRect) {
        guard let page = currentPage else { return }
        let pageIndex = document?.index(for: page) ?? overlayState.pageIndex
        guard pageIndex == overlayState.pageIndex else { return }

        NSGraphicsContext.saveGraphicsState()
        drawRecognizedTextOverlay(on: page)
        drawMeasurementOverlays(on: page)
        drawCalibrationOverlay(on: page)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func configure() {
        displayMode = .singlePage
        displaysPageBreaks = true
        displaysAsBook = false
        backgroundColor = .windowBackgroundColor
        allowedTouchTypes = [.indirect]
        minScaleFactor = 0.1
        maxScaleFactor = 20
        autoScales = true
        overlayView.owner = self
        overlayView.autoresizingMask = [.width, .height]
        overlayView.frame = bounds
        addSubview(overlayView, positioned: .above, relativeTo: nil)
        clearSelectionIfNeeded()
        setupNotifications()
        setupCursorEventMonitor()
        setupGestureEventMonitor()
        attachScrollObserversIfNeeded()
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleScaleChanged), name: .PDFViewScaleChanged, object: self)
        center.addObserver(self, selector: #selector(handlePageChanged), name: .PDFViewPageChanged, object: self)
        center.addObserver(self, selector: #selector(handleSelectionChanged), name: .PDFViewSelectionChanged, object: self)
        center.addObserver(self, selector: #selector(handleZoomInNotification), name: .plotMeasureZoomIn, object: nil)
        center.addObserver(self, selector: #selector(handleZoomOutNotification), name: .plotMeasureZoomOut, object: nil)
        center.addObserver(self, selector: #selector(handleZoomToFitNotification), name: .plotMeasureZoomToFit, object: nil)
        center.addObserver(self, selector: #selector(handleZoomActualSizeNotification), name: .plotMeasureZoomActualSize, object: nil)
    }

    private func setupGestureEventMonitor() {
        guard magnifyEventMonitor == nil else { return }
        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .smartMagnify]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }

            switch event.type {
            case .magnify:
                self.applyMagnificationDelta(event.magnification)
                return nil
            case .smartMagnify:
                self.smartMagnify(with: event)
                return nil
            default:
                return event
            }
        }
    }

    private func setupCursorEventMonitor() {
        guard cursorEventMonitor == nil else { return }
        cursorEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.cursorUpdate]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }
            self.clearSelectionIfNeeded()
            NSCursor.arrow.set()
            return nil
        }
    }

    @objc private func handleScaleChanged() {
        invalidateOverlay()
        onCursorUpdate?(currentHoverPoint(), scaleFactor)
    }

    @objc private func handlePageChanged() {
        hoverPagePoint = nil
        hoverPageIndex = nil
        invalidateOverlay()
    }

    @objc private func handleClipViewBoundsChanged() {
        invalidateOverlay()
    }

    @objc private func handleSelectionChanged() {
        clearSelectionIfNeeded()
        NSCursor.arrow.set()
    }

    @objc private func handleMagnifyGesture(_ recognizer: NSMagnificationGestureRecognizer) {
        applyMagnificationDelta(recognizer.magnification)
        recognizer.magnification = 0
    }

    @objc private func handleZoomInNotification() {
        zoomInFromUI(nil)
    }

    @objc private func handleZoomOutNotification() {
        zoomOutFromUI(nil)
    }

    @objc private func handleZoomToFitNotification() {
        zoomToFitFromUI(nil)
    }

    @objc private func handleZoomActualSizeNotification() {
        zoomActualSizeFromUI(nil)
    }

    private func pagePoint(for viewPoint: CGPoint) -> (PDFPage, CGPoint)? {
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    private func currentHoverPoint() -> CGPoint? {
        guard let window else { return nil }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard let (_, point) = pagePoint(for: location) else { return nil }
        return point
    }

    private func attachScrollObserversIfNeeded() {
        guard let scrollView = descendantScrollView(in: self) else { return }
        if observedClipView !== scrollView.contentView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleClipViewBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            observedClipView = scrollView.contentView
        }
        observedScrollView = scrollView
        applyArrowCursorRects(to: scrollView)
        applyArrowCursorRects(to: scrollView.contentView)
        if let documentView = scrollView.documentView {
            applyArrowCursorRects(to: documentView)
        }
        installMagnificationSupport(on: scrollView)
    }

    private func descendantScrollView(in root: NSView) -> NSScrollView? {
        if let scrollView = root as? NSScrollView {
            return scrollView
        }
        for subview in root.subviews {
            if let match = descendantScrollView(in: subview) {
                return match
            }
        }
        return nil
    }

    private func invalidateOverlay() {
        overlayView.needsDisplay = true
    }

    private func forwardScrollWheelFromOverlay(_ event: NSEvent) {
        if shouldHandleZoomScroll(event) {
            scrollWheel(with: event)
            return
        }
        if let observedScrollView {
            observedScrollView.scrollWheel(with: event)
            invalidateOverlay()
            onCursorUpdate?(currentHoverPoint(), scaleFactor)
            return
        }
        super.scrollWheel(with: event)
        invalidateOverlay()
    }

    private func applyArrowCursorRects(to view: NSView) {
        view.discardCursorRects()
        view.addCursorRect(view.bounds, cursor: .arrow)
        view.window?.invalidateCursorRects(for: view)
    }

    private func clearSelectionIfNeeded() {
        guard currentSelection != nil else { return }
        clearSelection()
        currentSelection = nil
    }

    private func overlayNeedsHoverPreview() -> Bool {
        overlayState.draftMeasurement != nil || !overlayState.calibrationDraftPoints.isEmpty || activeDrag != nil
    }

    private func hoverPointChanged(from oldPoint: CGPoint?, to newPoint: CGPoint) -> Bool {
        guard let oldPoint else { return true }
        let threshold = max(0.35, 1.0 / max(scaleFactor, 1))
        return GeometryEngine.distance(oldPoint, newPoint) > threshold
    }

    private func installMagnificationSupport(on scrollView: NSScrollView) {
        scrollView.allowedTouchTypes = [.indirect]
        scrollView.contentView.allowedTouchTypes = [.indirect]
        scrollView.documentView?.allowedTouchTypes = [.indirect]

        let hostView = scrollView.documentView ?? scrollView.contentView
        if magnificationHostView !== hostView {
            if let existingRecognizer = magnifyGestureRecognizer, let oldHost = magnificationHostView {
                oldHost.removeGestureRecognizer(existingRecognizer)
            }
            let recognizer = magnifyGestureRecognizer ?? NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnifyGesture(_:)))
            hostView.addGestureRecognizer(recognizer)
            magnifyGestureRecognizer = recognizer
            magnificationHostView = hostView
        }
    }

    private func shouldHandleZoomScroll(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    private func applyMagnificationDelta(_ delta: CGFloat) {
        guard delta != 0 else { return }
        let nextScale = scaleFactor * max(0.2, 1 + delta)
        setZoomScale(nextScale)
    }

    private func setZoomScale(_ newScale: CGFloat) {
        autoScales = false
        scaleFactor = min(max(newScale, minScaleFactor), maxScaleFactor)
        invalidateOverlay()
        onCursorUpdate?(currentHoverPoint(), scaleFactor)
    }

    @IBAction func zoomInFromUI(_ sender: Any?) {
        setZoomScale(scaleFactor * 1.2)
    }

    @IBAction func zoomOutFromUI(_ sender: Any?) {
        setZoomScale(scaleFactor / 1.2)
    }

    @IBAction func zoomToFitFromUI(_ sender: Any?) {
        autoScales = true
        invalidateOverlay()
        onCursorUpdate?(currentHoverPoint(), scaleFactor)
    }

    @IBAction func zoomActualSizeFromUI(_ sender: Any?) {
        setZoomScale(1.0)
    }

    private func drawMeasurementOverlays(on page: PDFPage) {
        for measurement in overlayState.measurements {
            drawMeasurement(measurement, on: page, isSelected: overlayState.selectedMeasurementID == measurement.id, isDraft: false)
        }
        if let draftMeasurement = overlayState.draftMeasurement {
            drawMeasurement(draftMeasurement, on: page, isSelected: overlayState.selectedMeasurementID == draftMeasurement.id, isDraft: true)
        }
    }

    private func drawRecognizedTextOverlay(on page: PDFPage) {
        guard overlayState.showRecognizedTextOverlay else { return }
        guard !overlayState.recognizedTexts.isEmpty else { return }

        for recognizedText in overlayState.recognizedTexts {
            let rect = convert(rect: recognizedText.boundingBox, from: page)
            guard rect.width > 1, rect.height > 1 else { continue }

            let isSelected = overlayState.selectedRecognizedTextID == recognizedText.id
            let color = isSelected ? OverlayPalette.selectedOCRBox : OverlayPalette.ocrBox
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
            path.setLineDash([6, 4], count: 2, phase: 0)

            color.withAlphaComponent(isSelected ? 0.14 : 0.06).setFill()
            path.fill()

            NSColor.black.withAlphaComponent(0.42).setStroke()
            path.lineWidth = isSelected ? 3.2 : 2.4
            path.stroke()

            color.setStroke()
            path.lineWidth = isSelected ? 1.8 : 1.2
            path.stroke()

            if isSelected {
                drawLabel(
                    recognizedText.text,
                    at: CGPoint(x: rect.minX, y: rect.maxY + 4),
                    color: color
                )
            }
        }
    }

    private func drawMeasurement(_ measurement: MeasurementPolygon, on page: PDFPage, isSelected: Bool, isDraft: Bool) {
        let analysis = MeasurementAnalyzer.analyze(measurement: measurement, calibration: overlayState.calibration)
        let points = measurement.points.map { convert($0.cgPoint, from: page) }
        let strokeColor = overlayColor(for: measurement, isSelected: isSelected, isDraft: isDraft, isInvalid: analysis.isSelfIntersecting)
        let showsDetailedLabels = isSelected || isDraft
        guard points.count > 1 else {
            drawVertices(measurement.points, on: page, color: strokeColor, style: .measurement)
            drawDraftPreviewIfNeeded(for: measurement, on: page, color: strokeColor)
            return
        }

        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }

        if measurement.kind == .polygon, measurement.isClosed || isDraft {
            if let fillPath = polygonFillPath(for: measurement, on: page, includeHoverPreview: isDraft) {
                let fillAlpha: CGFloat = isDraft ? 0.30 : 0.14
                strokeColor.withAlphaComponent(fillAlpha).setFill()
                fillPath.fill()
            }
        }

        if measurement.kind == .polygon, measurement.isClosed {
            path.close()
        }
        strokePath(path, color: strokeColor, lineWidth: strokeWidth(for: measurement, isSelected: isSelected, isDraft: isDraft))

        drawDraftPreviewIfNeeded(for: measurement, on: page, color: strokeColor)
        drawVertices(measurement.points, on: page, color: strokeColor, style: .measurement)
        if showsDetailedLabels {
            drawPointLabels(measurement.points, on: page, color: strokeColor)
            drawSegmentLabels(measurement: measurement, analysis: analysis, on: page, color: strokeColor)
        }

        if measurement.kind == .polygon, measurement.isClosed {
            if let centroid = analysis.centroid {
                let viewCentroid = convert(centroid, from: page)
                let centroidRect = CGRect(x: viewCentroid.x - 4, y: viewCentroid.y - 4, width: 8, height: 8)
                OverlayPalette.centroid.setFill()
                NSBezierPath(ovalIn: centroidRect).fill()
            }

            if overlayState.showBoundingBox, let box = analysis.boundingBox {
                let topLeft = convert(CGPoint(x: box.minX, y: box.maxY), from: page)
                let bottomRight = convert(CGPoint(x: box.maxX, y: box.minY), from: page)
                let rect = CGRect(
                    x: min(topLeft.x, bottomRight.x),
                    y: min(topLeft.y, bottomRight.y),
                    width: abs(bottomRight.x - topLeft.x),
                    height: abs(bottomRight.y - topLeft.y)
                )
                let dash = NSBezierPath(rect: rect)
                dash.setLineDash([6, 4], count: 2, phase: 0)
                strokeColor.withAlphaComponent(0.6).setStroke()
                dash.lineWidth = 1
                dash.stroke()
            }

            if overlayState.showTriangulation {
                strokeColor.withAlphaComponent(0.4).setStroke()
                for triangle in analysis.triangles {
                    let path = NSBezierPath()
                    let converted = triangle.map { convert($0, from: page) }
                    guard let first = converted.first else { continue }
                    path.move(to: first)
                    for point in converted.dropFirst() {
                        path.line(to: point)
                    }
                    path.close()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }
    }

    private func drawCalibrationOverlay(on page: PDFPage) {
        guard !overlayState.calibrationDraftPoints.isEmpty else { return }
        let points = overlayState.calibrationDraftPoints.map { convert($0.cgPoint, from: page) }
        let color = OverlayPalette.calibration
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        strokePath(path, color: color, lineWidth: 4.5)

        if overlayState.calibrationDraftPoints.count == 1,
           let hoverPoint = hoverPagePoint,
           hoverPageIndex == overlayState.pageIndex {
            let previewPath = NSBezierPath()
            previewPath.lineJoinStyle = .round
            previewPath.lineCapStyle = .round
            previewPath.setLineDash([10, 6], count: 2, phase: 0)
            previewPath.move(to: points[0])
            previewPath.line(to: convert(hoverPoint, from: page))
            strokePath(previewPath, color: color.withAlphaComponent(0.95), lineWidth: 3.5)
        }

        drawVertices(overlayState.calibrationDraftPoints, on: page, color: color, style: .calibration)
    }

    private func drawVertices(_ points: [MeasurementPoint], on page: PDFPage, color: NSColor, style: MarkerStyle) {
        for point in points {
            let viewPoint = convert(point.cgPoint, from: page)
            let isSelected = overlayState.selectedPointID == point.id
            let diameter: CGFloat
            switch style {
            case .measurement:
                diameter = isSelected ? 22 : 18
            case .calibration:
                diameter = 22
            }

            let outerRect = CGRect(
                x: viewPoint.x - diameter / 2,
                y: viewPoint.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            let middleRect = outerRect.insetBy(dx: 1.6, dy: 1.6)
            let innerRect = outerRect.insetBy(dx: 3.6, dy: 3.6)

            NSColor.black.withAlphaComponent(0.92).setFill()
            NSBezierPath(ovalIn: outerRect).fill()

            NSColor.white.withAlphaComponent(0.98).setFill()
            NSBezierPath(ovalIn: middleRect).fill()

            color.setFill()
            NSBezierPath(ovalIn: innerRect).fill()

            let ring = NSBezierPath(ovalIn: outerRect.insetBy(dx: 0.8, dy: 0.8))
            ring.lineWidth = 2
            NSColor.black.withAlphaComponent(0.85).setStroke()
            ring.stroke()

            let crosshair = NSBezierPath()
            crosshair.lineWidth = style == .calibration ? 1.6 : 1.2
            crosshair.move(to: CGPoint(x: viewPoint.x - 5.5, y: viewPoint.y))
            crosshair.line(to: CGPoint(x: viewPoint.x + 5.5, y: viewPoint.y))
            crosshair.move(to: CGPoint(x: viewPoint.x, y: viewPoint.y - 5.5))
            crosshair.line(to: CGPoint(x: viewPoint.x, y: viewPoint.y + 5.5))
            NSColor.black.withAlphaComponent(style == .calibration ? 0.9 : 0.72).setStroke()
            crosshair.stroke()

            if style == .calibration {
                let crosshair = NSBezierPath()
                crosshair.lineWidth = 1.4
                crosshair.move(to: CGPoint(x: viewPoint.x - 5, y: viewPoint.y))
                crosshair.line(to: CGPoint(x: viewPoint.x + 5, y: viewPoint.y))
                crosshair.move(to: CGPoint(x: viewPoint.x, y: viewPoint.y - 5))
                crosshair.line(to: CGPoint(x: viewPoint.x, y: viewPoint.y + 5))
                NSColor.black.withAlphaComponent(0.85).setStroke()
                crosshair.stroke()
            }
        }
    }

    private func drawPointLabels(_ points: [MeasurementPoint], on page: PDFPage, color: NSColor) {
        for (index, point) in points.enumerated() {
            let viewPoint = convert(point.cgPoint, from: page)
            drawLabel("P\(index + 1)", at: CGPoint(x: viewPoint.x + 6, y: viewPoint.y + 6), color: color)
        }
    }

    private func drawSegmentLabels(measurement: MeasurementPolygon, analysis: MeasurementAnalysis, on page: PDFPage, color: NSColor) {
        guard !analysis.segmentMeasurements.isEmpty else { return }
        let preferredUnit = overlayState.preferredLinearUnit
        for index in analysis.segmentMeasurements.indices {
            let start = measurement.points[index].cgPoint
            let end = measurement.points[(index + 1) % measurement.points.count].cgPoint
            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let viewMid = convert(midpoint, from: page)
            let segment = analysis.segmentMeasurements[index]
            let text: String
            if let preferredUnit {
                let value = preferredUnit.fromMeters(segment.lengthMeters)
                text = String(format: "%.2f %@", value, preferredUnit.symbol)
            } else {
                text = String(format: "%.1f pt", GeometryEngine.distance(start, end))
            }
            drawLabel(text, at: CGPoint(x: viewMid.x + 6, y: viewMid.y - 4), color: color)
        }

        guard measurement.kind == .polygon, measurement.isClosed else { return }
        for (index, angle) in analysis.internalAngles.enumerated() {
            let point = convert(measurement.points[index].cgPoint, from: page)
            drawLabel(String(format: "%.1f°", angle), at: CGPoint(x: point.x + 6, y: point.y - 16), color: color.withAlphaComponent(0.85))
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
            .backgroundColor: NSColor.black.withAlphaComponent(0.58),
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: point)
    }

    private func drawDraftPreviewIfNeeded(for measurement: MeasurementPolygon, on page: PDFPage, color: NSColor) {
        guard overlayState.draftMeasurement?.id == measurement.id else { return }
        guard let lastPoint = measurement.points.last?.cgPoint else { return }
        guard let hoverPoint = hoverPagePoint, hoverPageIndex == overlayState.pageIndex else { return }

        let previewPath = NSBezierPath()
        previewPath.lineJoinStyle = .round
        previewPath.lineCapStyle = .round
        previewPath.setLineDash([8, 6], count: 2, phase: 0)
        previewPath.move(to: convert(lastPoint, from: page))
        previewPath.line(to: convert(hoverPoint, from: page))
        strokePath(previewPath, color: color.withAlphaComponent(0.98), lineWidth: 4.2)
    }

    private func polygonFillPath(for measurement: MeasurementPolygon, on page: PDFPage, includeHoverPreview: Bool) -> NSBezierPath? {
        guard measurement.kind == .polygon else { return nil }

        var fillPoints = measurement.points.map { convert($0.cgPoint, from: page) }
        if includeHoverPreview,
           let hoverPoint = hoverPagePoint,
           hoverPageIndex == overlayState.pageIndex,
           fillPoints.count >= 2 {
            fillPoints.append(convert(hoverPoint, from: page))
        }

        guard fillPoints.count >= 3 else { return nil }

        let fillPath = NSBezierPath()
        fillPath.lineJoinStyle = .round
        fillPath.lineCapStyle = .round
        fillPath.move(to: fillPoints[0])
        for point in fillPoints.dropFirst() {
            fillPath.line(to: point)
        }
        fillPath.close()
        return fillPath
    }

    private func strokeWidth(for measurement: MeasurementPolygon, isSelected: Bool, isDraft: Bool) -> CGFloat {
        switch measurement.kind {
        case .distance:
            return isDraft ? 5.2 : (isSelected ? 4.8 : 4.0)
        case .path:
            return isDraft ? 5.4 : (isSelected ? 4.9 : 4.2)
        case .polygon:
            return isDraft ? 5.8 : (isSelected ? 5.0 : 4.4)
        }
    }

    private func strokePath(_ path: NSBezierPath, color: NSColor, lineWidth: CGFloat) {
        let originalWidth = path.lineWidth
        NSColor.black.withAlphaComponent(0.72).setStroke()
        path.lineWidth = lineWidth + 6
        path.stroke()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = lineWidth + 3
        path.stroke()

        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
        path.lineWidth = originalWidth
    }

    private func overlayColor(
        for measurement: MeasurementPolygon,
        isSelected: Bool,
        isDraft: Bool,
        isInvalid: Bool
    ) -> NSColor {
        if measurement.kind == .polygon, isInvalid {
            return OverlayPalette.invalidPolygon
        }
        if isDraft {
            switch measurement.kind {
            case .distance:
                return OverlayPalette.draftDistance
            case .path:
                return OverlayPalette.draftPath
            case .polygon:
                return OverlayPalette.draftPolygon
            }
        }
        if isSelected {
            switch measurement.kind {
            case .distance:
                return OverlayPalette.selectedDistance
            case .path:
                return OverlayPalette.selectedPath
            case .polygon:
                return OverlayPalette.selectedPolygon
            }
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

    private func convert(rect: CGRect, from page: PDFPage) -> CGRect {
        let topLeft = convert(CGPoint(x: rect.minX, y: rect.maxY), from: page)
        let bottomRight = convert(CGPoint(x: rect.maxX, y: rect.minY), from: page)
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    private func shouldCloseDraft(at viewPoint: CGPoint) -> Bool {
        guard let draft = overlayState.draftMeasurement, draft.kind == .polygon, draft.points.count >= 3 else { return false }
        guard let currentPage else { return false }
        guard let first = draft.points.first else { return false }
        let firstViewPoint = convert(first.cgPoint, from: currentPage)
        return hypot(viewPoint.x - firstViewPoint.x, viewPoint.y - firstViewPoint.y) < 14
    }

    private func hitMeasurement(at viewPoint: CGPoint) -> UUID? {
        guard let currentPage else { return nil }
        var best: (UUID, Double)?
        for measurement in overlayState.measurements {
            let points = measurement.points.map { convert($0.cgPoint, from: currentPage) }
            guard points.count > 1 else { continue }
            let segmentCount = measurement.kind == .polygon && measurement.isClosed ? points.count : points.count - 1
            for index in 0..<segmentCount {
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let distance = GeometryEngine.pointDistanceToSegment(viewPoint, segmentStart: start, segmentEnd: end)
                if distance < 12, distance < (best?.1 ?? .greatestFiniteMagnitude) {
                    best = (measurement.id, distance)
                }
            }
        }
        return best?.0
    }

    private func hitVertex(at viewPoint: CGPoint) -> (measurementID: UUID, pointID: UUID)? {
        guard let currentPage else { return nil }
        var best: (UUID, UUID, Double)?
        for measurement in overlayState.measurements {
            for point in measurement.points {
                let converted = convert(point.cgPoint, from: currentPage)
                let distance = Double(hypot(converted.x - viewPoint.x, converted.y - viewPoint.y))
                if distance < 10, distance < (best?.2 ?? .greatestFiniteMagnitude) {
                    best = (measurement.id, point.id, distance)
                }
            }
        }
        if let best {
            return (best.0, best.1)
        }
        return nil
    }

    private func hitSegment(at viewPoint: CGPoint) -> (measurementID: UUID, segmentIndex: Int)? {
        guard let currentPage else { return nil }
        var best: (UUID, Int, Double)?
        for measurement in overlayState.measurements {
            let points = measurement.points.map { convert($0.cgPoint, from: currentPage) }
            guard points.count > 1 else { continue }
            let segmentCount = measurement.kind == .polygon && measurement.isClosed ? points.count : points.count - 1
            for index in 0..<segmentCount {
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let distance = GeometryEngine.pointDistanceToSegment(viewPoint, segmentStart: start, segmentEnd: end)
                if distance < 10, distance < (best?.2 ?? .greatestFiniteMagnitude) {
                    best = (measurement.id, index, distance)
                }
            }
        }
        if let best {
            return (best.0, best.1)
        }
        return nil
    }
}
