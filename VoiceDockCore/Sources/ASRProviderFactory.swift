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
public enum ASRModelSelection: String, CaseIterable {
    /// Default Qwen3 1.7B 4-bit model (Quality/default)
    case qwen3_1_7B_4bit = "qwen3-1.7b-4bit"
    /// Qwen3 0.6B 8-bit model (Fast)
    case qwen3_0_6B_8bit = "qwen3-0.6b-8bit"

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

/// Factory for creating ASR providers based on runtime configuration
public enum ASRProviderFactory {

    /// Create an ASR provider based on environment variable
    /// - Returns: Configured ASRProvider instance
    /// - Note: Uses VOICEDOCK_ASR_MODEL environment variable
    ///   - Not set, empty, or invalid: Qwen3ASRProvider with 1.7B 4-bit (default)
    ///   - "qwen3-1.7b-4bit": Qwen3ASRProvider with 1.7B 4-bit descriptor
    ///   - "qwen3-0.6b-8bit": Qwen3ASRProvider with 0.6B 8-bit descriptor
    ///   - Retired values ("nemotron-0.6b-8bit", "qwen3-0.6b-6bit"): fall back to default with warning
    public static func createProvider() -> ASRProvider {
        let selection = ASRModelSelection.current()
        logger.info("Creating ASR provider for: \(selection.rawValue)")

        return Qwen3ASRProvider(descriptor: selection.modelDescriptor)
    }

    /// Create an ASR provider for a specific model selection (testing)
    /// - Parameter selection: Explicit model selection
    /// - Returns: Configured ASRProvider instance
    public static func createProvider(for selection: ASRModelSelection) -> ASRProvider {
        logger.info("Creating ASR provider (explicit): \(selection.rawValue)")

        return Qwen3ASRProvider(descriptor: selection.modelDescriptor)
    }
}