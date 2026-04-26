//
//  BottomToolbarView.swift
//  Nightfall
//

import AppKit

final class BottomToolbarView: NSView {

    private struct Action {
        let symbol: String
        let tooltip: String
        let tint: NSColor
        let callback: () -> Void
    }

    private let actions: [Action]
    private let buttonSize: CGFloat = 30
    private let padding: CGFloat = 5

    init(onSave:  @escaping () -> Void,
         onCopy:  @escaping () -> Void,
         onClose: @escaping () -> Void,
         onUndo:  @escaping () -> Void,
         onRedo:  @escaping () -> Void) {

        self.actions = [
            Action(symbol: "arrow.uturn.backward",
                   tooltip: "Undo  (⌘Z)",
                   tint: NSColor(calibratedWhite: 0.25, alpha: 1.0),
                   callback: onUndo),
            Action(symbol: "arrow.uturn.forward",
                   tooltip: "Redo  (⌘⇧Z)",
                   tint: NSColor(calibratedWhite: 0.25, alpha: 1.0),
                   callback: onRedo),
            Action(symbol: "arrow.down.to.line",
                   tooltip: "Save  (⌘S)",
                   tint: NSColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 1.0),
                   callback: onSave),
            Action(symbol: "doc.on.doc",
                   tooltip: "Copy  (⌘C)",
                   tint: NSColor(red: 0.3, green: 0.65, blue: 0.35, alpha: 1.0),
                   callback: onCopy),
            Action(symbol: "xmark",
                   tooltip: "Close  (Esc)",
                   tint: NSColor(red: 0.85, green: 0.35, blue: 0.3, alpha: 1.0),
                   callback: onClose),
        ]

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
        NSSize(width:  CGFloat(actions.count) * buttonSize
                     + CGFloat(actions.count - 1) * 2
                     + padding * 2,
               height: buttonSize + padding * 2)
    }

    private func build() {
        var x = padding
        for action in actions {
            let btn = ActionButton(symbol: action.symbol,
                                   tint: action.tint,
                                   onClick: action.callback)
            btn.toolTip = action.tooltip
            btn.frame = NSRect(x: x, y: padding,
                               width: buttonSize, height: buttonSize)
            addSubview(btn)
            x += buttonSize + 2
        }
    }
}

private final class ActionButton: NSView {
    private let symbol: String
    private let tint: NSColor
    private let onClick: () -> Void
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(symbol: String, tint: NSColor, onClick: @escaping () -> Void) {
        self.symbol = symbol; self.tint = tint; self.onClick = onClick
        super.init(frame: .zero); wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited,
                                          .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta); trackingArea = ta
    }
    override func mouseEntered(with event: NSEvent) { hovering = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onClick() }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor(calibratedWhite: 0.82, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                         xRadius: 4, yRadius: 4).fill()
        }
        let iconSize: CGFloat = 14
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            let configured = img.withSymbolConfiguration(cfg) ?? img
            let tinted = tinted(configured)
            let r = NSRect(x: (bounds.width  - iconSize) / 2,
                           y: (bounds.height - iconSize) / 2,
                           width: iconSize, height: iconSize)
            tinted.draw(in: r)
        }
    }

    private func tinted(_ image: NSImage) -> NSImage {
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        tint.set()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
