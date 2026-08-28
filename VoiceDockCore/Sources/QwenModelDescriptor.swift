//
//  QwenModelDescriptor.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

/// Model descriptor for ASR models supported by VoiceDock
public struct QwenModelDescriptor: Equatable, Sendable {
    /// Stable identifier (Hugging Face repo ID)
    public let repoID: String
    /// Display name for UI
    public let displayName: String
    /// Canonical directory name in Application Support
    public let canonicalDirectoryName: String
    /// Model family
    public let family: ModelFamily
    /// Required files for validation
    public let requiredFiles: [String]
    /// Optional indexed files (validated differently)
    public let indexedFiles: [String]

    public enum ModelFamily: String, Sendable {
        case qwen3 = "Qwen3-ASR"
    }

    /// Qwen3-ASR-0.6B-8bit model descriptor (Fast, default)
    public static let qwen3_0_6B_8bit = QwenModelDescriptor(
        repoID: "mlx-community/Qwen3-ASR-0.6B-8bit",
        displayName: "Qwen3 ASR 0.6B 8-bit",
        canonicalDirectoryName: "Qwen3-ASR-0.6B-8bit",
        family: .qwen3,
        requiredFiles: [
            "config.json",
            "tokenizer_config.json",
            "merges.txt",
            "vocab.json",
            "preprocessor_config.json",
            "generation_config.json"
        ],
        indexedFiles: [
            "model.safetensors.index.json"
        ]
    )

    /// Qwen3-ASR-1.7B-4bit model descriptor (Quality, optional)
    public static let qwen3_1_7B_4bit = QwenModelDescriptor(
        repoID: "mlx-community/Qwen3-ASR-1.7B-4bit",
        displayName: "Qwen3 ASR 1.7B 4-bit",
        canonicalDirectoryName: "Qwen3-ASR-1.7B-4bit",
        family: .qwen3,
        requiredFiles: [
            "config.json",
            "tokenizer_config.json",
            "merges.txt",
            "vocab.json",
            "preprocessor_config.json",
            "generation_config.json"
        ],
        indexedFiles: [
            "model.safetensors.index.json"
        ]
    )

    /// All supported models
    public static let all: [QwenModelDescriptor] = [
        .qwen3_0_6B_8bit,
        .qwen3_1_7B_4bit
    ]
}