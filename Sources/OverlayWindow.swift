//
//  OverlayWindow.swift
//  Nightfall
//

import AppKit

final class OverlayWindow: NSWindow {

    weak var coordinator: CaptureController?
    let capture: ScreenCapture
    let overlayView: OverlayView

    init(capture: ScreenCapture,
         mode: CaptureMode,
         windows: [WindowInfo]) {
        self.capture = capture
        self.overlayView = OverlayView(capture: capture,
                                       mode: mode,
                                       windows: windows)

        super.init(contentRect: capture.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                   .stationary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none

        self.contentView = overlayView
        overlayView.window_ = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func requestFinish() {
        coordinator?.finish()
    }
}
