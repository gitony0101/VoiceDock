//
//  TranscriptDeliveryPreferences.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

/// User preferences controlling transcript delivery behavior.
///
/// Preferences are persisted via UserDefaults and survive app relaunch.
public struct TranscriptDeliveryPreferences: Equatable {
    private static let automaticPasteKey = "voicedock.automaticPaste"
    private static let sendReturnAfterPasteKey = "voicedock.sendReturnAfterPaste"

    /// Whether to automatically paste the transcript to the focused application.
    /// When false, the transcript is only copied to the clipboard.
    ///
    /// Default: true (matches Candidate 6 behavior for safe migration)
    public var automaticPaste: Bool

    /// Whether to send a Return key event after pasting.
    /// Only effective when `automaticPaste` is also true.
    ///
    /// Default: false (safer than Candidate 6; prevents terminal command execution)
    public var sendReturnAfterPaste: Bool

    public init(automaticPaste: Bool = true, sendReturnAfterPaste: Bool = false) {
        self.automaticPaste = automaticPaste
        self.sendReturnAfterPaste = sendReturnAfterPaste
    }

    /// Load preferences from UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    /// - Returns: The current preferences, using defaults for any missing keys.
    public static func load(from defaults: UserDefaults = .standard) -> TranscriptDeliveryPreferences {
        let automaticPaste = defaults.object(forKey: automaticPasteKey) as? Bool ?? true
        let sendReturnAfterPaste = defaults.object(forKey: sendReturnAfterPasteKey) as? Bool ?? false
        return TranscriptDeliveryPreferences(
            automaticPaste: automaticPaste,
            sendReturnAfterPaste: sendReturnAfterPaste
        )
    }

    /// Save preferences to UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(automaticPaste, forKey: Self.automaticPasteKey)
        defaults.set(sendReturnAfterPaste, forKey: Self.sendReturnAfterPasteKey)
    }
}