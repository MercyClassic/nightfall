//
//  Annotation.swift
//  Nightfall
//

import AppKit
import CoreImage

enum Tool: Int, CaseIterable {
    case pencil
    case line
    case arrow
    case rectangle
    case marker        // semi-transparent highlighter
    case blur          // gaussian blur over a rect
    case text
    case colorPicker   // not a drawing tool itself

    var iconSymbol: String {
        switch self {
        case .pencil:      return "pencil"
        case .line:        return "line.diagonal"
        case .arrow:       return "arrow.up.right"
        case .rectangle:   return "rectangle"
        case .marker:      return "highlighter"
        case .blur:        return "drop.halffull"
        case .text:        return "textformat"
        case .colorPicker: return "paintpalette"
        }
    }

    var tooltip: String {
        switch self {
        case .pencil:      return "Pencil"
        case .line:        return "Line"
        case .arrow:       return "Arrow"
        case .rectangle:   return "Rectangle"
        case .marker:      return "Marker"
        case .blur:        return "Blur"
        case .text:        return "Text"
        case .colorPicker: return "Color"
        }
    }

    /// Whether the tool uses the configurable color from the palette.
    var usesColor: Bool {
        switch self {
        case .blur: return false
        default:    return true
        }
    }

    /// Whether the tool uses the configurable stroke width.
    var usesStrokeWidth: Bool {
        switch self {
        case .text, .blur: return false
        default:           return true
        }
    }
}

/// Coordinates are stored in the OverlayView's coordinate system
/// (AppKit, origin bottom-left).
protocol Annotation: AnyObject {
    var color: NSColor { get set }
    var lineWidth: CGFloat { get set }
    func draw(in context: CGContext)
    var boundingBox: NSRect { get }
}

// MARK: - Pencil

final class PencilAnnotation: Annotation {
    var color: NSColor
    var lineWidth: CGFloat
    var points: [NSPoint] = []

    init(color: NSColor, lineWidth: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
    }

    func add(point: NSPoint) { points.append(point) }

    func draw(in context: CGContext) {
        guard points.count > 1 else { return }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: points[0])
        for i in 1..<points.count { context.addLine(to: points[i]) }
        context.strokePath()
        context.restoreGState()
    }

    var boundingBox: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return NSRect(x: minX - lineWidth, y: minY - lineWidth,
                      width: (maxX - minX) + lineWidth * 2,
                      height: (maxY - minY) + lineWidth * 2)
    }
}

// MARK: - Line

final class LineAnnotation: Annotation {
    var color: NSColor
    var lineWidth: CGFloat
    var start: NSPoint
    var end: NSPoint

    init(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start; self.end = end
        self.color = color; self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    var boundingBox: NSRect {
        NSRect(x: min(start.x, end.x) - lineWidth,
               y: min(start.y, end.y) - lineWidth,
               width: abs(end.x - start.x) + lineWidth * 2,
               height: abs(end.y - start.y) + lineWidth * 2)
    }
}

// MARK: - Arrow

final class ArrowAnnotation: Annotation {
    var color: NSColor
    var lineWidth: CGFloat
    var start: NSPoint
    var end: NSPoint

    init(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start; self.end = end
        self.color = color; self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)

        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx)
        let headLength = max(12.0, lineWidth * 4)
        let headAngle: CGFloat = .pi / 7

        context.beginPath()
        context.move(to: start)
        let shortened = NSPoint(
            x: end.x - cos(angle) * (headLength * 0.5),
            y: end.y - sin(angle) * (headLength * 0.5)
        )
        context.addLine(to: shortened)
        context.strokePath()

        let p1 = NSPoint(x: end.x - headLength * cos(angle - headAngle),
                         y: end.y - headLength * sin(angle - headAngle))
        let p2 = NSPoint(x: end.x - headLength * cos(angle + headAngle),
                         y: end.y - headLength * sin(angle + headAngle))

        context.beginPath()
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }

    var boundingBox: NSRect {
        NSRect(x: min(start.x, end.x) - lineWidth - 10,
               y: min(start.y, end.y) - lineWidth - 10,
               width: abs(end.x - start.x) + lineWidth * 2 + 20,
               height: abs(end.y - start.y) + lineWidth * 2 + 20)
    }
}

// MARK: - Rectangle

final class RectangleAnnotation: Annotation {
    var color: NSColor
    var lineWidth: CGFloat
    var rect: NSRect

    init(rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect; self.color = color; self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    var boundingBox: NSRect { rect.insetBy(dx: -lineWidth, dy: -lineWidth) }
}

// MARK: - Marker

final class MarkerAnnotation: Annotation {
    var color: NSColor {
        didSet { _displayColor = color.withAlphaComponent(0.38) }
    }
    private var _displayColor: NSColor
    var lineWidth: CGFloat
    var points: [NSPoint] = []

    init(color: NSColor, lineWidth: CGFloat) {
        self.color = color
        self._displayColor = color.withAlphaComponent(0.38)
        self.lineWidth = lineWidth
    }

    func add(point: NSPoint) { points.append(point) }

    func draw(in context: CGContext) {
        guard points.count > 1 else { return }
        context.saveGState()
        context.setStrokeColor(_displayColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.square)
        context.setLineJoin(.round)
        context.setBlendMode(.multiply)
        context.beginPath()
        context.move(to: points[0])
        for i in 1..<points.count { context.addLine(to: points[i]) }
        context.strokePath()
        context.restoreGState()
    }

    var boundingBox: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return NSRect(x: minX - lineWidth, y: minY - lineWidth,
                      width: (maxX - minX) + lineWidth * 2,
                      height: (maxY - minY) + lineWidth * 2)
    }
}

// MARK: - Blur

final class BlurAnnotation: Annotation {
    var color: NSColor = .clear
    var lineWidth: CGFloat = 0
    var rect: NSRect

    private let source: CGImage
    private let sourceBounds: NSRect

    private var cachedRect: NSRect = .zero
    private var cachedImage: CGImage?

    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: nil)
    }()

    init(rect: NSRect, source: CGImage, sourceBounds: NSRect) {
        self.rect = rect
        self.source = source
        self.sourceBounds = sourceBounds
    }

    func draw(in context: CGContext) {
        guard rect.width > 1, rect.height > 1,
              sourceBounds.width > 0, sourceBounds.height > 0 else { return }

        if cachedImage == nil || cachedRect != rect {
            cachedImage = computeBlurredImage()
            cachedRect = rect
        }
        guard let img = cachedImage else { return }

        context.saveGState()
        context.draw(img, in: rect)
        // Subtle border so blurred regions are still visible against
        // similarly-blurred content underneath.
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        context.stroke(rect)
        context.restoreGState()
    }

    private func computeBlurredImage() -> CGImage? {
        let scaleX = CGFloat(source.width)  / sourceBounds.width
        let scaleY = CGFloat(source.height) / sourceBounds.height

        // Crop in CGImage (top-left origin) coords
        let pxRect = CGRect(
            x: rect.minX * scaleX,
            y: CGFloat(source.height) - rect.maxY * scaleY,
            width:  rect.width  * scaleX,
            height: rect.height * scaleY
        ).integral

        let imgWidth  = CGFloat(source.width)
        let imgHeight = CGFloat(source.height)
        let safe = pxRect.intersection(CGRect(x: 0, y: 0,
                                              width: imgWidth,
                                              height: imgHeight))
        guard safe.width >= 1, safe.height >= 1,
              let cropped = source.cropping(to: safe) else { return nil }

        let ci = CIImage(cgImage: cropped)
        let radius = max(8.0, min(rect.width, rect.height) / 12.0)

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return BlurAnnotation.ciContext.createCGImage(out, from: ci.extent)
    }

    var boundingBox: NSRect { rect }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    var color: NSColor
    var lineWidth: CGFloat = 1
    var origin: NSPoint
    var text: String
    var fontSize: CGFloat

    init(origin: NSPoint, text: String, color: NSColor, fontSize: CGFloat) {
        self.origin = origin
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    private var attributedString: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    func draw(in context: CGContext) {
        guard !text.isEmpty else { return }
        let attributed = attributedString

        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = gc

        let size = attributed.size()
        let drawRect = NSRect(x: origin.x,
                              y: origin.y - size.height,
                              width: size.width + 4,
                              height: size.height)
        attributed.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    var boundingBox: NSRect {
        let size = attributedString.size()
        return NSRect(x: origin.x,
                      y: origin.y - size.height,
                      width: size.width + 4,
                      height: size.height)
    }
}
