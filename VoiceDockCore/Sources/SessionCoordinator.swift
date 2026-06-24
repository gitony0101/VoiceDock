//
//  SessionCoordinator.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "SessionCoordinator")

/// Owns the workflow state and orchestrates the PTT session
@MainActor
public final class SessionCoordinator: ObservableObject {
    public enum State: Equatable {
        case starting
        case waitingForMicrophonePermission
        case waitingForAccessibilityPermission
        case loadingModel
        case ready
        case listening
        case transcribing
        case delivering
        case failed(String)
        case idle
    }

    @Published public private(set) var state: State = .starting
    @Published public private(set) var currentTranscript: String?

    private var audioCapture: AudioCaptureProtocol?
    private var asrProvider: ASRProvider?
    private var transcriptDestination: TranscriptDestination?
    private var audioBuffer: [Float] = []
    private var ready: Bool = false

    private var modelLoadTask: Task<Void, Never>?
    private var initialState: State = .starting

    // Dependency injection for testing
    public init(audioCapture: AudioCaptureProtocol? = nil,
         asrProvider: ASRProvider? = nil,
         transcriptDestination: TranscriptDestination? = nil) {
        self.audioCapture = audioCapture
        self.asrProvider = asrProvider
        self.transcriptDestination = transcriptDestination
        modelLoadTask = Task { [weak self] in
            await self?.initialize()
        }
    }

    private func initialize() async {
        logger.info("Initializing coordinator...")
        do {
            if asrProvider != nil {
                state = .loadingModel
                // P2-4 Fix: Add retry logic for model load (network issues)
                try await loadModelWithRetry()
                try await asrProvider?.warmup()
            } else {
                logger.warning("No ASR provider; skipping model load (test path).")
            }

            state = .ready
            ready = true
            logger.info("Coordinator ready")
        } catch {
            let message = "Failed to initialize: \(error.localizedDescription)"
            state = .failed(message)
            logger.error("\(message, privacy: .public)")
        }
    }

    // P2-4 Fix: Retry logic for model loading with exponential backoff
    private func loadModelWithRetry() async throws {
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                logger.info("Loading ASR model (attempt \(attempt)/\(maxRetries))...")
                try await asrProvider?.load()
                logger.info("ASR model loaded successfully")
                return
            } catch {
                lastError = error
                logger.warning("Model load attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Exponential backoff: 2s, 4s, 8s...
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    logger.info("Retrying in \(delay / 1_000_000_000) seconds...")
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? VoiceDockError.modelLoadFailed(underlying: nil)
    }

    public func startRecording() {
        logger.info("startRecording called, state=\(String(describing: self.state))")
        writeRuntimeDiagnostic("COORDINATOR_START_ENTER")
        guard state == .ready || state == .idle else {
            logger.warning("Not in ready state; ignoring")
            writeRuntimeDiagnostic("COORDINATOR_START_IGNORED")
            return
        }
        audioBuffer.removeAll()
        writeRuntimeDiagnostic("AUDIO_START_ENTER")
        do {
            try audioCapture?.start()
        } catch {
            let message = "Failed to start audio capture: \(error.localizedDescription)"
            state = .failed(message)
            audioCapture?.cancel()
            logger.error("\(message, privacy: .public)")
            writeRuntimeDiagnostic("AUDIO_START_FAILED")
            return
        }
        writeRuntimeDiagnostic("AUDIO_START_EXIT")
        state = .listening
        writeRuntimeDiagnostic("COORDINATOR_STATE_LISTENING")
        writeRuntimeDiagnostic("COORDINATOR_START_EXIT")
    }

    public func stopRecording() {
        logger.info("stopRecording called, state=\(String(describing: self.state))")
        writeRuntimeDiagnostic("COORDINATOR_STOP_ENTER")
        guard state == .listening else {
            logger.warning("Not in listening state; ignoring")
            writeRuntimeDiagnostic("COORDINATOR_STOP_IGNORED")
            return
        }
        writeRuntimeDiagnostic("AUDIO_STOP_ENTER")
        let samples = audioCapture?.stop() ?? []
        writeRuntimeDiagnostic("CAPTURED_SAMPLE_COUNT=\(samples.count)")
        audioBuffer = samples
        writeRuntimeDiagnostic("AUDIO_STOP_EXIT")
        writeRuntimeDiagnostic("COORDINATOR_STOP_AUDIO_RETURNED")
        writeRuntimeDiagnostic("TRANSCRIBE_SCHEDULED")
        Task { [weak self] in
            await self?.transcribe()
        }
        writeRuntimeDiagnostic("COORDINATOR_STOP_EXIT")
    }

    private func transcribe() async {
        logger.info("Transcribing, \(self.audioBuffer.count) samples")
        state = .transcribing
        guard !audioBuffer.isEmpty else {
            logger.info("Empty recording; returning to ready")
            state = .ready
            return
        }

        // P2-4 Fix: Retry transcription on transient errors
        do {
            let result = try await transcribeWithRetry()
            await deliver(text: result)
        } catch {
            let message = "Transcription failed: \(error.localizedDescription)"
            state = .failed(message)
            logger.error("\(message, privacy: .public)")
        }
    }

    // P2-4 Fix: Retry logic for transcription with exponential backoff
    private func transcribeWithRetry() async throws -> String {
        let maxRetries = 2
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await asrProvider?.transcribe(audio: audioBuffer) ?? ""
            } catch {
                lastError = error
                logger.warning("Transcription attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? VoiceDockError.transcriptionFailed(underlying: nil)
    }

    private func deliver(text: String?) async {
        state = .delivering
        if let text = text, !text.isEmpty {
            // Load user preferences and determine delivery policy
            let preferences = TranscriptDeliveryPreferences.load()
            let appProvider = NSWorkspaceFrontmostAppProvider()
            let policy = TranscriptDeliveryPolicy(
                preferences: preferences,
                appProvider: appProvider
            )
            let decision = policy.determineDelivery()

            // Execute delivery based on decision
            let resultMessage = transcriptDestination?.deliver(text: text, decision: decision) ?? "Delivery failed"
            logger.info("deliver: \(resultMessage)")

            currentTranscript = text
        } else {
            logger.warning("No transcript text to deliver")
        }
        // Brief delay so the UI shows the delivering state
        try? await Task.sleep(nanoseconds: 200_000_000)
        state = .ready
    }

    public func cleanup() {
        audioCapture?.cancel()
        Task {
            await asrProvider?.unload()
        }
        state = .idle
    }

    public func quit() {
        cleanup()
        NSApplication.shared.terminate(nil)
    }

    public func retry() async {
        await cleanupAndReset()
        modelLoadTask = Task { [weak self] in
            await self?.initialize()
        }
    }

    private func cleanupAndReset() async {
        if let task = modelLoadTask {
            task.cancel()
        }
    }

    private func writeRuntimeDiagnostic(_ message: String) {
        let line = "[\(Date().ISO8601Format())] \(message)\n"
        if var data = line.data(using: .utf8) {
            let path = "/tmp/voicedock-runtime-diagnostics.log"
            let url = URL(fileURLWithPath: path)
            if let existing = try? Data(contentsOf: url) {
                data.append(existing)
            }
            try? data.write(to: url)
        }
    }
}
