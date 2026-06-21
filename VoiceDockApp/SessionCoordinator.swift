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
    private let lock = NSLock()

    init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        do {
            audioCapture = AudioCapture()
            asrProvider = MLXAudioSTTProvider()
            transcriptDestination = TranscriptDestination()

            try await asrProvider?.load()
            try await asrProvider?.warmup()

            await MainActor.run {
                state = .ready
            }
        } catch {
            await MainActor.run {
                state = .error("Failed to initialize: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func startRecording() {
        Task { @MainActor in
            guard state == .ready || state == .idle else { return }
            state = .listening
            audioBuffer.removeAll()
            audioCapture?.start()
        }
    }

    nonisolated func stopRecording() {
        Task { @MainActor in
            guard state == .listening else { return }
            audioBuffer = audioCapture?.stop() ?? []
            await transcribe()
        }
    }

    private func transcribe() async {
        state = .transcribing
        do {
            let result = try await asrProvider?.transcribe(audio: audioBuffer)
            await deliver(text: result)
        } catch {
            await MainActor.run {
                state = .error("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private func deliver(text: String?) async {
        state = .delivering
        if let text = text {
            transcriptDestination?.paste(text: text)
        }
        await MainActor.run {
            state = .ready
        }
    }

    nonisolated func cleanup() {
        Task { @MainActor in
            audioCapture?.cancel()
            await asrProvider?.unload()
            state = .idle
        }
    }
}