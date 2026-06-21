//
//  HotKeyManager.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Carbon.HIToolbox
import Foundation

// Virtual key codes from Carbon
private enum VirtualKeyCodes {
    static let kVK_SPACE: UInt32 = 49
    static let kVK_ANSI_V: UInt32 = 9
    static let kVK_Return: UInt32 = 36
}

/// Manages global push-to-talk hotkey registration
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    init(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onStart = onStart
        self.onStop = onStop
    }

    func register() -> Bool {
        // Register Command+Space as PTT hotkey
        let hotKeyID = EventHotKeyID(signature: OSType(4, from: "vdpt"), id: 1)
        let status = RegisterEventHotKey(
            VirtualKeyCodes.kVK_SPACE,
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

extension OSType {
    init(_ value: Int32) {
        self = OSType(value)
    }

    init(_ type: Int, from string: String) {
        if string.count >= 4 {
            let utf8 = Array(string.utf8)
            let value = Int32(utf8[0]) << 24 | Int32(utf8[1]) << 16 | Int32(utf8[2]) << 8 | Int32(utf8[3])
            self = OSType(value)
        } else {
            self = OSType(0)
        }
    }
}