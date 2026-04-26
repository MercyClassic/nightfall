//
//  SideToolbarView.swift
//  Nightfall
//

import AppKit

final class SideToolbarView: NSView {

    private let tools: [Tool]
    private let onToolSelected: (Tool) -> Void
    private var buttons: [Tool: ToolButton] = [:]
    private var activeTool: Tool?
    private var accentColor: NSColor = .systemRed

    private let buttonSize: CGFloat = 30
    private let padding: CGFloat = 5

    init(tools: [Tool], onToolSelected: @escaping (Tool) -> Void) {
        self.tools = tools
        self.onToolSelected = onToolSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 4
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        NSSize(width:  buttonSize + padding * 2,
               height: CGFloat(tools.count) * buttonSize
                     + CGFloat(tools.count - 1) * 2
                     + padding * 2)
    }

    private func build() {
        var y = padding
        for tool in tools.reversed() {
            let btn = ToolButton(tool: tool) { [weak self] in
                self?.onToolSelected(tool)
            }
            btn.frame = NSRect(x: padding, y: y, width: buttonSize, height: buttonSize)
            addSubview(btn)
            buttons[tool] = btn
            y += buttonSize + 2
        }
    }

    func setActiveTool(_ tool: Tool?) {
        activeTool = tool
        for (t, btn) in buttons {
            btn.isActive = (t == tool)
            btn.accentColor = accentColor
            btn.needsDisplay = true
        }
    }

    func setAccentColor(_ color: NSColor) {
        accentColor = color
        for btn in buttons.values {
            btn.accentColor = color
            btn.needsDisplay = true
        }
    }
}

// MARK: - ToolButton

final class ToolButton: NSView {

    let tool: Tool
    private let onClick: () -> Void
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    var isActive = false { didSet { needsDisplay = true } }
    var accentColor: NSColor = .systemBlue { didSet { needsDisplay = true } }

    init(tool: Tool, onClick: @escaping () -> Void) {
        self.tool = tool
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = tool.tooltip
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited,
                                          .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onClick() }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor
        if isActive {
            bgColor = accentColor.withAlphaComponent(0.22)
        } else if hovering {
            bgColor = NSColor(calibratedWhite: 0.82, alpha: 1.0)
        } else {
            bgColor = .clear
        }
        bgColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                     xRadius: 4, yRadius: 4).fill()

        let symbol = tool.iconSymbol
        let iconSize: CGFloat = 15
        let tint: NSColor = isActive
            ? accentColor
            : NSColor(calibratedWhite: 0.25, alpha: 1.0)

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            let configured = img.withSymbolConfiguration(cfg) ?? img
            let tinted = tintedImage(configured, color: tint)
            let r = NSRect(x: (bounds.width - iconSize) / 2,
                           y: (bounds.height - iconSize) / 2,
                           width: iconSize, height: iconSize)
            tinted.draw(in: r)
        } else {
            let ch = String(tool.tooltip.prefix(1))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: tint
            ]
            let s = NSAttributedString(string: ch, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: (bounds.width  - size.width)  / 2,
                               y: (bounds.height - size.height) / 2))
        }

        if tool == .colorPicker {
            let dotRect = NSRect(x: bounds.width - 10, y: 4, width: 6, height: 6)
            accentColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
