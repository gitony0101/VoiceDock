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

actor MLXAudioSTTProvider: ASRProvider {
    private var model: GLMASRModel?
    private let modelName = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"

    func load() async throws {
        do {
            model = try await GLMASRModel.fromPretrained(modelName)
        } catch {
            throw ASError.loadFailed
        }
    }

    func warmup() async throws {
        guard model != nil else {
            throw ASError.warmupFailed
        }
        // TODO: Run small dummy inference to warm up
    }

    func transcribe(audio: [Float]) async throws -> String {
        guard let model = model else {
            throw ASError.inferenceFailed
        }

        // Convert [Float] to MLXArray
        let audioArray = MLXArray(audio)

        let result = model.generate(audio: audioArray)
        return result.text
    }

    func unload() async {
        model = nil
    }
}