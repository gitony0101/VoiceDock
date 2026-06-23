//
//  TranscriptDeliveryPolicy.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "TranscriptDeliveryPolicy")

/// Policy engine that determines how to deliver a transcript.
///
/// The policy considers:
/// - User preferences (automatic paste, Return-after-paste)
/// - Frontmost application type (terminal apps suppress Return)
public struct TranscriptDeliveryPolicy {
    private let preferences: TranscriptDeliveryPreferences
    private let appProvider: FrontmostApplicationProviding

    public init(
        preferences: TranscriptDeliveryPreferences,
        appProvider: FrontmostApplicationProviding
    ) {
        self.preferences = preferences
        self.appProvider = appProvider
    }

    /// Determine the delivery decision based on current state.
    ///
    /// Decision logic:
    /// 1. If automaticPaste is false → copyToClipboard
    /// 2. If automaticPaste is true but sendReturnAfterPaste is false → pasteTranscript
    /// 3. If both are true AND frontmost app is a terminal → pasteWithReturnSuppressed
    /// 4. If both are true AND frontmost app is not a terminal → pasteAndSendReturn
    public func determineDelivery() -> TranscriptDeliveryDecision {
        let frontmostBundleId = appProvider.frontmostBundleIdentifier
        let isTerminal = TerminalApplicationClassifier.isTerminal(bundleId: frontmostBundleId)

        logger.info("determineDelivery: automaticPaste=\(preferences.automaticPaste), sendReturn=\(preferences.sendReturnAfterPaste), frontmost=\(frontmostBundleId ?? "unknown"), isTerminal=\(isTerminal)")

        if !preferences.automaticPaste {
            logger.info("decision: copyToClipboard (automatic paste disabled)")
            return .copyToClipboard
        }

        if !preferences.sendReturnAfterPaste {
            logger.info("decision: pasteTranscript (Return disabled in preferences)")
            return .pasteTranscript
        }

        // Both preferences are ON; check for terminal safety
        if isTerminal {
            let reason = "Return suppressed for terminal safety (\(frontmostBundleId ?? "unknown terminal"))"
            logger.info("decision: \(reason)")
            return .pasteWithReturnSuppressed(reason: reason)
        }

        logger.info("decision: pasteAndSendReturn")
        return .pasteAndSendReturn
    }
}