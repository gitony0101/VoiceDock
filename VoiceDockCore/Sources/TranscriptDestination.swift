//
//  TranscriptDestination.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "TranscriptDestination")

public struct TranscriptDestination {
    public init() {}

    public func paste(text: String, sendReturn: Bool = true) {
        guard !text.isEmpty else {
            logger.warning("Empty text; nothing to paste")
            return
        }

        // Copy to clipboard
        NSPasteboard.general.clearContents()
        let setString = NSPasteboard.general.setString(text, forType: .string)
        logger.info("Clipboard setString=\(setString), length=\(text.count)")

        guard AXIsProcessTrusted() else {
            logger.info("Accessibility not trusted; leaving transcript on clipboard")
            return
        }

        // Simulate Cmd-V paste
        postKeyDown(keyCode: 0x09, flags: .maskCommand)

        if sendReturn {
            postKeyDown(keyCode: 0x24)
        }
    }

    private func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("CGEventSource returned nil")
            return
        }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
