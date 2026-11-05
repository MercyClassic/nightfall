//
//  TextRecognizer.swift
//  Nightfall
//
//  Live-Text-style OCR. Recognises the text inside the current selection so
//  it can be drag-selected and copied as plain text.
//
//  Everything happens in memory: the capture is never written to disk, and
//  Vision runs fully on-device.
//

import AppKit
import Vision

// MARK: - Model

/// A single recognised character with its rect in OverlayView coordinates
/// (AppKit, origin bottom-left).
struct RecognizedGlyph {
    let character: Character
    let rect: NSRect
}

struct RecognizedLine {
    let glyphs: [RecognizedGlyph]
    let rect: NSRect

    var text: String { String(glyphs.map { $0.character }) }
}

/// A caret position. `glyph` is an *insertion* index, so it ranges over
/// 0...glyphs.count.
struct TextPosition: Equatable, Comparable {
    let line: Int
    let glyph: Int

    static func < (a: TextPosition, b: TextPosition) -> Bool {
        a.line != b.line ? a.line < b.line : a.glyph < b.glyph
    }
}

struct RecognizedTextLayout {

    let lines: [RecognizedLine]

    static let empty = RecognizedTextLayout(lines: [])

    var isEmpty: Bool { lines.allSatisfy { $0.glyphs.isEmpty } }

    var start: TextPosition { TextPosition(line: 0, glyph: 0) }

    var end: TextPosition {
        guard let last = lines.indices.last else { return start }
        return TextPosition(line: last, glyph: lines[last].glyphs.count)
    }

    // MARK: Hit testing

    /// Vertical slack used when deciding whether a point is "on" a line.
    private func padding(for line: RecognizedLine) -> CGFloat {
        max(3, line.rect.height * 0.35)
    }

    /// Strict hit test: returns a position only if the point actually lands on
    /// a recognised line (used to decide between "start selecting text" and
    /// "this click was on empty space").
    func hitTest(_ point: NSPoint) -> TextPosition? {
        guard let index = lineIndex(at: point, requireHit: true) else { return nil }
        return TextPosition(line: index, glyph: glyphIndex(in: index, x: point.x))
    }

    /// Lenient hit test used while dragging: always snaps to the closest
    /// position, the way a text view does.
    func nearestPosition(to point: NSPoint) -> TextPosition? {
        guard let index = lineIndex(at: point, requireHit: false) else { return nil }
        return TextPosition(line: index, glyph: glyphIndex(in: index, x: point.x))
    }

    private func lineIndex(at point: NSPoint, requireHit: Bool) -> Int? {
        guard !lines.isEmpty else { return nil }

        // Lines whose vertical band contains the point (there can be several
        // when text is laid out in columns).
        let onRow = lines.indices.filter { i in
            let pad = padding(for: lines[i])
            return point.y >= lines[i].rect.minY - pad
                && point.y <= lines[i].rect.maxY + pad
        }

        if !onRow.isEmpty {
            let closest = onRow.min {
                horizontalDistance(to: point.x, line: lines[$0])
                    < horizontalDistance(to: point.x, line: lines[$1])
            }
            if requireHit, let c = closest {
                // Allow a little slack past the end of the line so clicking
                // just past the last word still grabs it.
                let slack = max(6, lines[c].rect.height * 0.5)
                if horizontalDistance(to: point.x, line: lines[c]) > slack { return nil }
            }
            return closest
        }

        if requireHit { return nil }

        return lines.indices.min {
            verticalDistance(to: point.y, line: lines[$0])
                < verticalDistance(to: point.y, line: lines[$1])
        }
    }

    private func horizontalDistance(to x: CGFloat, line: RecognizedLine) -> CGFloat {
        if x < line.rect.minX { return line.rect.minX - x }
        if x > line.rect.maxX { return x - line.rect.maxX }
        return 0
    }

    private func verticalDistance(to y: CGFloat, line: RecognizedLine) -> CGFloat {
        if y < line.rect.minY { return line.rect.minY - y }
        if y > line.rect.maxY { return y - line.rect.maxY }
        return 0
    }

    private func glyphIndex(in lineIndex: Int, x: CGFloat) -> Int {
        let glyphs = lines[lineIndex].glyphs
        for (i, g) in glyphs.enumerated() where x < g.rect.midX { return i }
        return glyphs.count
    }

    // MARK: Word / line ranges

    /// Word under the point — used for double-click.
    func wordRange(at point: NSPoint) -> (TextPosition, TextPosition)? {
        guard let index = lineIndex(at: point, requireHit: true) else { return nil }
        let glyphs = lines[index].glyphs
        guard !glyphs.isEmpty else { return nil }

        var i = glyphIndex(in: index, x: point.x)
        if i >= glyphs.count { i = glyphs.count - 1 }
        if isWordBreak(glyphs[i].character) {
            return (TextPosition(line: index, glyph: i),
                    TextPosition(line: index, glyph: i + 1))
        }

        var lower = i
        while lower > 0, !isWordBreak(glyphs[lower - 1].character) { lower -= 1 }
        var upper = i + 1
        while upper < glyphs.count, !isWordBreak(glyphs[upper].character) { upper += 1 }

        return (TextPosition(line: index, glyph: lower),
                TextPosition(line: index, glyph: upper))
    }

    /// Whole line under the point — used for triple-click.
    func lineRange(at point: NSPoint) -> (TextPosition, TextPosition)? {
        guard let index = lineIndex(at: point, requireHit: true) else { return nil }
        return (TextPosition(line: index, glyph: 0),
                TextPosition(line: index, glyph: lines[index].glyphs.count))
    }

    private func isWordBreak(_ c: Character) -> Bool {
        c.isWhitespace || (c.isPunctuation && c != "-" && c != "_") || c.isSymbol
    }

    // MARK: Selection geometry & text

    /// One highlight rect per (partially) selected line.
    func selectionRects(from: TextPosition, to: TextPosition) -> [NSRect] {
        var result: [NSRect] = []
        for i in lineIndex(from: from, to: to) {
            let glyphs = lines[i].glyphs
            let range = glyphRange(inLine: i, from: from, to: to)
            guard range.lowerBound < range.upperBound,
                  range.upperBound <= glyphs.count else { continue }
            let slice = glyphs[range]
            guard let first = slice.first, let last = slice.last else { continue }
            result.append(NSRect(x: first.rect.minX,
                                 y: lines[i].rect.minY,
                                 width: max(2, last.rect.maxX - first.rect.minX),
                                 height: lines[i].rect.height))
        }
        return result
    }

    func text(from: TextPosition, to: TextPosition) -> String {
        var parts: [String] = []
        for i in lineIndex(from: from, to: to) {
            let glyphs = lines[i].glyphs
            let range = glyphRange(inLine: i, from: from, to: to)
            guard range.lowerBound < range.upperBound,
                  range.upperBound <= glyphs.count else { continue }
            parts.append(String(glyphs[range].map { $0.character }))
        }
        return parts.joined(separator: "\n")
    }

    /// Full recognised text, in reading order.
    var allText: String {
        lines.map { $0.text }.joined(separator: "\n")
    }

    private func lineIndex(from: TextPosition, to: TextPosition) -> Range<Int> {
        guard !lines.isEmpty else { return 0..<0 }
        let lower = max(0, min(from.line, lines.count - 1))
        let upper = max(0, min(to.line, lines.count - 1))
        return lower..<(upper + 1)
    }

    private func glyphRange(inLine i: Int,
                            from: TextPosition,
                            to: TextPosition) -> Range<Int> {
        let count = lines[i].glyphs.count
        let lower = (i == from.line) ? min(max(0, from.glyph), count) : 0
        let upper = (i == to.line)   ? min(max(0, to.glyph),   count) : count
        return min(lower, upper)..<max(lower, upper)
    }
}

// MARK: - Vision wrapper

enum TextRecognizer {

    /// Recognises text inside `region`.
    ///
    /// - Parameters:
    ///   - image:       the full screen capture at native pixel resolution.
    ///   - imageBounds: the view rect that `image` maps onto (bottom-left origin).
    ///   - region:      the sub-rect to OCR, in the same coordinate system.
    ///   - completion:  always called on the main queue.
    static func recognize(in image: CGImage,
                          imageBounds: NSRect,
                          region: NSRect,
                          completion: @escaping (RecognizedTextLayout) -> Void) {

        guard imageBounds.width > 0, imageBounds.height > 0,
              region.width > 2, region.height > 2 else {
            DispatchQueue.main.async { completion(.empty) }
            return
        }

        let scaleX = CGFloat(image.width)  / imageBounds.width
        let scaleY = CGFloat(image.height) / imageBounds.height

        // View coords (bottom-left) -> CGImage pixel coords (top-left).
        let pxRect = CGRect(
            x: (region.minX - imageBounds.minX) * scaleX,
            y: (imageBounds.maxY - region.maxY) * scaleY,
            width:  region.width  * scaleX,
            height: region.height * scaleY
        ).integral

        let full = CGRect(x: 0, y: 0,
                          width: CGFloat(image.width),
                          height: CGFloat(image.height))
        let safe = pxRect.intersection(full)

        guard safe.width >= 8, safe.height >= 8,
              let cropped = image.cropping(to: safe) else {
            DispatchQueue.main.async { completion(.empty) }
            return
        }

        // The exact view rect the crop corresponds to, so normalised Vision
        // coordinates map back without drift from the .integral rounding.
        let cropInView = NSRect(
            x: imageBounds.minX + safe.minX / scaleX,
            y: imageBounds.maxY - safe.maxY / scaleY,
            width:  safe.width  / scaleX,
            height: safe.height / scaleY
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let layout = run(on: upscaledForOCR(cropped), mappedTo: cropInView)
            DispatchQueue.main.async { completion(layout) }
        }
    }

    // MARK: Private

    private static func run(on image: CGImage,
                            mappedTo viewRect: NSRect) -> RecognizedTextLayout {

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3

        // Ask for Russian + English, but only for the ones this machine
        // actually ships — an unsupported language makes the request fail.
        let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequestRevision3)) ?? []
        let wanted = ["ru-RU", "en-US"].filter { supported.contains($0) }
        if !wanted.isEmpty { request.recognitionLanguages = wanted }

        let handler = VNImageRequestHandler(cgImage: image,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .empty
        }

        let converted = observations.compactMap { obs -> RecognizedLine? in
            guard let candidate = obs.topCandidates(1).first,
                  !candidate.string.isEmpty else { return nil }

            let lineRect = viewRect.denormalize(obs.boundingBox)
            guard lineRect.width > 0, lineRect.height > 0 else { return nil }

            let glyphs = glyphRects(for: candidate, lineRect: lineRect, in: viewRect)
            guard !glyphs.isEmpty else { return nil }

            return RecognizedLine(glyphs: glyphs, rect: lineRect)
        }

        return RecognizedTextLayout(lines: readingOrder(converted))
    }

    /// Per-character rects. Vision can refuse a range, in which case the whole
    /// line falls back to an evenly spaced approximation — imprecise, but it
    /// keeps hit testing monotonic instead of dropping the line entirely.
    private static func glyphRects(for candidate: VNRecognizedText,
                                   lineRect: NSRect,
                                   in viewRect: NSRect) -> [RecognizedGlyph] {
        let string = candidate.string
        var glyphs: [RecognizedGlyph] = []
        glyphs.reserveCapacity(string.count)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(after: index)
            guard let box = try? candidate.boundingBox(for: index..<next) else {
                return evenlySpacedGlyphs(string, lineRect: lineRect)
            }
            let rect = viewRect.denormalize(box.boundingBox)
            glyphs.append(RecognizedGlyph(character: string[index],
                                          rect: rect.isEmpty ? lineRect : rect))
            index = next
        }

        // Vision occasionally returns boxes out of order for a rotated line;
        // sorting keeps caret math sane.
        if !glyphs.isEmpty, !isMonotonic(glyphs) {
            return evenlySpacedGlyphs(string, lineRect: lineRect)
        }
        return glyphs
    }

    private static func isMonotonic(_ glyphs: [RecognizedGlyph]) -> Bool {
        var previous = -CGFloat.greatestFiniteMagnitude
        for g in glyphs {
            if g.rect.midX + 0.5 < previous { return false }
            previous = g.rect.midX
        }
        return true
    }

    private static func evenlySpacedGlyphs(_ string: String,
                                           lineRect: NSRect) -> [RecognizedGlyph] {
        let count = string.count
        guard count > 0 else { return [] }
        let step = lineRect.width / CGFloat(count)
        return string.enumerated().map { i, ch in
            RecognizedGlyph(character: ch,
                            rect: NSRect(x: lineRect.minX + CGFloat(i) * step,
                                         y: lineRect.minY,
                                         width: step,
                                         height: lineRect.height))
        }
    }

    /// Vision returns observations roughly top-to-bottom, but side-by-side
    /// columns can interleave. Group into rows, then sort left-to-right.
    private static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        guard !lines.isEmpty else { return [] }
        let sorted = lines.sorted { $0.rect.midY > $1.rect.midY }

        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if var last = rows.last,
               let reference = last.first,
               overlapRatio(line.rect, reference.rect) > 0.5 {
                last.append(line)
                rows[rows.count - 1] = last
            } else {
                rows.append([line])
            }
        }

        return rows.flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }

    private static func overlapRatio(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap > 0 else { return 0 }
        return overlap / min(a.height, b.height)
    }

    /// Small crops of small text recognise much better when scaled up.
    private static func upscaledForOCR(_ image: CGImage) -> CGImage {
        let target: CGFloat = 1600
        let longest = CGFloat(max(image.width, image.height))
        guard longest > 0 else { return image }

        let factor = min(3.0, max(1.0, target / longest))
        guard factor > 1.05 else { return image }

        let w = Int((CGFloat(image.width)  * factor).rounded())
        let h = Int((CGFloat(image.height) * factor).rounded())
        guard w > 0, h > 0, w * h < 40_000_000,
              let ctx = CGContext(data: nil,
                                  width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

// MARK: - Normalised -> view coordinates

private extension NSRect {
    /// Maps a Vision normalised rect (origin bottom-left) into this rect.
    func denormalize(_ normalized: CGRect) -> NSRect {
        NSRect(x: minX + normalized.minX * width,
               y: minY + normalized.minY * height,
               width:  normalized.width  * width,
               height: normalized.height * height)
    }
}
