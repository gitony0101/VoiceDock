//
//  TerminalApplicationClassifier.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

/// Classifier for identifying terminal applications.
///
/// Terminal applications require special safety handling: Return key events
/// must be suppressed to prevent accidental command execution.
public struct TerminalApplicationClassifier {
    /// Known terminal application bundle identifiers.
    ///
    /// Verified terminals:
    /// - `com.apple.Terminal` - Apple Terminal
    /// - `com.googlecode.iterm2` - iTerm2
    ///
    /// Unverified (may need confirmation):
    /// - `dev.warp.Warp` - Warp terminal (common convention, not verified)
    public static let knownTerminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        // Warp terminal - bundle ID observed in the wild, should verify if installed
        "dev.warp.Warp"
    ]

    /// Determine if a bundle identifier represents a terminal application.
    ///
    /// - Parameter bundleId: The bundle identifier to check (may be nil)
    /// - Returns: true if the bundle ID matches a known terminal
    public static func isTerminal(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return knownTerminals.contains(bundleId)
    }

    /// Get the list of known terminal bundle identifiers.
    ///
    /// Useful for diagnostics and documentation.
    public static var allKnownTerminals: [String] {
        Array(knownTerminals).sorted()
    }
}