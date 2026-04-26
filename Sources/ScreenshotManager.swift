//
//  ScreenshotManager.swift
//  Nightfall
//
//  Captures a single NSScreen using CGDisplayCreateImage. Other screens are
//  intentionally left untouched so live content keeps playing on them.
//

import AppKit
import CoreGraphics

struct ScreenCapture {
    let screen: NSScreen
    let image: NSImage    // size in points
    let cgImage: CGImage  // native pixel resolution
    let frame: NSRect     // global AppKit coords
}

enum ScreenshotManager {

    /// Returns the screen the cursor is currently on, falling back to main.
    static func screenForCursor() -> NSScreen {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    static func capture(screen: NSScreen) -> ScreenCapture? {
        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else { return nil }

        guard let cgImage = CGDisplayCreateImage(displayID) else { return nil }
        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        return ScreenCapture(screen: screen,
                             image: image,
                             cgImage: cgImage,
                             frame: screen.frame)
    }
}
