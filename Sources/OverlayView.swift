//
//  OverlayView.swift
//  Nightfall
//

import AppKit

final class OverlayView: NSView {

    weak var window_: OverlayWindow?

    private let capture: ScreenCapture
    private let backgroundImage: NSImage
    private let backgroundCGImage: CGImage

    // MARK: - Capture mode (area / window)

    private let mode: CaptureMode
    private let availableWindows: [WindowInfo]
    private var hoveredWindow: WindowInfo?

    // MARK: - Selection state

    enum State {
        case idle                 // no selection yet
        case selecting            // dragging out the rectangle
        case editing              // selection done, picking a tool / drawing
        case drawing              // currently drawing
        case movingSelection
        case resizingSelection(ResizeHandle)
        case editingText(TextAnnotation)
    }

    enum ResizeHandle {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private(set) var state: State = .idle
    private(set) var selection: NSRect? = nil

    // MARK: - Drawing state

    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var activeTool: Tool? = nil

    // Per-tool color memory: marker stays yellow, others stay red, etc.
    private var drawingColor: NSColor = .systemRed
    private var markerColor:  NSColor = NSColor(red: 0.98, green: 0.80,
                                                blue: 0.16, alpha: 1.0) // yellow
    private var currentLineWidth: CGFloat = 4.0

    private var currentColor: NSColor {
        activeTool == .marker ? markerColor : drawingColor
    }

    // MARK: - UI subviews

    private var sideToolbar: SideToolbarView?
    private var bottomToolbar: BottomToolbarView?
    private var colorPaletteView: ColorPaletteView?
    private var strokeWidthPaletteView: StrokeWidthPaletteView?
    private var textFieldView: NSTextField?

    // MARK: - Interaction tracking

    private var dragStart: NSPoint = .zero
    private var dragOffset: NSSize = .zero
    private var selectionAtDragStart: NSRect = .zero
    private var trackingArea: NSTrackingArea?
    private var cursorPosition: NSPoint = .zero
    private var didDragSinceMouseDown = false

    // MARK: - Init

    init(capture: ScreenCapture,
         mode: CaptureMode,
         windows: [WindowInfo]) {
        self.capture = capture
        self.backgroundImage = capture.image
        self.backgroundCGImage = capture.cgImage
        self.mode = mode
        self.availableWindows = windows
        super.init(frame: NSRect(origin: .zero, size: capture.frame.size))
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways,
                                            .mouseEnteredAndExited,
                                            .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Background screenshot.
        backgroundImage.draw(in: bounds,
                             from: .zero,
                             operation: .copy,
                             fraction: 1.0)

        // 2. Dim layer with cut-out for selection (or hovered window in window mode).
        let dimColor = NSColor.black.withAlphaComponent(0.45)
        ctx.saveGState()
        ctx.setFillColor(dimColor.cgColor)
        let cutout = selection ?? hoveredWindowRectInView()
        if let r = cutout {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(r)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }
        ctx.restoreGState()

        // 3. Plain crosshairs while waiting for first input.
        if selection == nil {
            drawCrosshair(in: ctx)
        }

        // 4. Selection / hovered-window chrome.
        if let sel = selection {
            drawSelectionChrome(sel, in: ctx, withHandles: true)
        } else if let hover = hoveredWindowRectInView() {
            drawSelectionChrome(hover, in: ctx, withHandles: false)
        }

        // 5. Annotations — drawn UNCLIPPED so the user can scribble freely
        //    across the boundary. Export still crops to the selection.
        for ann in annotations { ann.draw(in: ctx) }
        currentAnnotation?.draw(in: ctx)
    }

    private func drawCrosshair(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        let x = cursorPosition.x, y = cursorPosition.y
        ctx.beginPath()
        ctx.move(to: NSPoint(x: 0, y: y))
        ctx.addLine(to: NSPoint(x: bounds.width, y: y))
        ctx.move(to: NSPoint(x: x, y: 0))
        ctx.addLine(to: NSPoint(x: x, y: bounds.height))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawSelectionChrome(_ rect: NSRect,
                                     in ctx: CGContext,
                                     withHandles: Bool) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
        ctx.restoreGState()

        if withHandles, !isDrawingState {
            drawResizeHandles(rect, in: ctx)
        }
        drawDimensionsLabel(rect, in: ctx)
    }

    private var isDrawingState: Bool {
        switch state {
        case .drawing, .editingText: return true
        default: return false
        }
    }

    private func drawResizeHandles(_ sel: NSRect, in ctx: CGContext) {
        let points = resizePoints(for: sel)
        let s: CGFloat = 7
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        for p in points.values {
            let r = NSRect(x: p.x - s/2, y: p.y - s/2, width: s, height: s)
            ctx.fill(r); ctx.stroke(r)
        }
        ctx.restoreGState()
    }

    private func resizePoints(for sel: NSRect) -> [ResizeHandle: NSPoint] {
        [
            .bottomLeft:  NSPoint(x: sel.minX, y: sel.minY),
            .bottom:      NSPoint(x: sel.midX, y: sel.minY),
            .bottomRight: NSPoint(x: sel.maxX, y: sel.minY),
            .right:       NSPoint(x: sel.maxX, y: sel.midY),
            .topRight:    NSPoint(x: sel.maxX, y: sel.maxY),
            .top:         NSPoint(x: sel.midX, y: sel.maxY),
            .topLeft:     NSPoint(x: sel.minX, y: sel.maxY),
            .left:        NSPoint(x: sel.minX, y: sel.midY),
        ]
    }

    private func drawDimensionsLabel(_ sel: NSRect, in ctx: CGContext) {
        let scale = window?.backingScaleFactor ?? 1.0
        let wPx = Int(sel.width * scale), hPx = Int(sel.height * scale)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: "\(wPx) × \(hPx)", attributes: attrs)
        let size = attributed.size()
        let pad: CGFloat = 6
        var labelRect = NSRect(x: sel.minX, y: sel.maxY + 6,
                               width: size.width + pad * 2,
                               height: size.height + pad)
        if labelRect.maxY > bounds.height - 4 {
            labelRect.origin.y = sel.maxY - labelRect.height - 6
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        attributed.draw(at: NSPoint(x: labelRect.minX + pad,
                                    y: labelRect.minY + pad / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func hoveredWindowRectInView() -> NSRect? {
        guard mode == .window, selection == nil,
              let hover = hoveredWindow else { return nil }
        // Convert AppKit-global rect to our view coords (clamp to screen).
        let local = NSRect(x: hover.appKitBounds.minX - capture.frame.origin.x,
                           y: hover.appKitBounds.minY - capture.frame.origin.y,
                           width: hover.appKitBounds.width,
                           height: hover.appKitBounds.height)
        return local.intersection(bounds)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        cursorPosition = convert(event.locationInWindow, from: nil)
        if mode == .window && selection == nil {
            updateHoveredWindow(at: cursorPosition)
        }
        if selection == nil { needsDisplay = true }
        updateCursor()
    }

    private func updateHoveredWindow(at point: NSPoint) {
        let global = NSPoint(x: capture.frame.origin.x + point.x,
                             y: capture.frame.origin.y + point.y)
        hoveredWindow = WindowDetector.windowAt(global, in: availableWindows)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        didDragSinceMouseDown = false

        // Commit any active text edit.
        if case .editingText = state { commitTextEditing() }

        if let sel = selection {
            if let handle = resizeHandle(at: point, in: sel) {
                state = .resizingSelection(handle)
                selectionAtDragStart = sel
                return
            }
            if let tool = activeTool {
                // Start drawing — even if the click is outside the selection.
                beginDrawing(with: tool, at: point)
                return
            }
            if sel.contains(point) {
                state = .movingSelection
                dragOffset = NSSize(width: point.x - sel.minX,
                                    height: point.y - sel.minY)
                return
            }
            // Click outside the selection with no tool active: do NOTHING.
            // (Don't reset the screenshot — user requirement.)
            return
        }

        // No selection yet.
        if mode == .window {
            // Window mode: a click on a window commits it as the selection.
            if let hover = hoveredWindow {
                let r = hoveredWindowRectInView() ?? .zero
                if r.width >= 4, r.height >= 4 {
                    selection = r
                    hoveredWindow = nil
                    state = .editing
                    setupToolbars()
                    needsDisplay = true
                    _ = hover // silence unused
                }
            }
            // Click on empty space in window mode: do nothing (or Esc).
            return
        }

        // Area mode: start dragging out a fresh selection.
        state = .selecting
        selection = NSRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPosition = point
        didDragSinceMouseDown = true

        switch state {
        case .selecting:
            selection = NSRect.fromPoints(dragStart, point).intersection(bounds)
            hideToolbars()
            needsDisplay = true

        case .movingSelection:
            if var sel = selection {
                sel.origin = NSPoint(x: point.x - dragOffset.width,
                                     y: point.y - dragOffset.height)
                sel = clampToBounds(sel)
                selection = sel
                repositionToolbars()
                needsDisplay = true
            }

        case .resizingSelection(let handle):
            selection = resizedRect(from: selectionAtDragStart,
                                    handle: handle,
                                    to: point).intersection(bounds)
            repositionToolbars()
            needsDisplay = true

        case .drawing:
            updateDrawing(to: point)
            needsDisplay = true

        default: break
        }
        updateCursor()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch state {
        case .selecting:
            if let sel = selection, sel.width > 2, sel.height > 2 {
                state = .editing
                setupToolbars()
            } else {
                selection = nil
                state = .idle
            }
        case .drawing:
            finishDrawing(at: point)
            state = .editing
        case .movingSelection, .resizingSelection:
            state = .editing
            setupToolbars()
        default: break
        }
        needsDisplay = true
        updateCursor()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Esc
        if event.keyCode == 53 {
            if case .editingText = state { cancelTextEditing(); return }
            window_?.requestFinish()
            return
        }
        // Return / Enter
        if event.keyCode == 36 || event.keyCode == 76 {
            if case .editingText = state { commitTextEditing(); return }
            if selection != nil { saveToFile() }
            return
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copyToClipboard(); return
            case "s": saveToFile();      return
            case "z":
                if event.modifierFlags.contains(.shift) { redo() } else { undo() }
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Cursor

    private func updateCursor() {
        if selection == nil {
            NSCursor.crosshair.set(); return
        }
        if let sel = selection, let handle = resizeHandle(at: cursorPosition, in: sel) {
            switch handle {
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .left, .right: NSCursor.resizeLeftRight.set()
            default:            NSCursor.crosshair.set()
            }
            return
        }
        if activeTool != nil { NSCursor.crosshair.set(); return }
        if let sel = selection, sel.contains(cursorPosition) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Resize

    private func resizeHandle(at point: NSPoint, in sel: NSRect) -> ResizeHandle? {
        let tolerance: CGFloat = 10
        for (h, p) in resizePoints(for: sel) {
            if abs(p.x - point.x) <= tolerance && abs(p.y - point.y) <= tolerance {
                return h
            }
        }
        return nil
    }

    private func resizedRect(from rect: NSRect,
                             handle: ResizeHandle,
                             to point: NSPoint) -> NSRect {
        var r = rect
        switch handle {
        case .topLeft:
            r.size.width  = r.maxX - point.x
            r.size.height = point.y - r.minY
            r.origin.x    = point.x
        case .top:
            r.size.height = point.y - r.minY
        case .topRight:
            r.size.width  = point.x - r.minX
            r.size.height = point.y - r.minY
        case .right:
            r.size.width  = point.x - r.minX
        case .bottomRight:
            let top = r.maxY
            r.size.width  = point.x - r.minX
            r.origin.y    = point.y
            r.size.height = top - point.y
        case .bottom:
            let top = r.maxY
            r.origin.y    = point.y
            r.size.height = top - point.y
        case .bottomLeft:
            let top = r.maxY
            r.size.width  = r.maxX - point.x
            r.origin.x    = point.x
            r.origin.y    = point.y
            r.size.height = top - point.y
        case .left:
            r.size.width  = r.maxX - point.x
            r.origin.x    = point.x
        }
        if r.width  < 4 { r.size.width  = 4 }
        if r.height < 4 { r.size.height = 4 }
        return r
    }

    private func clampToBounds(_ r: NSRect) -> NSRect {
        var r = r
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > bounds.width  { r.origin.x = bounds.width  - r.width  }
        if r.maxY > bounds.height { r.origin.y = bounds.height - r.height }
        return r
    }

    // MARK: - Toolbars

    private func setupToolbars() {
        if sideToolbar == nil {
            let side = SideToolbarView(tools: [.pencil, .line, .arrow,
                                               .rectangle, .marker, .blur,
                                               .text, .colorPicker]) {
                [weak self] tool in self?.handleToolSelected(tool)
            }
            addSubview(side)
            sideToolbar = side
        }
        if bottomToolbar == nil {
            let bottom = BottomToolbarView(
                onSave:  { [weak self] in self?.saveToFile() },
                onCopy:  { [weak self] in self?.copyToClipboard() },
                onClose: { [weak self] in self?.window_?.requestFinish() },
                onUndo:  { [weak self] in self?.undo() },
                onRedo:  { [weak self] in self?.redo() }
            )
            addSubview(bottom)
            bottomToolbar = bottom
        }
        sideToolbar?.isHidden = false
        bottomToolbar?.isHidden = false
        refreshToolbarAccents()
        repositionToolbars()
    }

    private func hideToolbars() {
        sideToolbar?.isHidden = true
        bottomToolbar?.isHidden = true
        colorPaletteView?.isHidden = true
        strokeWidthPaletteView?.isHidden = true
    }

    private func teardownToolbars() {
        sideToolbar?.removeFromSuperview();   sideToolbar = nil
        bottomToolbar?.removeFromSuperview(); bottomToolbar = nil
        colorPaletteView?.removeFromSuperview(); colorPaletteView = nil
        strokeWidthPaletteView?.removeFromSuperview(); strokeWidthPaletteView = nil
    }

    private func refreshToolbarAccents() {
        sideToolbar?.setAccentColor(currentColor)
        sideToolbar?.setActiveTool(activeTool)
        strokeWidthPaletteView?.setAccent(currentColor)
    }

    private func repositionToolbars() {
        guard let sel = selection else { return }
        sideToolbar?.isHidden = false
        bottomToolbar?.isHidden = false

        if let side = sideToolbar {
            let size = side.fittingSize
            var x = sel.maxX + 8
            if x + size.width > bounds.width - 4 {
                x = sel.minX - size.width - 8
            }
            if x < 4 { x = max(4, sel.maxX - size.width - 4) }
            var y = sel.maxY - size.height
            if y < 4 { y = 4 }
            if y + size.height > bounds.height - 4 {
                y = bounds.height - size.height - 4
            }
            side.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        if let bottom = bottomToolbar {
            let size = bottom.fittingSize
            var x = sel.maxX - size.width
            if x < 4 { x = 4 }
            if x + size.width > bounds.width - 4 {
                x = bounds.width - size.width - 4
            }
            var y = sel.minY - size.height - 8
            if y < 4 { y = sel.minY + 8 }
            bottom.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        if let palette = colorPaletteView, let side = sideToolbar {
            let size = palette.fittingSize
            var x = side.frame.minX - size.width - 6
            if x < 4 { x = side.frame.maxX + 6 }
            let y = side.frame.maxY - size.height
            palette.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            palette.isHidden = false
        }

        if let palette = strokeWidthPaletteView, let side = sideToolbar {
            let size = palette.fittingSize
            var x = side.frame.minX - size.width - 6
            if let color = colorPaletteView, !color.isHidden {
                x = color.frame.minX - size.width - 6
                if x < 4 { x = color.frame.maxX + 6 }
            }
            if x < 4 { x = side.frame.maxX + 6 }
            let y = side.frame.maxY - size.height
            palette.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            palette.isHidden = false
        }
    }

    // MARK: - Tool selection

    private func handleToolSelected(_ tool: Tool) {
        if tool == .colorPicker {
            toggleColorPalette()
            return
        }
        // Re-clicking the active tool deselects it: the user can then drag /
        // resize the selection without drawing anything.
        if activeTool == tool {
            activeTool = nil
            sideToolbar?.setActiveTool(nil)
            removeStrokeWidthPalette()
            colorPaletteView?.removeFromSuperview()
            colorPaletteView = nil
            updateCursor()
            return
        }

        activeTool = tool
        sideToolbar?.setActiveTool(tool)
        sideToolbar?.setAccentColor(currentColor)

        // Show stroke-width palette only for tools that use it.
        if tool.usesStrokeWidth {
            ensureStrokeWidthPalette()
        } else {
            removeStrokeWidthPalette()
        }
        strokeWidthPaletteView?.setAccent(currentColor)

        colorPaletteView?.removeFromSuperview()
        colorPaletteView = nil
        updateCursor()
    }

    private func toggleColorPalette() {
        if colorPaletteView != nil {
            colorPaletteView?.removeFromSuperview()
            colorPaletteView = nil
            return
        }
        let palette = ColorPaletteView(selected: currentColor) { [weak self] color in
            guard let self = self else { return }
            if self.activeTool == .marker {
                self.markerColor = color
            } else {
                self.drawingColor = color
            }
            self.refreshToolbarAccents()
            self.colorPaletteView?.removeFromSuperview()
            self.colorPaletteView = nil
        }
        addSubview(palette)
        colorPaletteView = palette
        repositionToolbars()
    }

    private func ensureStrokeWidthPalette() {
        if strokeWidthPaletteView != nil { return }
        let palette = StrokeWidthPaletteView(selected: currentLineWidth,
                                             accent: currentColor) {
            [weak self] w in self?.currentLineWidth = w
        }
        addSubview(palette)
        strokeWidthPaletteView = palette
        repositionToolbars()
    }

    private func removeStrokeWidthPalette() {
        strokeWidthPaletteView?.removeFromSuperview()
        strokeWidthPaletteView = nil
    }

    // MARK: - Drawing

    private func beginDrawing(with tool: Tool, at point: NSPoint) {
        state = .drawing
        switch tool {
        case .pencil:
            let p = PencilAnnotation(color: currentColor, lineWidth: currentLineWidth)
            p.add(point: point); currentAnnotation = p
        case .line:
            currentAnnotation = LineAnnotation(start: point, end: point,
                                               color: currentColor,
                                               lineWidth: currentLineWidth)
        case .arrow:
            currentAnnotation = ArrowAnnotation(start: point, end: point,
                                                color: currentColor,
                                                lineWidth: max(currentLineWidth, 2.5))
        case .rectangle:
            currentAnnotation = RectangleAnnotation(rect: NSRect(origin: point, size: .zero),
                                                    color: currentColor,
                                                    lineWidth: currentLineWidth)
        case .marker:
            let m = MarkerAnnotation(color: currentColor,
                                     lineWidth: currentLineWidth * 4)
            m.add(point: point); currentAnnotation = m
        case .blur:
            currentAnnotation = BlurAnnotation(rect: NSRect(origin: point, size: .zero),
                                               source: backgroundCGImage,
                                               sourceBounds: bounds)
        case .text:
            startTextEditing(at: point)
        case .colorPicker: break
        }
        hideToolbars()
    }

    private func updateDrawing(to point: NSPoint) {
        guard let ann = currentAnnotation else { return }
        switch ann {
        case let p as PencilAnnotation: p.add(point: point)
        case let m as MarkerAnnotation: m.add(point: point)
        case let l as LineAnnotation:   l.end = point
        case let a as ArrowAnnotation:  a.end = point
        case let r as RectangleAnnotation:
            r.rect = NSRect.fromPoints(dragStart, point)
        case let b as BlurAnnotation:
            b.rect = NSRect.fromPoints(dragStart, point)
        default: break
        }
    }

    private func finishDrawing(at point: NSPoint) {
        if let ann = currentAnnotation {
            // Discard zero-size shapes (accidental clicks).
            switch ann {
            case let r as RectangleAnnotation where r.rect.width < 2 || r.rect.height < 2:
                break
            case let b as BlurAnnotation where b.rect.width < 4 || b.rect.height < 4:
                break
            default:
                annotations.append(ann)
                redoStack.removeAll()
            }
        }
        currentAnnotation = nil
        setupToolbars()
    }

    private func undo() {
        guard !annotations.isEmpty else { return }
        redoStack.append(annotations.removeLast())
        needsDisplay = true
    }

    private func redo() {
        guard !redoStack.isEmpty else { return }
        annotations.append(redoStack.removeLast())
        needsDisplay = true
    }

    // MARK: - Text editing

    private func startTextEditing(at point: NSPoint) {
        let tf = NSTextField(frame: NSRect(x: point.x,
                                           y: point.y - 28,
                                           width: 200, height: 28))
        tf.isBordered = false
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        tf.textColor = currentColor
        tf.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        tf.focusRingType = .none
        tf.isBezeled = false
        tf.drawsBackground = true
        tf.placeholderString = "Text"
        tf.delegate = self
        tf.target = self
        tf.action = #selector(textFieldDidFinish(_:))
        addSubview(tf)
        window?.makeFirstResponder(tf)
        textFieldView = tf

        let pending = TextAnnotation(origin: point, text: "",
                                     color: currentColor, fontSize: 20)
        state = .editingText(pending)
        currentAnnotation = pending
        hideToolbars()
    }

    @objc private func textFieldDidFinish(_ sender: NSTextField) {
        commitTextEditing()
    }

    private func commitTextEditing() {
        guard case let .editingText(ann) = state else { return }
        if let tf = textFieldView {
            ann.text = tf.stringValue
            tf.removeFromSuperview()
        }
        if !ann.text.isEmpty {
            annotations.append(ann)
            redoStack.removeAll()
        }
        currentAnnotation = nil
        textFieldView = nil
        state = .editing
        setupToolbars()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelTextEditing() {
        textFieldView?.removeFromSuperview()
        textFieldView = nil
        currentAnnotation = nil
        state = .editing
        setupToolbars()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Export

    private func renderSelectionImage() -> NSImage? {
        guard let sel = selection else { return nil }
        let scale = window?.backingScaleFactor ?? 2.0
        let pxW = Int(sel.width  * scale)
        let pxH = Int(sel.height * scale)
        guard pxW > 0, pxH > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: pxW, height: pxH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -sel.origin.x, y: -sel.origin.y)

        // Background — draw the entire screen capture in view coords.
        ctx.draw(backgroundCGImage, in: bounds)

        // Annotations clipped to selection (anything drawn outside is cropped).
        ctx.saveGState()
        ctx.clip(to: sel)
        for ann in annotations { ann.draw(in: ctx) }
        ctx.restoreGState()

        guard let cgOut = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgOut, size: sel.size)
    }

    private func saveToFile() {
        guard let image = renderSelectionImage(),
              let data  = pngData(from: image) else { NSSound.beep(); return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultFilename()
        panel.canCreateDirectories = true
        panel.title = "Save Screenshot"

        let saveWindow = self.window
        saveWindow?.level = .normal

        panel.begin { [weak self] response in
            saveWindow?.level = .screenSaver
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                    self?.window_?.requestFinish()
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func copyToClipboard() {
        guard let image = renderSelectionImage() else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        window_?.requestFinish()
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func defaultFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(f.string(from: Date())).png"
    }
}

// MARK: - NSTextFieldDelegate

extension OverlayView: NSTextFieldDelegate {
    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing(); return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing(); return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            let size = (tf.stringValue as NSString).size(withAttributes: [
                .font: tf.font ?? NSFont.systemFont(ofSize: 20)
            ])
            var f = tf.frame
            f.size.width = max(120, size.width + 20)
            tf.frame = f
        }
    }
}

// MARK: - NSRect helpers

extension NSRect {
    static func fromPoints(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width:  abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
