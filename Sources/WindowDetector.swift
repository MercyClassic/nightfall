//
//  WindowDetector.swift
//  Nightfall
//
//  Enumerates on-screen application windows (via CGWindowListCopyWindowInfo)
//  for the "capture window" mode (⌘⇧1, Shottr-style). Returns windows in
//  Z-order, front-most first, so a hit test can pick the topmost window.
//
//  CGWindow geometry uses screen-global, top-left origin coordinates. AppKit
//  uses bottom-left origin coordinates. Helpers here convert between them.
//

import AppKit
import CoreGraphics

struct WindowInfo {
    let id: CGWindowID
    let appName: String
    let title: String
    let bounds: CGRect          // CG global coords, top-left origin
    let appKitBounds: NSRect    // AppKit global coords, bottom-left origin
}

enum WindowDetector {

    /// Returns visible application windows in Z-order (front to back),
    /// excluding our own and tiny system widgets.
    static func windows(excludingPid: pid_t? = nil) -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        let myPid = ProcessInfo.processInfo.processIdentifier
        let excludePid = excludingPid ?? myPid

        var result: [WindowInfo] = []
        for d in arr {
            guard let layer = d[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }

            guard let id = d[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            guard let pid = d[kCGWindowOwnerPID as String] as? Int32,
                  pid != excludePid else { continue }

            guard let boundsDict = d[kCGWindowBounds as String] as? [String: Any],
                  let cfDict = (boundsDict as CFDictionary?),
                  let cg = CGRect(dictionaryRepresentation: cfDict)
            else { continue }

            // Skip tiny / off-screen / size-zero windows.
            if cg.width < 40 || cg.height < 40 { continue }

            let appName = d[kCGWindowOwnerName as String] as? String ?? ""
            let title   = d[kCGWindowName     as String] as? String ?? ""

            // Some helper windows have empty owner — skip.
            if appName.isEmpty { continue }

            result.append(WindowInfo(id: id,
                                     appName: appName,
                                     title: title,
                                     bounds: cg,
                                     appKitBounds: cgBoundsToAppKit(cg)))
        }
        return result
    }

    /// Returns the front-most window containing `globalAppKitPoint` (origin
    /// at bottom-left of the primary display).
    static func windowAt(_ globalAppKitPoint: NSPoint,
                         in windows: [WindowInfo]) -> WindowInfo? {
        // The list is already front-to-back, so first hit wins.
        for w in windows where w.appKitBounds.contains(globalAppKitPoint) {
            return w
        }
        return nil
    }

    // MARK: - Coordinate conversion

    /// Height of the display whose origin is (0, 0) in AppKit. CG coordinates
    /// invert relative to this display.
    private static var primaryHeight: CGFloat {
        // The primary screen is the one with origin (0,0) in AppKit terms.
        for s in NSScreen.screens where s.frame.origin == .zero {
            return s.frame.height
        }
        return NSScreen.main?.frame.height ?? 0
    }

    static func cgBoundsToAppKit(_ cg: CGRect) -> NSRect {
        let h = primaryHeight
        return NSRect(x: cg.minX,
                      y: h - cg.maxY,
                      width: cg.width,
                      height: cg.height)
    }
}
