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
        case nemotron = "Nemotron-ASR"
    }

    /// Qwen3-ASR-0.6B-6bit model descriptor
    public static let qwen3_0_6B_6bit = QwenModelDescriptor(
        repoID: "mlx-community/Qwen3-ASR-0.6B-6bit",
        displayName: "Qwen3 ASR 0.6B 6-bit",
        canonicalDirectoryName: "Qwen3-ASR-0.6B-6bit",
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

    /// Qwen3-ASR-0.6B-8bit model descriptor (Duel candidate 1)
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

    /// Qwen3-ASR-1.7B-4bit model descriptor (Duel candidate 2)
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

    /// Nemotron-3.5-ASR-0.6B-8bit model descriptor (metadata only)
    public static let nemotron_0_6B_8bit = QwenModelDescriptor(
        repoID: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
        displayName: "Nemotron ASR 0.6B 8-bit",
        canonicalDirectoryName: "nemotron-3.5-asr-streaming-0.6b-8bit",
        family: .nemotron,
        requiredFiles: [
            "config.json",
            "vocab.txt"
        ],
        indexedFiles: []
    )

    /// All supported models
    public static let all: [QwenModelDescriptor] = [
        .qwen3_0_6B_6bit,
        .qwen3_0_6B_8bit,
        .qwen3_1_7B_4bit,
        .nemotron_0_6B_8bit
    ]
}