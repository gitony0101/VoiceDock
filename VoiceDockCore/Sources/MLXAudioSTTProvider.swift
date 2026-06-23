//
//  MLXAudioSTTProvider.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "MLXAudioSTTProvider")

public actor MLXAudioSTTProvider: ASRProvider {
    private var model: NemotronASRModel?
    private let modelName = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
    private let maxRetries = 3

    public init() {}

    public func load() async throws {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                logger.info("Loading Nemotron model: \(self.modelName, privacy: .public) (attempt \(attempt))")
                model = try await NemotronASRModel.fromPretrained(modelName)
                logger.info("Nemotron model loaded successfully")
                return
            } catch {
                lastError = error
                logger.warning("Nemotron load attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        throw VoiceDockError.modelLoadFailed(underlying: lastError)
    }

    public func warmup() async throws {
        guard model != nil else {
            throw VoiceDockError.modelWarmupFailed
        }
        // Warmup with short silent audio to initialize inference pipeline (1s of silence at 16 kHz).
        logger.info("Warming up Nemotron model")
        let silentAudio = MLXArray(Array(repeating: Float(0), count: 16_000))
        _ = model!.generate(audio: silentAudio, generationParameters: .init())
        logger.info("Warmup complete")
    }

    public func transcribe(audio: [Float]) async throws -> String {
        guard let model = model else {
            throw VoiceDockError.modelInferenceFailed(underlying: nil)
        }
        logger.info("Transcribing \(audio.count) samples")
        let audioArray = MLXArray(audio)
        let result = model.generate(audio: audioArray, generationParameters: .init())
        logger.info("Transcription complete")
        return result.text
    }

    public func unload() async {
        logger.info("Unloading Nemotron model")
        model = nil
    }
}