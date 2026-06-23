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
    private let isAccessibilityTrusted: () -> Bool
    private let postKeyboardEvent: (CGKeyCode, CGEventFlags) -> Void

    public init() {
        self.init(
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            postKeyboardEvent: TranscriptDestination.postKeyDown
        )
    }

    init(isAccessibilityTrusted: @escaping () -> Bool,
         postKeyboardEvent: @escaping (CGKeyCode, CGEventFlags) -> Void) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.postKeyboardEvent = postKeyboardEvent
    }

    /// Copy text to clipboard without pasting.
    ///
    /// This is the safe fallback when automatic paste is disabled.
    ///
    /// - Parameter text: The text to copy
    public func copyToClipboard(text: String) {
        guard !text.isEmpty else {
            logger.warning("Empty text; nothing to copy")
            return
        }

        NSPasteboard.general.clearContents()
        let setString = NSPasteboard.general.setString(text, forType: .string)
        logger.info("copyToClipboard: setString=\(setString), length=\(text.count)")
    }

    /// Paste text to the focused application with optional Return.
    ///
    /// - Parameters:
    ///   - text: The text to paste
    ///   - sendReturn: Whether to send a Return key event after pasting
    public func paste(text: String, sendReturn: Bool = true) {
        guard !text.isEmpty else {
            logger.warning("Empty text; nothing to paste")
            return
        }

        // Copy to clipboard first (always happens)
        copyToClipboard(text: text)

        guard isAccessibilityTrusted() else {
            logger.info("Accessibility not trusted; leaving transcript on clipboard")
            return
        }

        // Simulate Cmd-V paste
        postKeyboardEvent(0x09, .maskCommand)

        if sendReturn {
            postKeyboardEvent(0x24, [])
        }
    }

    /// Paste text based on a delivery decision.
    ///
    /// This method integrates the policy decision with actual delivery.
    ///
    /// - Parameters:
    ///   - text: The transcript text
    ///   - decision: The delivery decision from TranscriptDeliveryPolicy
    /// - Returns: A log message describing what happened
    @discardableResult
    public func deliver(text: String, decision: TranscriptDeliveryDecision) -> String {
        switch decision {
        case .copyToClipboard:
            copyToClipboard(text: text)
            return "Transcript copied to clipboard (auto-paste disabled)"

        case .pasteTranscript:
            paste(text: text, sendReturn: false)
            return "Transcript pasted (Return disabled)"

        case .pasteAndSendReturn:
            paste(text: text, sendReturn: true)
            return "Transcript pasted with Return"

        case .pasteWithReturnSuppressed(let reason):
            paste(text: text, sendReturn: false)
            logger.info("SAFE_DELIVERY: \(reason)")
            return reason
        }
    }

    private static func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
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
