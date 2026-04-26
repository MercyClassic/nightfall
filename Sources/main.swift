//
//  main.swift
//  Nightfall
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory = no Dock icon, menu-bar app only.
app.setActivationPolicy(.accessory)
app.run()
