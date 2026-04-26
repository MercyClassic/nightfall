//
//  StrokeWidthPaletteView.swift
//  Nightfall
//

import AppKit

final class StrokeWidthPaletteView: NSView {

    private let widths: [CGFloat] = [2, 4, 7, 11]
    private var selected: CGFloat
    private var accent: NSColor
    private let onPick: (CGFloat) -> Void

    private let cellSize: CGFloat = 22
    private let padding: CGFloat = 6
    private let spacing: CGFloat = 4

    init(selected: CGFloat, accent: NSColor, onPick: @escaping (CGFloat) -> Void) {
        self.selected = selected
        self.accent = accent
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 4
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        let count = CGFloat(widths.count)
        return NSSize(width:  cellSize + padding * 2,
                      height: count * cellSize + (count - 1) * spacing + padding * 2)
    }

    func setAccent(_ color: NSColor) {
        accent = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, w) in widths.enumerated() {
            let r = cellRect(at: i)
            let isActive = abs(w - selected) < 0.001

            if isActive {
                accent.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1),
                             xRadius: 4, yRadius: 4).fill()
            }

            // Dot whose diameter scales with the stroke width.
            let dotDiameter = min(cellSize - 6, max(4, w * 1.4))
            let dotRect = NSRect(x: r.midX - dotDiameter / 2,
                                 y: r.midY - dotDiameter / 2,
                                 width: dotDiameter,
                                 height: dotDiameter)
            (isActive ? accent : NSColor(calibratedWhite: 0.25, alpha: 1.0)).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func cellRect(at index: Int) -> NSRect {
        let count = widths.count
        let i = count - 1 - index
        let y = padding + CGFloat(i) * (cellSize + spacing)
        return NSRect(x: padding, y: y, width: cellSize, height: cellSize)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, w) in widths.enumerated() {
            if cellRect(at: i).contains(p) {
                selected = w
                needsDisplay = true
                onPick(w)
                return
            }
        }
    }
}
