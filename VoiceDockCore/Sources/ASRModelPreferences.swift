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
/// 3. Quality default (qwen3-1.7b-4bit)
///
/// When an environment override is active, the UI must clearly indicate that
/// the model picker will apply only after a normal restart without the override.
public struct ASRModelPreferences: Equatable, Sendable {
    private static let selectedModelKey = "voicedock.selectedASRModel"
    private static let hasSeenModelSelectionKey = "voicedock.hasSeenModelSelection"

    /// The user's selected model identifier
    public var selectedModel: ASRModelSelection

    /// Whether the user has been shown the model selection UI (for onboarding)
    public var hasSeenModelSelection: Bool

    public init(selectedModel: ASRModelSelection = .qwen3_1_7B_4bit, hasSeenModelSelection: Bool = false) {
        self.selectedModel = selectedModel
        self.hasSeenModelSelection = hasSeenModelSelection
    }

    /// Load preferences from UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    /// - Returns: The current preferences, using Quality default for any missing keys.
    public static func load(from defaults: UserDefaults = .standard) -> ASRModelPreferences {
        let modelRaw = defaults.string(forKey: selectedModelKey)
        let hasSeen = defaults.object(forKey: hasSeenModelSelectionKey) as? Bool ?? false

        // Parse saved model, default to Quality if missing or invalid
        let model: ASRModelSelection
        if let raw = modelRaw, let selection = ASRModelSelection(rawValue: raw) {
            model = selection
        } else {
            model = .qwen3_1_7B_4bit  // Quality default
        }

        logger.debug("Loaded ASR model preferences: selectedModel=\(model.rawValue)")
        return ASRModelPreferences(selectedModel: model, hasSeenModelSelection: hasSeen)
    }

    /// Save preferences to UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use (defaults to .standard)
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
        defaults.set(hasSeenModelSelection, forKey: Self.hasSeenModelSelectionKey)
        logger.info("Saved ASR model preferences: selectedModel=\(selectedModel.rawValue)")
    }

    /// Reset to default values
    public static func reset(to defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: selectedModelKey)
        defaults.removeObject(forKey: hasSeenModelSelectionKey)
        logger.info("Reset ASR model preferences to defaults")
    }

    /// Determine the effective model for this launch.
    ///
    /// Precedence:
    /// 1. Environment override (VOICEDOCK_ASR_MODEL)
    /// 2. Saved user preference
    /// 3. Quality default
    ///
    /// - Parameter warningRecorder: Optional closure to record warnings for testing
    /// - Returns: The model to use for this launch
    public static func effectiveModel(warningRecorder: ((ASRModelSelection.FallbackReason, String) -> Void)? = nil) -> ASRModelSelection {
        // Check environment override first
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        if let envValue = envValue, !envValue.isEmpty {
            // Environment override is explicit - use it
            let envModel = ASRModelSelection.fromEnvironmentValue(envValue, warningRecorder: warningRecorder)
            logger.info("Using environment override for ASR model: \(envModel.rawValue)")
            return envModel
        }

        // Fall back to saved preference
        let prefs = load()
        logger.info("Using saved preference for ASR model: \(prefs.selectedModel.rawValue)")
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