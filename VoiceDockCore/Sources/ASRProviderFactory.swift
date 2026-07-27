//
//  ASRProviderFactory.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ASRProviderFactory")

/// Environment variable name for selecting ASR model at runtime
public let ASRModelEnvVarName = "VOICEDOCK_ASR_MODEL"

/// Valid values for VOICEDOCK_ASR_MODEL environment variable
public enum ASRModelSelection: String, CaseIterable, Sendable {
    /// Default Qwen3 1.7B 4-bit model (Quality/default)
    case qwen3_1_7B_4bit = "qwen3-1.7b-4bit"
    /// Qwen3 0.6B 8-bit model (Fast)
    case qwen3_0_6B_8bit = "qwen3-0.6b-8bit"

    /// Display name for UI (e.g., "Quality — Qwen3 1.7B 4-bit")
    public var displayName: String {
        switch self {
        case .qwen3_1_7B_4bit:
            return "Quality — Qwen3 1.7B 4-bit"
        case .qwen3_0_6B_8bit:
            return "Fast — Qwen3 0.6B 8-bit"
        }
    }

    /// Get the corresponding QwenModelDescriptor
    public var modelDescriptor: QwenModelDescriptor {
        switch self {
        case .qwen3_1_7B_4bit:
            return .qwen3_1_7B_4bit
        case .qwen3_0_6B_8bit:
            return .qwen3_0_6B_8bit
        }
    }

    /// Warning types emitted during model selection (for testing)
    public enum FallbackReason: String, Equatable {
        case retired = "retired"
        case unknown = "unknown"
    }

    /// Parse from environment variable value
    /// - Parameters:
    ///   - value: Raw environment variable string
    ///   - warningRecorder: Optional closure to record warnings for testing. Called with (fallbackReason, message).
    /// - Returns: Model selection enum; defaults to `.qwen3_1_7B_4bit` for absent, empty, or invalid values
    public static func fromEnvironmentValue(_ value: String?, warningRecorder: ((FallbackReason, String) -> Void)? = nil) -> ASRModelSelection {
        guard let value = value, !value.isEmpty else {
            logger.info("No environment variable set or empty, using default: \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)")
            return .qwen3_1_7B_4bit
        }

        if let selection = ASRModelSelection(rawValue: value) {
            logger.info("Environment variable parsed: \(selection.rawValue)")
            return selection
        }

        // Handle retired model identifiers with warnings
        if value == "nemotron-0.6b-8bit" {
            let msg = "Retired ASR model: '\(value)' is no longer supported, falling back to \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)"
            logger.warning("\(msg, privacy: .public)")
            warningRecorder?(.retired, msg)
            return .qwen3_1_7B_4bit
        }

        if value == "qwen3-0.6b-6bit" {
            let msg = "Retired ASR model: '\(value)' is no longer supported, falling back to \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)"
            logger.warning("\(msg, privacy: .public)")
            warningRecorder?(.retired, msg)
            return .qwen3_1_7B_4bit
        }

        // Unknown or malformed value - fall back to Qwen3 1.7B 4-bit (default)
        let msg = "Unknown ASR model value: '\(value)', falling back to \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)"
        logger.warning("\(msg, privacy: .public)")
        warningRecorder?(.unknown, msg)
        return .qwen3_1_7B_4bit
    }

    /// Read directly from environment
    /// - Parameter warningRecorder: Optional closure to record warnings for testing
    public static func current(warningRecorder: ((FallbackReason, String) -> Void)? = nil) -> ASRModelSelection {
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        return fromEnvironmentValue(envValue, warningRecorder: warningRecorder)
    }
}

/// Result of creating an ASR provider via the factory.
///
/// Carries the provider AND the selection/descriptor that was actually used, so
/// callers can report the real active model rather than inferring it from the
/// picker or saved preference.
public struct ASRProviderFactoryResult: Sendable {
    public let provider: ASRProvider
    public let selection: ASRModelSelection
    public let descriptor: QwenModelDescriptor

    public init(provider: ASRProvider, selection: ASRModelSelection, descriptor: QwenModelDescriptor) {
        self.provider = provider
        self.selection = selection
        self.descriptor = descriptor
    }
}

/// Factory for creating ASR providers based on runtime configuration
public enum ASRProviderFactory {

    /// Resolve the per-launch recorder to bind into a created provider when the
    /// caller does not inject one explicitly. Routes through the runtime
    /// composition so the test host's isolated recorder is used when the Xcode
    /// TEST_HOST launched the host AppDelegate with `VOICEDOCK_TEST_MODE=1`;
    /// the production `ModelLaunchRecorder.shared` singleton is used in a
    /// normal app launch. The factory never references `.shared` directly.
    private static func resolveRecorder(_ recorder: ModelLaunchRecorder?) -> ModelLaunchRecorder {
        recorder ?? VoiceDockRuntimeComposition.current.launchRecorder
    }

    /// Create an ASR provider plus metadata based on environment variable or
    /// saved preference read through the shared store.
    ///
    /// - Parameters:
    ///   - store: Preference store. Defaults to the runtime composition's
    ///     store (`.production` in a normal launch, the isolated test-host
    ///     suite when `VOICEDOCK_TEST_MODE=1`), so the factory and ModelStatus
    ///     share one durable view of the selection across the relaunch boundary.
    ///   - launchRecorder: Per-launch diagnostic recorder to bind into the
    ///     created provider. Defaults to the runtime composition's recorder so
    ///     the provider records load/warmup outcomes into the same recorder the
    ///     AppDelegate owns — `ModelLaunchRecorder.shared` in production, the
    ///     isolated test-host recorder under the test host.
    /// - Returns: A `ASRProviderFactoryResult` carrying the provider, the
    ///   selection actually used, and the resolved `QwenModelDescriptor`.
    public static func createProviderWithMetadata(
        from store: ASRPreferenceStore? = nil,
        launchRecorder: ModelLaunchRecorder? = nil
    ) -> ASRProviderFactoryResult {
        let resolvedStore = store ?? VoiceDockRuntimeComposition.current.preferenceStore
        let resolvedRecorder = resolveRecorder(launchRecorder)
        let selection = ASRModelPreferences.effectiveModel(from: resolvedStore)
        let descriptor = selection.modelDescriptor
        logger.info("Creating ASR provider for: \(selection.rawValue) descriptor=\(descriptor.repoID) suite=\(resolvedStore.suiteName)")

        let provider = Qwen3ASRProvider(descriptor: descriptor, launchRecorder: resolvedRecorder)
        return ASRProviderFactoryResult(provider: provider, selection: selection, descriptor: descriptor)
    }

    /// Create an ASR provider based on environment variable or saved preference
    /// - Parameter store: Preference store (defaults to the runtime composition's
    ///   production store in a normal launch).
    /// - Returns: Configured ASRProvider instance
    /// - Note: Uses precedence:
    ///   1. VOICEDOCK_ASR_MODEL environment variable
    ///   2. Saved user preference (ASRModelPreferences) read through `store`
    ///   3. Quality default (qwen3-1.7b-4bit)
    public static func createProvider(
        from store: ASRPreferenceStore? = nil,
        launchRecorder: ModelLaunchRecorder? = nil
    ) -> ASRProvider {
        createProviderWithMetadata(from: store, launchRecorder: launchRecorder).provider
    }

    /// Create an ASR provider for a specific model selection (testing)
    /// - Parameter selection: Explicit model selection
    /// - Parameter launchRecorder: Per-launch diagnostic recorder to bind into
    ///   the created provider; defaults to the runtime composition's recorder.
    /// - Returns: Configured ASRProvider instance
    public static func createProvider(
        for selection: ASRModelSelection,
        launchRecorder: ModelLaunchRecorder? = nil
    ) -> ASRProvider {
        logger.info("Creating ASR provider (explicit): \(selection.rawValue)")
        return Qwen3ASRProvider(
            descriptor: selection.modelDescriptor,
            launchRecorder: resolveRecorder(launchRecorder)
        )
    }

    /// Create an ASR provider using saved preferences only (ignores environment)
    /// - Parameter store: Preference store (defaults to the runtime composition's
    ///   production store in a normal launch).
    /// - Returns: Configured ASRProvider instance
    public static func createProviderFromSavedPreference(
        from store: ASRPreferenceStore? = nil,
        launchRecorder: ModelLaunchRecorder? = nil
    ) -> ASRProvider {
        let resolvedStore = store ?? VoiceDockRuntimeComposition.current.preferenceStore
        let resolvedRecorder = resolveRecorder(launchRecorder)
        let prefs = ASRModelPreferences.load(from: resolvedStore)
        logger.info("Creating ASR provider from saved preference: \(prefs.selectedModel.rawValue) suite=\(resolvedStore.suiteName)")

        return Qwen3ASRProvider(descriptor: prefs.selectedModel.modelDescriptor, launchRecorder: resolvedRecorder)
    }
}