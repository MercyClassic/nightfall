//
//  CaptureController.swift
//  Nightfall
//
//  Orchestrates a single overlay window on the screen the cursor is on.
//  Other displays remain untouched (live content keeps playing on them).
//

import AppKit

enum CaptureMode {
    case area    // ⌘⇧2 — drag out a rectangle
    case window  // ⌘⇧1 — click on a window
}

final class CaptureController {

    private let mode: CaptureMode
    private let onFinished: () -> Void
    private var overlay: OverlayWindow?

    init(mode: CaptureMode, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.onFinished = onFinished
    }

    func start() {
        // 1. Pick the screen the cursor is on.
        let screen = ScreenshotManager.screenForCursor()

        // 2. Capture windows BEFORE we activate ourselves, so our own
        //    overlay is never in the list.
        let windows: [WindowInfo]
        if mode == .window {
            windows = WindowDetector.windows().filter {
                screen.frame.intersects($0.appKitBounds)
            }
        } else {
            windows = []
        }

        // 3. Capture the screen image BEFORE any of our UI changes are
        //    visible — so the screenshot reflects what the user sees right
        //    now, with nothing of ours in it.
        guard let capture = ScreenshotManager.capture(screen: screen) else {
            NSSound.beep()
            finish()
            return
        }

        // 4. Build & show overlay with no animation, then activate.
        let overlay = OverlayWindow(capture: capture, mode: mode, windows: windows)
        overlay.coordinator = self
        overlay.animationBehavior = .none
        overlay.orderFrontRegardless()
        overlay.makeKey()
        self.overlay = overlay

        // Activate AFTER the overlay is up — that way the activation
        // doesn't briefly expose our missing window.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called by the overlay when the user saves / copies / cancels.
    func finish() {
        if let overlay = overlay {
            overlay.orderOut(nil)
            overlay.close()
        }
        overlay = nil
        onFinished()
    }
}
