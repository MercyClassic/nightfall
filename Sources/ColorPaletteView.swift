//
//  ColorPaletteView.swift
//  Nightfall
//

import AppKit

final class ColorPaletteView: NSView {

    private let swatches: [NSColor] = [
        .black,
        .white,
        NSColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1.0), // red
        NSColor(red: 0.98, green: 0.55, blue: 0.10, alpha: 1.0), // orange
        NSColor(red: 0.98, green: 0.80, blue: 0.16, alpha: 1.0), // yellow
        NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1.0), // green
        NSColor(red: 0.18, green: 0.45, blue: 0.92, alpha: 1.0), // blue
        NSColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1.0), // purple
    ]

    private var selected: NSColor
    private let onPick: (NSColor) -> Void
    private let swatchSize: CGFloat = 22
    private let padding: CGFloat = 6
    private let spacing: CGFloat = 4

    init(selected: NSColor, onPick: @escaping (NSColor) -> Void) {
        self.selected = selected
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
        let count = CGFloat(swatches.count)
        return NSSize(width:  swatchSize + padding * 2,
                      height: count * swatchSize + (count - 1) * spacing + padding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, color) in swatches.enumerated() {
            let r = swatchRect(at: i)
            let path = NSBezierPath(ovalIn: r)
            color.setFill()
            path.fill()

            // Light outline so white swatch stays visible.
            NSColor(calibratedWhite: 0.5, alpha: 0.6).setStroke()
            path.lineWidth = 0.5
            path.stroke()

            if isSameColor(color, selected) {
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: -3, dy: -3))
                ring.lineWidth = 2
                NSColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 1.0).setStroke()
                ring.stroke()
            }
        }
    }

    private func swatchRect(at index: Int) -> NSRect {
        let count = swatches.count
        let i = count - 1 - index   // top-down visually
        let y = padding + CGFloat(i) * (swatchSize + spacing)
        return NSRect(x: padding, y: y, width: swatchSize, height: swatchSize)
    }

    private func isSameColor(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let aa = a.usingColorSpace(.sRGB),
              let bb = b.usingColorSpace(.sRGB) else { return false }
        return abs(aa.redComponent   - bb.redComponent)   < 0.02 &&
               abs(aa.greenComponent - bb.greenComponent) < 0.02 &&
               abs(aa.blueComponent  - bb.blueComponent)  < 0.02
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, color) in swatches.enumerated() {
            if swatchRect(at: i).insetBy(dx: -2, dy: -2).contains(p) {
                selected = color
                needsDisplay = true
                onPick(color)
                return
            }
        }
    }
}
