//
//  Qwen3ASRProvider.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "Qwen3ASRProvider")

/// Qwen3-ASR provider implementing the ASRProvider protocol
public actor Qwen3ASRProvider: ASRProvider {
    private var model: Qwen3ASRModel?
    private let modelStorage: ModelStorage
    private let descriptor: QwenModelDescriptor

    /// Initialize with optional custom storage (for testing)
    /// - Note: descriptor must be passed explicitly - no default value
    public init(storage: ModelStorage? = nil, descriptor: QwenModelDescriptor) {
        self.modelStorage = storage ?? ModelStorage()
        self.descriptor = descriptor
    }

    /// Load the Qwen3 model from the canonical directory
    public func load() async throws {
        logger.info("Loading Qwen3 model: \(self.descriptor.repoID)")

        // Check if model is validly installed
        guard await modelStorage.isModelValid(descriptor) else {
            logger.error("Model not found or invalid at canonical path")
            throw VoiceDockError.modelLoadFailed(underlying: NSError(
                domain: "Qwen3ASRProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model not found at canonical path. Install first using ModelInstaller."]
            ))
        }

        // Resolve canonical model directory
        let modelDir = await modelStorage.modelDirectory(for: descriptor)
        logger.info("Loading from: \(modelDir.path)")

        do {
            // Load using Qwen3ASRModel.fromModelDirectory
            model = try await Qwen3ASRModel.fromModelDirectory(modelDir)
            logger.info("Qwen3 model loaded successfully")
        } catch {
            logger.error("Failed to load Qwen3 model: \(error.localizedDescription)")
            throw VoiceDockError.modelLoadFailed(underlying: error)
        }
    }

    /// Warm up the model with silent audio
    public func warmup() async throws {
        guard model != nil else {
            throw VoiceDockError.modelWarmupFailed
        }

        logger.info("Warming up Qwen3 model")

        // Warmup with 1 second of silence at 16 kHz
        let silentAudio = MLXArray(Array(repeating: Float(0), count: 16_000))
        _ = model!.generate(audio: silentAudio, generationParameters: .init())
        logger.info("Qwen3 warmup complete")
    }

    /// Transcribe audio using the Qwen3 model
    /// - Parameter audio: 16 kHz mono Float32 samples
    /// - Returns: Trimmed transcript text
    public func transcribe(audio: [Float]) async throws -> String {
        guard let model = model else {
            throw VoiceDockError.modelInferenceFailed(underlying: nil)
        }

        // Handle empty input
        guard !audio.isEmpty else {
            logger.info("Empty audio input, returning empty string")
            return ""
        }

        logger.info("Transcribing \(audio.count) samples with Qwen3")

        let audioArray = MLXArray(audio)
        let result = model.generate(audio: audioArray, generationParameters: .init())

        logger.info("Qwen3 transcription complete")
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unload the model and release resources
    public func unload() async {
        logger.info("Unloading Qwen3 model")
        model = nil
    }
}