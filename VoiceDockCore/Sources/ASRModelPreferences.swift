//
//  ASRModelPreferences.swift
//  VoiceDock
//
//  VoiceDock Persistent ASR Model Selection
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ASRModelPreferences")

/// User preferences for ASR model selection.
///
/// Preferences are persisted via UserDefaults and survive app relaunch.
///
/// Selection precedence:
/// 1. Valid nonempty `VOICEDOCK_ASR_MODEL` environment override (for testing)
/// 2. Saved user model preference
/// 3. Fast default (qwen3-0.6b-8bit)
///
/// When an environment override is active, the UI must clearly indicate that
/// the model picker will apply only after a normal restart without the override.
///
/// Production composition must read/write through a shared `ASRPreferenceStore`
/// instance so that no two components drift to different defaults stores.
/// The static convenience helpers below default to `.standard` only for legacy
/// entry points and tests; production wiring passes an explicit store.
public struct ASRModelPreferences: Equatable, Sendable {
    private static let selectedModelKey = ASRPreferenceStore.selectedModelKey
    private static let hasSeenModelSelectionKey = ASRPreferenceStore.hasSeenModelSelectionKey

    /// The user's selected model identifier
    public var selectedModel: ASRModelSelection

    /// Whether the user has been shown the model selection UI (for onboarding)
    public var hasSeenModelSelection: Bool

    public init(selectedModel: ASRModelSelection = .qwen3_0_6B_8bit, hasSeenModelSelection: Bool = false) {
        self.selectedModel = selectedModel
        self.hasSeenModelSelection = hasSeenModelSelection
    }

    /// Load preferences from a `UserDefaults` instance (legacy/test entry point).
    /// Defaults to `.standard`. Production should call `load(from:)` on the
    /// shared `ASRPreferenceStore` instead so the store is explicit.
    public static func load(from defaults: UserDefaults = .standard) -> ASRModelPreferences {
        let modelRaw = defaults.string(forKey: selectedModelKey)
        let hasSeen = defaults.object(forKey: hasSeenModelSelectionKey) as? Bool ?? false

        // Parse saved model, default to Fast if missing or invalid
        let model: ASRModelSelection
        if let raw = modelRaw, let selection = ASRModelSelection(rawValue: raw) {
            model = selection
        } else {
            model = .qwen3_0_6B_8bit  // Fast default
        }

        logger.debug("Loaded ASR model preferences: selectedModel=\(model.rawValue) suite=\(String(describing: defaults))")
        return ASRModelPreferences(selectedModel: model, hasSeenModelSelection: hasSeen)
    }

    /// Load preferences from the shared `ASRPreferenceStore`. This is the
    /// production path — the store guarantees every component reads the same
    /// durable on-disk value.
    public static func load(from store: ASRPreferenceStore) -> ASRModelPreferences {
        load(from: store.defaults)
    }

    /// Save preferences to a `UserDefaults` instance (legacy/test entry point).
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
        defaults.set(hasSeenModelSelection, forKey: Self.hasSeenModelSelectionKey)
        logger.info("Saved ASR model preferences: selectedModel=\(selectedModel.rawValue) suite=\(String(describing: defaults))")
    }

    /// Save preferences through the shared `ASRPreferenceStore` and force a
    /// cfprefs synchronization so the value is durable for a process launched
    /// immediately afterward via `open -n`. Returns the persisted raw value
    /// read back from the same store (no separate in-memory cache).
    @discardableResult
    public func saveAndSynchronize(to store: ASRPreferenceStore) -> String {
        save(to: store.defaults)
        store.synchronize()
        let raw = store.rawSelectedModelValue()
        logger.info("saveAndSynchronize: wrote=\(selectedModel.rawValue) readBack=\(raw ?? "nil")")
        return raw ?? ""
    }

    /// Reset to default values
    public static func reset(to defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: selectedModelKey)
        defaults.removeObject(forKey: hasSeenModelSelectionKey)
        logger.info("Reset ASR model preferences to defaults")
    }

    public static func reset(to store: ASRPreferenceStore) {
        store.defaults.removeObject(forKey: selectedModelKey)
        store.defaults.removeObject(forKey: hasSeenModelSelectionKey)
        store.synchronize()
    }

    /// Determine the effective model for this launch.
    ///
    /// Precedence:
    /// 1. Environment override (VOICEDOCK_ASR_MODEL)
    /// 2. Saved user preference (read through the shared store when provided)
    /// 3. Fast default
    ///
    /// - Parameters:
    ///   - store: Optional shared preference store. When provided, the saved
    ///     preference is read through it so production shares one durable view.
    ///   - warningRecorder: Optional closure to record warnings for testing
    public static func effectiveModel(
        from store: ASRPreferenceStore? = nil,
        warningRecorder: ((ASRModelSelection.FallbackReason, String) -> Void)? = nil
    ) -> ASRModelSelection {
        // Check environment override first
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        if let envValue = envValue, !envValue.isEmpty {
            // Environment override is explicit - use it
            let envModel = ASRModelSelection.fromEnvironmentValue(envValue, warningRecorder: warningRecorder)
            logger.info("Using environment override for ASR model: \(envModel.rawValue)")
            return envModel
        }

        // Fall back to saved preference read through the shared store
        let prefs: ASRModelPreferences
        if let store = store {
            prefs = load(from: store)
            logger.info("Using saved preference (shared store): \(prefs.selectedModel.rawValue) suite=\(store.suiteName)")
        } else {
            prefs = load()
            logger.info("Using saved preference (.standard): \(prefs.selectedModel.rawValue)")
        }
        return prefs.selectedModel
    }

    /// Check if the model is overridden by environment variable
    public static var isOverriddenByEnvironment: Bool {
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        return envValue != nil && !envValue!.isEmpty
    }

    /// Get a user-facing message about environment override status
    public static var environmentOverrideMessage: String? {
        guard isOverriddenByEnvironment else { return nil }
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName] ?? "unknown"
        return "Model is externally overridden via VOICEDOCK_ASR_MODEL=\(envValue). The picker selection will apply after a normal restart without this environment variable."
    }
}
