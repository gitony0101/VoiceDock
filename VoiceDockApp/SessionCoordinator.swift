//
//  SessionCoordinator.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import Combine

/// Owns the workflow state and orchestrates the PTT session
@MainActor
final class SessionCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case listening
        case transcribing
        case delivering
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentTranscript: String?

    private var audioCapture: AudioCapture?
    private var asrProvider: ASRProvider?
    private var transcriptDestination: TranscriptDestination?
    private var audioBuffer: [Float] = []

    init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        // TODO: Initialize dependencies
        // audioCapture = AudioCapture()
        // asrProvider = MLXAudioSTTProvider()
        // transcriptDestination = TranscriptDestination()
    }

    nonisolated func startRecording() {
        Task { @MainActor in
            guard state == .ready || state == .idle else { return }
            state = .listening
            audioBuffer.removeAll()
            // TODO: Start audio capture
        }
    }

    nonisolated func stopRecording() {
        Task { @MainActor in
            guard state == .listening else { return }
            // TODO: Stop audio capture
            await transcribe()
        }
    }

    private func transcribe() async {
        state = .transcribing
        // TODO: Call ASR provider
        // let result = try? await asrProvider?.transcribe(audio: audioBuffer)
        // await deliver(text: result)
    }

    private func deliver(text: String?) async {
        state = .delivering
        // TODO: Paste to focused application
        state = .ready
    }

    nonisolated func cleanup() {
        Task { @MainActor in
            // TODO: Clean up resources
        }
    }
}