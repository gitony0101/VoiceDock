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
    /// Default Qwen3 1.7B 4-bit model (Quality)
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

    /// Parse from environment variable value
    /// - Parameter value: Raw environment variable string
    /// - Returns: Model selection enum; defaults to `.qwen3_1_7B_4bit` for absent, empty, or invalid values
    public static func fromEnvironmentValue(_ value: String?) -> ASRModelSelection {
        guard let value = value, !value.isEmpty else {
            logger.info("No environment variable set or empty, using default: \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)")
            return .qwen3_1_7B_4bit
        }

        if let selection = ASRModelSelection(rawValue: value) {
            logger.info("Environment variable parsed: \(selection.rawValue)")
            return selection
        }

        // Unknown or malformed value - fall back to Qwen3 1.7B 4-bit (Quality/default)
        logger.warning("Unknown ASR model value: '\(value)', falling back to \(ASRModelSelection.qwen3_1_7B_4bit.rawValue)")
        return .qwen3_1_7B_4bit
    }

    /// Read directly from environment
    public static func current() -> ASRModelSelection {
        let envValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        return fromEnvironmentValue(envValue)
    }
}

/// Factory for creating ASR providers based on runtime configuration
public enum ASRProviderFactory {

    /// Create an ASR provider based on environment variable
    /// - Returns: Configured ASRProvider instance
    /// - Note: Uses VOICEDOCK_ASR_MODEL environment variable
    ///   - Not set, empty, or invalid: Qwen3ASRProvider with 1.7B 4-bit (Quality/default)
    ///   - "qwen3-1.7b-4bit": Qwen3ASRProvider with 1.7B 4-bit descriptor
    ///   - "qwen3-0.6b-8bit": Qwen3ASRProvider with 0.6B 8-bit descriptor
    public static func createProvider() -> ASRProvider {
        let selection = ASRModelSelection.current()
        logger.info("Creating ASR provider for: \(selection.rawValue)")

        switch selection {
        case .qwen3_1_7B_4bit, .qwen3_0_6B_8bit:
            logger.info("Using Qwen3 ASR provider: \(selection.rawValue)")
            return Qwen3ASRProvider(descriptor: selection.modelDescriptor)
        }
    }

    /// Create an ASR provider for a specific model selection (testing)
    /// - Parameter selection: Explicit model selection
    /// - Returns: Configured ASRProvider instance
    public static func createProvider(for selection: ASRModelSelection) -> ASRProvider {
        logger.info("Creating ASR provider (explicit): \(selection.rawValue)")

        switch selection {
        case .qwen3_0_6B_8bit, .qwen3_1_7B_4bit:
            return Qwen3ASRProvider(descriptor: selection.modelDescriptor)
        }
    }
}