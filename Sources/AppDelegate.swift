//
//  AppDelegate.swift
//  Nightfall
//

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var captureController: CaptureController?

    private enum HotkeyID: UInt32 {
        case captureArea   = 1   // ⌘⇧2
        case captureWindow = 2   // ⌘⇧1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupHotkeys()

        // Trigger Screen Recording permission prompt on first launch.
        _ = CGDisplayCreateImage(CGMainDisplayID())
    }

    // MARK: - Menu bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "moon.stars",
                                   accessibilityDescription: "Nightfall") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "◳"
            }
        }

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Capture Area    ⌘⇧2",
                                  action: #selector(triggerAreaCapture)))
        menu.addItem(makeMenuItem(title: "Capture Window  ⌘⇧1",
                                  action: #selector(triggerWindowCapture)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "About Nightfall",
                                  action: #selector(showAbout)))
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        self.statusItem = item
    }

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        let cmdShift = UInt32(cmdKey | shiftKey)

        _ = HotkeyManager.shared.register(
            id: HotkeyID.captureArea.rawValue,
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: cmdShift
        ) { [weak self] in
            self?.triggerAreaCapture()
        }

        _ = HotkeyManager.shared.register(
            id: HotkeyID.captureWindow.rawValue,
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: cmdShift
        ) { [weak self] in
            self?.triggerWindowCapture()
        }
    }

    // MARK: - Actions

    @objc func triggerAreaCapture() {
        startCapture(mode: .area)
    }

    @objc func triggerWindowCapture() {
        startCapture(mode: .window)
    }

    private func startCapture(mode: CaptureMode) {
        if captureController != nil { return }
        let controller = CaptureController(mode: mode) { [weak self] in
            self?.captureController = nil
        }
        captureController = controller
        controller.start()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Nightfall"
        alert.informativeText = """
        A local-only screenshot & annotation tool.

        ⌘⇧2  Capture area
        ⌘⇧1  Capture window
        Esc   Cancel
        Enter Save
        ⌘C    Copy to clipboard
        ⌘S    Save to file
        ⌘Z    Undo  /  ⌘⇧Z Redo
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
}
