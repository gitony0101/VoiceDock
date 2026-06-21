//
//  TranscriptDestination.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit

/// Delivers transcript to focused application via clipboard + paste
struct TranscriptDestination {
    func paste(text: String, sendReturn: Bool = false) {
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Simulate Cmd-V paste
        postKeyDown(keyCode: 0x09, flags: .maskCommand)

        // Optionally send Return
        if sendReturn {
            postKeyDown(keyCode: 0x24)
        }
    }

    private func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}