//
//  HotkeyManager.swift
//  Nightfall
//
//  Singleton manager for multiple Carbon-registered global hotkeys. Carbon's
//  RegisterEventHotKey is the most reliable mechanism for system-wide hotkeys
//  on macOS — it doesn't require Accessibility permission for combinations
//  that include modifier keys, unlike NSEvent global monitors.
//

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {

    static let shared = HotkeyManager()
    private init() {}

    private struct Registration {
        let ref: EventHotKeyRef
        let callback: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x4E494754  // 'NIGT'

    @discardableResult
    func register(id: UInt32,
                  keyCode: UInt32,
                  modifiers: UInt32,
                  callback: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        // Replace any existing registration with the same id.
        if let existing = registrations[id] {
            UnregisterEventHotKey(existing.ref)
            registrations.removeValue(forKey: id)
        }

        let hkID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hkID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref = ref else {
            NSLog("Nightfall: hotkey \(id) registration failed (\(status))")
            return false
        }
        registrations[id] = Registration(ref: ref, callback: callback)
        return true
    }

    func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(GetApplicationEventTarget(),
                            { (_, eventRef, userData) -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            if status == noErr {
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let reg = mgr.registrations[hkID.id] {
                    DispatchQueue.main.async { reg.callback() }
                }
            }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }
}
