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
    /// Per-launch diagnostic recorder the provider records load/warmup outcomes
    /// into. Bound from the runtime composition through `ASRProviderFactory` so
    /// the provider and the AppDelegate that owns it share one recorder. A
    /// test host (VOICEDOCK_TEST_MODE=1) binds an isolated temp-directory
    /// recorder here; production binds `ModelLaunchRecorder.shared`. The
    /// provider never references `ModelLaunchRecorder.shared` directly.
    private let launchRecorder: ModelLaunchRecorder

    /// Initialize with optional custom storage (for testing) and an explicit
    /// descriptor. The per-launch recorder defaults to the runtime
    /// composition's recorder (production `.shared` in a normal launch, the
    /// isolated test-host recorder under the Xcode test host), so a provider
    /// constructed without an explicit recorder still records into the same
    /// recorder the owning AppDelegate owns.
    /// - Note: descriptor must be passed explicitly - no default value
    public init(
        storage: ModelStorage? = nil,
        descriptor: QwenModelDescriptor,
        launchRecorder: ModelLaunchRecorder? = nil
    ) {
        self.modelStorage = storage ?? ModelStorage()
        self.descriptor = descriptor
        self.launchRecorder = launchRecorder ?? VoiceDockRuntimeComposition.current.launchRecorder
    }

    /// Load the Qwen3 model from the canonical directory
    public func load() async throws {
        Self.writeASRDiagnostic("Qwen3ASRProvider_load_enter")
        logger.info("Loading Qwen3 model: \(self.descriptor.repoID)")
        Self.writeASRDiagnostic("descriptor_repoID=\(self.descriptor.repoID)")

        // Check if model is validly installed
        Self.writeASRDiagnostic("modelStorage_isModelValid_checking")
        let isValid = await modelStorage.isModelValid(descriptor)
        Self.writeASRDiagnostic("modelStorage_isModelValid_result=\(isValid ? "true" : "false")")
        guard isValid else {
            Self.writeASRDiagnostic("model_validation_failed")
            logger.error("Model not found or invalid at canonical path")
            launchRecorder.recordProviderLifecycle(
                loadResult: "fail:model-not-found",
                warmupResult: "skipped"
            )
            throw VoiceDockError.modelLoadFailed(underlying: NSError(
                domain: "Qwen3ASRProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model not found at canonical path. Install first using ModelInstaller."]
            ))
        }

        // Resolve canonical model directory
        Self.writeASRDiagnostic("resolving_model_directory")
        let modelDir = await modelStorage.modelDirectory(for: descriptor)
        Self.writeASRDiagnostic("model_directory_path=\(modelDir.path)")
        logger.info("Loading from: \(modelDir.path)")

        do {
            // Load using Qwen3ASRModel.fromModelDirectory
            Self.writeASRDiagnostic("Qwen3ASRModel_fromModelDirectory_will_call")
            model = try await Qwen3ASRModel.fromModelDirectory(modelDir)
            Self.writeASRDiagnostic("Qwen3ASRModel_fromModelDirectory_did_complete")
            logger.info("Qwen3 model loaded successfully")
            launchRecorder.recordProviderLifecycle(
                loadResult: "ok:\(modelDir.path)",
                warmupResult: "notrun-yet"
            )
        } catch {
            Self.writeASRDiagnostic("Qwen3ASRModel_fromModelDirectory_error:\(error.localizedDescription)")
            logger.error("Failed to load Qwen3 model: \(error.localizedDescription)")
            launchRecorder.recordProviderLifecycle(
                loadResult: "fail:\(error.localizedDescription)",
                warmupResult: "skipped"
            )
            throw VoiceDockError.modelLoadFailed(underlying: error)
        }
        Self.writeASRDiagnostic("Qwen3ASRProvider_load_exit")
    }

    /// Warm up the model with silent audio
    public func warmup() async throws {
        guard model != nil else {
            launchRecorder.recordProviderLifecycle(
                loadResult: "ok",
                warmupResult: "skipped:no-model"
            )
            throw VoiceDockError.modelWarmupFailed
        }

        logger.info("Warming up Qwen3 model")

        // Warmup with 1 second of silence at 16 kHz
        let silentAudio = MLXArray(Array(repeating: Float(0), count: 16_000))
        _ = model!.generate(audio: silentAudio, generationParameters: .init())
        logger.info("Qwen3 warmup complete")
        launchRecorder.recordProviderLifecycle(
            loadResult: "ok",
            warmupResult: "ok"
        )
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
        Self.writeASRDiagnostic("Qwen3ASRProvider_unload_called")
        model = nil
        Self.writeASRDiagnostic("Qwen3ASRProvider_unload_exit")
    }

    private static func writeASRDiagnostic(_ message: String) {
        let line = "[\(Date().ISO8601Format())] Qwen3ASRProvider: \(message)\n"
        let path = "/tmp/voicedock-asr-diagnostics.log"
        let url = URL(fileURLWithPath: path)
        if var data = line.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forUpdating: url) {
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: data)
                try? fileHandle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}