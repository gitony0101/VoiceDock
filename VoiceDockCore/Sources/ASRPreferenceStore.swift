//
//  ASRPreferenceStore.swift
//  VoiceDock
//
//  VoiceDock 0.2 — Single production ASR-model preference store.
//
//  One explicit UserDefaults suite backs every production model-selection
//  component so that no two components can drift to different defaults stores
//  across the relaunch boundary. Tests inject isolated UUID suites; production
//  constructs exactly one shared instance through `ASRPreferenceStore.production`.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ASRPreferenceStore")

/// Canonical suite name for the production ASR-model preference store.
///
/// Production uses a single explicit `UserDefaults(suiteName:)` store shared
/// across ModelStatus, the model picker, AppDelegate, ASRProviderFactory,
/// and restart preference verification. The suite name is intentionally
/// distinct from the host application's bundle identifier: Apple explicitly
/// rejects `UserDefaults(suiteName:)` when the suite name equals the host
/// bundle ID (logging "Using your own bundle identifier as an NSUserDefaults
/// suite name does not make sense and will not work" and returning nil).
/// Using a sub-suite keeps the store in the application's cfprefs family
/// while remaining a valid named suite, so the production singleton can fail
/// visibly (and never silently fall back to `.standard`) when the platform
/// refuses to construct the suite for any other reason.
public let ASRPreferenceStoreSuiteName = "com.voicedock.app.asr-prefs"

/// A thin wrapper around a `UserDefaults` instance that is the single source
/// of truth for ASR-model selection in production. Production constructs one
/// shared instance and threads it through ModelStatus, the model picker,
/// AppDelegate, ASRProviderFactory, and restart preference verification.
///
/// Tests construct isolated instances with `ASRPreferenceStore(isolate:)`,
/// backed by a unique UUID suite, so production preferences are never touched.
public final class ASRPreferenceStore: @unchecked Sendable {
    public let suiteName: String
    public let defaults: UserDefaults

    /// Production constructor. Creates the canonical suite and fails
    /// visibly (fatalError) if the suite cannot be created — production must
    /// never silently fall back to `.standard`.
    public static let production: ASRPreferenceStore = {
        guard let defaults = UserDefaults(suiteName: ASRPreferenceStoreSuiteName) else {
            // The spec requires a visible failure here. Production must not
            // silently fall back to .standard.
            fatalError("ASRPreferenceStore: failed to create UserDefaults suite \(ASRPreferenceStoreSuiteName)")
        }
        return ASRPreferenceStore(suiteName: ASRPreferenceStoreSuiteName, defaults: defaults)
    }()

    /// Internal initializer used by both production and test factories.
    public init(suiteName: String, defaults: UserDefaults) {
        self.suiteName = suiteName
        self.defaults = defaults
    }

    /// Test-only constructor backed by an isolated UUID suite. Production
    /// must never call this.
    public static func isolate(_ suffix: String = UUID().uuidString) -> ASRPreferenceStore {
        let name = "VoiceDockTests.ASRPrefs.\(suffix)"
        guard let defaults = UserDefaults(suiteName: name) else {
            // Tests constructed an unisolatable suite; this is a test bug.
            fatalError("ASRPreferenceStore: failed to create isolated suite \(name)")
        }
        // Ensure the isolated suite starts clean for determinism.
        defaults.dictionaryRepresentation().keys.forEach { defaults.removeObject(forKey: $0) }
        return ASRPreferenceStore(suiteName: name, defaults: defaults)
    }
}

// MARK: - Preference keys (shared with ASRModelPreferences)

extension ASRPreferenceStore {
    public static let selectedModelKey = "voicedock.selectedASRModel"
    public static let hasSeenModelSelectionKey = "voicedock.hasSeenModelSelection"
}

// MARK: - Persistence verification

extension ASRPreferenceStore {
    /// Read the raw persisted selected-model value as a string, exactly as a
    /// freshly-launched process would see it (no in-memory caching layer on
    /// top of `UserDefaults`).
    public func rawSelectedModelValue() -> String? {
        defaults.string(forKey: Self.selectedModelKey)
    }

    /// Force a cfprefs synchronization for this suite's domain so a value
    /// written by a terminating process is durable to a process launched
    /// immediately afterward via `open -n`.
    @discardableResult
    public func synchronize() -> Bool {
        let domain = suiteName as CFString
        let result = CFPreferencesAppSynchronize(domain)
        logger.info("ASRPreferenceStore.synchronize domain=\(self.suiteName, privacy: .public) result=\(result)")
        return result
    }
}
