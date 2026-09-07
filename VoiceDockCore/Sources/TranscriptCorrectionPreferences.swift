//
//  TranscriptCorrectionPreferences.swift
//  VoiceDock
//
//  VoiceDock Personal Transcript Correction v1
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "TranscriptCorrectionPreferences")

/// User preferences for transcript correction.
///
/// Preferences are persisted via UserDefaults and survive app relaunch.
public struct TranscriptCorrectionPreferences: Equatable, Sendable {
    private static let correctionModeKey = "voicedock.transcriptCorrectionMode"
    private static let userCorrectionsFileKey = "voicedock.userCorrectionsFile"

    /// The correction mode to apply
    public var mode: TranscriptCorrectionMode

    /// Whether to load user corrections from file (in addition to builtin rules)
    public var loadUserCorrections: Bool

    public init(mode: TranscriptCorrectionMode = .off, loadUserCorrections: Bool = true) {
        self.mode = mode
        self.loadUserCorrections = loadUserCorrections
    }

    /// Load preferences from UserDefaults.
    ///
    /// VoiceDock product target: Correction OFF by default. When no correction
    /// mode key has been persisted (clean install / cleared preference), the
    /// fallback resolves to `.off`. An explicitly saved `.personalCorrection`
    /// is preserved verbatim, as is an explicitly saved `.off`.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    /// - Returns: The current preferences, using defaults for any missing keys.
    public static func load(from defaults: UserDefaults = .standard) -> TranscriptCorrectionPreferences {
        let modeRaw = defaults.string(forKey: correctionModeKey)
        let mode = TranscriptCorrectionMode(rawValue: modeRaw ?? "") ?? .off

        let loadUser = defaults.object(forKey: userCorrectionsFileKey) as? Bool ?? true

        logger.debug("Loaded correction preferences: mode=\(mode.displayName), loadUserCorrections=\(loadUser)")
        return TranscriptCorrectionPreferences(mode: mode, loadUserCorrections: loadUser)
    }

    /// Save preferences to UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Self.correctionModeKey)
        defaults.set(loadUserCorrections, forKey: Self.userCorrectionsFileKey)
        logger.info("Saved correction preferences: mode=\(mode.displayName)")
    }

    /// Reset to default values
    public static func reset(to defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: correctionModeKey)
        defaults.removeObject(forKey: userCorrectionsFileKey)
        logger.info("Reset correction preferences to defaults")
    }
}