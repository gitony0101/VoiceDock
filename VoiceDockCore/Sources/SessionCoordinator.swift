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
    private var correctionEngine: TranscriptCorrectionEngine?
    private var audioBuffer: [Float] = []
    private var ready: Bool = false

    // Correction state
    private var lastRawTranscript: String?
    private var lastCorrectedTranscript: String?
    private var lastAppliedCorrections: [AppliedCorrection] = []

    private var modelLoadTask: Task<Void, Never>?

    // 0.3.1 lifecycle authority. One monotonic generation per coordinator.
    // An async workflow captures the generation current at spawn; once that
    // value is superseded (cleanup/retry), every authority checkpoint rejects
    // it, so a retired continuation can neither mutate workflow state nor
    // invoke transcript delivery — even when the underlying model computation
    // itself is not cooperatively cancellable.
    private var generation: Int = 0

    /// Explicitly owned transcription/delivery workflow task. At most one is
    /// authoritative at a time; cleanup() and retry() cancel it.
    private var transcriptionTask: Task<Void, Never>?

    /// Injectable delivery hook for deterministic stale-delivery tests.
    /// Production uses the injected `transcriptDestination` unchanged; tests
    /// may supply a recording destination through the existing initializer,
    /// so this stays nil in production paths.
    var deliverHook: ((String) -> Void)?

    // Dependency injection for testing
    public init(audioCapture: AudioCaptureProtocol? = nil,
         asrProvider: ASRProvider? = nil,
         transcriptDestination: TranscriptDestination? = nil,
         correctionEngine: TranscriptCorrectionEngine? = nil) {
        self.audioCapture = audioCapture
        self.asrProvider = asrProvider
        self.transcriptDestination = transcriptDestination
        self.correctionEngine = correctionEngine
        // Use Task.detached to ensure model loading runs independently of MainActor
        // Model loading is heavy (CPU/IO) and should not block the UI
        writeInitDiagnostic("SessionCoordinator_init_enter")
        let capturedGeneration = generation
        modelLoadTask = Task.detached { [weak self] in
            await self?.initialize(generation: capturedGeneration)
        }
        writeInitDiagnostic("SessionCoordinator_init_exit_task_created")
    }

    /// Authority checkpoint: true only if `generation` is still the current
    /// authoritative generation for this coordinator.
    private func isAuthoritative(_ generation: Int) -> Bool {
        return generation == self.generation
    }

    private func initialize(generation: Int) async {
        writeInitDiagnostic("initialize_enter")
        logger.info("Initializing coordinator...")
        writeInitDiagnostic("asrProvider_is_nil=\(asrProvider == nil ? "true" : "false")")
        do {
            // 0.3.1: authority check before entering .loadingModel
            guard isAuthoritative(generation) else {
                writeInitDiagnostic("initialize_stale_before_loadingModel")
                return
            }
            if asrProvider != nil {
                // Hop to MainActor for state update
                writeInitDiagnostic("state_will_set_to_loadingModel")
                await MainActor.run {
                    guard self.isAuthoritative(generation) else { return }
                    self.state = .loadingModel
                }
                writeInitDiagnostic("state_did_set_to_loadingModel")
                // P2-4 Fix: Add retry logic for model load (network issues)
                writeInitDiagnostic("loadModelWithRetry_will_call")
                try await loadModelWithRetry()
                writeInitDiagnostic("loadModelWithRetry_did_complete")

                // Phase 2B: Add warmup timing
                writeInitDiagnostic("warmup_will_start")
                let warmupStart = Date()
                try await asrProvider?.warmup()
                let warmupDuration = Date().timeIntervalSince(warmupStart)
                writeInitDiagnostic("warmup_did_complete_duration=\(String(format: "%.3f", warmupDuration))s")
                logger.info("ASR warmup completed in \(String(format: "%.3f", warmupDuration))s")
            } else {
                logger.warning("No ASR provider; skipping model load (test path).")
                writeInitDiagnostic("no_asr_provider_skipping_load")
            }

            // Initialize correction engine if not injected (production path)
            if correctionEngine == nil {
                logger.info("Creating production correction engine...")
                writeInitDiagnostic("creating_correction_engine")
                let engine = PersonalTranscriptCorrectionEngine()
                self.correctionEngine = engine
                writeInitDiagnostic("correction_engine_created")

                // Load user corrections once at startup (non-blocking, nonfatal)
                Task {
                    do {
                        try await engine.loadUserCorrections()
                        logger.info("User corrections loaded at startup")
                        writeInitDiagnostic("user_corrections_loaded")
                    } catch {
                        logger.warning("User corrections load skipped or failed: \(error.localizedDescription)")
                        writeInitDiagnostic("user_corrections_load_failed:\(error.localizedDescription)")
                    }
                }
            } else {
                logger.info("Correction engine injected (test path)")
                writeInitDiagnostic("correction_engine_injected")
            }

            // Hop to MainActor for state updates
            writeInitDiagnostic("state_will_set_to_ready")
            await MainActor.run { [weak self] in
                guard let self, self.isAuthoritative(generation) else { return }
                self.state = .ready
                self.ready = true
            }
            writeInitDiagnostic("state_did_set_to_ready")
            logger.info("Coordinator ready")
        } catch {
            let message = "Failed to initialize: \(error.localizedDescription)"
            writeInitDiagnostic("initialize_error:\(message)")
            // 0.3.1: a retired initialization finishing with an error is not a
            // new failure of the live generation — publish nothing.
            await MainActor.run { [weak self] in
                guard let self, self.isAuthoritative(generation) else { return }
                self.state = .failed(message)
            }
            logger.error("\(message, privacy: .public)")
        }
        writeInitDiagnostic("initialize_exit")
    }

    // P2-4 Fix: Retry logic for model loading with exponential backoff
    private func loadModelWithRetry() async throws {
        let maxRetries = 3
        var lastError: Error?
        let modelLoadStart = Date()

        for attempt in 1...maxRetries {
            do {
                logger.info("Loading ASR model (attempt \(attempt)/\(maxRetries))...")
                let loadStart = Date()
                try await asrProvider?.load()
                let loadDuration = Date().timeIntervalSince(loadStart)
                logger.info("ASR model loaded successfully in \(String(format: "%.3f", loadDuration))s")
                return
            } catch {
                lastError = error
                logger.warning("Model load attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Exponential backoff: 2s, 4s, 8s...
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    logger.info("Retrying in \(delay / 1_000_000_000) seconds...")
                    // Cancellation-aware sleep inside an owned workflow.
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        let totalLoadDuration = Date().timeIntervalSince(modelLoadStart)
        logger.error("Model load failed after \(String(format: "%.3f", totalLoadDuration))s total")
        throw lastError ?? VoiceDockError.modelLoadFailed(underlying: nil)
    }

    /// Try to start recording. Returns true if recording started, false if rejected (not ready).
    ///
    /// 0.3.1: only `.ready` accepts a new recording. `.idle` means the
    /// workflow has been torn down (cleanup/quit); it must not mean
    /// ready-to-record while provider teardown semantics are unresolved.
    /// - Returns: Bool indicating whether recording was accepted
    @discardableResult
    public func startRecording() -> Bool {
        logger.info("startRecording called, state=\(String(describing: self.state))")
        writeRuntimeDiagnostic("COORDINATOR_START_ENTER")
        guard state == .ready else {
            logger.warning("Not in ready state; ignoring")
            writeRuntimeDiagnostic("COORDINATOR_START_IGNORED")
            return false
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
            return false
        }
        writeRuntimeDiagnostic("AUDIO_START_EXIT")
        state = .listening
        writeRuntimeDiagnostic("COORDINATOR_STATE_LISTENING")
        writeRuntimeDiagnostic("COORDINATOR_START_EXIT")
        return true
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
        // 0.3.1: bind the captured samples immutably to this one workflow.
        // Every retry attempt below sees exactly this snapshot; no later
        // recording or coordinator mutation can alter it.
        audioBuffer = samples
        writeRuntimeDiagnostic("AUDIO_STOP_EXIT")
        writeRuntimeDiagnostic("COORDINATOR_STOP_AUDIO_RETURNED")
        writeRuntimeDiagnostic("TRANSCRIBE_SCHEDULED")
        let capturedGeneration = generation
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.transcribe(audio: samples, generation: capturedGeneration)
        }
        writeRuntimeDiagnostic("COORDINATOR_STOP_EXIT")
    }

    private func transcribe(audio: [Float], generation: Int) async {
        // 0.3.1: authority check before entering .transcribing
        guard isAuthoritative(generation) else {
            logger.info("Stale transcription workflow retired before transcribing")
            return
        }
        logger.info("Transcribing, \(audio.count) samples")
        state = .transcribing
        guard !audio.isEmpty else {
            logger.info("Empty recording; returning to ready")
            state = .ready
            return
        }

        // P2-4 Fix: Retry transcription on transient errors
        do {
            let rawResult = try await transcribeWithRetry(audio: audio)

            // Apply transcript correction
            let correctionResult = await applyCorrection(rawTranscript: rawResult)

            await deliver(rawTranscript: correctionResult.rawTranscript, correctedTranscript: correctionResult.correctedTranscript, generation: generation)
        } catch is CancellationError {
            // Owned workflow was cancelled by cleanup/supersession. The
            // generation guard has already revoked its authority; retire
            // silently without publishing failure.
            logger.info("Transcription workflow cancelled; retiring silently")
        } catch {
            let message = "Transcription failed: \(error.localizedDescription)"
            // 0.3.1: a retired workflow's error is not a live failure.
            guard isAuthoritative(generation) else {
                logger.info("Stale transcription workflow failed after retirement; not publishing failure")
                return
            }
            state = .failed(message)
            logger.error("\(message, privacy: .public)")
        }
    }

    /// Apply correction to a raw transcript based on user preferences.
    ///
    /// The correction engine is loaded once at startup - this method does NOT reload rules.
    /// Visible for testing via @testable import.
    func applyCorrection(rawTranscript: String) async -> CorrectionResult {
        let preferences = TranscriptCorrectionPreferences.load()

        guard let engine = correctionEngine else {
            logger.warning("No correction engine; delivering raw transcript")
            let result = CorrectionResult(rawTranscript: rawTranscript, correctedTranscript: rawTranscript, appliedCorrections: [])
            // Store for retrieval even when no engine
            self.lastRawTranscript = rawTranscript
            self.lastCorrectedTranscript = rawTranscript
            self.lastAppliedCorrections = []
            return result
        }

        // Apply correction based on mode
        let result: CorrectionResult
        switch preferences.mode {
        case .off:
            // Mode Off: deliver raw transcript unchanged
            result = CorrectionResult(rawTranscript: rawTranscript, correctedTranscript: rawTranscript, appliedCorrections: [])
        case .personalCorrection:
            // Mode Personal Correction: apply deterministic rules
            result = engine.correct(rawTranscript)
        }

        // Store correction state for retrieval
        self.lastRawTranscript = rawTranscript
        self.lastCorrectedTranscript = result.correctedTranscript
        self.lastAppliedCorrections = result.appliedCorrections

        if result.didChange {
            logger.info("Correction applied: \(result.appliedCorrections.count) rules fired")
        }

        return result
    }

    // P2-4 Fix: Retry logic for transcription with exponential backoff
    // Every attempt operates on the same immutable `audio` snapshot bound at
    // stopRecording() — never on mutable shared coordinator storage.
    private func transcribeWithRetry(audio: [Float]) async throws -> String {
        let maxRetries = 2
        var lastError: Error?
        let transcribeStart = Date()

        for attempt in 1...maxRetries {
            do {
                let resultStart = Date()
                let result = try await asrProvider?.transcribe(audio: audio) ?? ""
                let transcribeDuration = Date().timeIntervalSince(resultStart)
                logger.info("Transcription completed in \(String(format: "%.3f", transcribeDuration))s")
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                logger.warning("Transcription attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    // Cancellation-aware sleep inside an owned workflow.
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        let totalTranscribeDuration = Date().timeIntervalSince(transcribeStart)
        logger.error("Transcription failed after \(String(format: "%.3f", totalTranscribeDuration))s total")
        throw lastError ?? VoiceDockError.transcriptionFailed(underlying: nil)
    }

    private func deliver(rawTranscript: String, correctedTranscript: String, generation: Int) async {
        // 0.3.1: authority check immediately before entering .delivering and
        // before any external side effect (clipboard / Cmd-V / Return).
        guard isAuthoritative(generation) else {
            logger.info("Stale delivery retired before delivering")
            return
        }
        state = .delivering
        let deliverStart = Date()

        // Store correction state
        self.lastRawTranscript = rawTranscript
        self.lastCorrectedTranscript = correctedTranscript

        // Determine which text to deliver
        let textToDeliver = correctedTranscript

        if !textToDeliver.isEmpty {
            // 0.3.1: final authority gate around the external side effect.
            // Nothing outside this block posts keystrokes, so a retired
            // generation can never inject stale text into a newly focused app.
            guard isAuthoritative(generation) else {
                logger.info("Stale delivery retired before invoking destination")
                return
            }
            // Load user preferences and determine delivery policy
            let preferences = TranscriptDeliveryPreferences.load()
            let appProvider = NSWorkspaceFrontmostAppProvider()
            let policy = TranscriptDeliveryPolicy(
                preferences: preferences,
                appProvider: appProvider
            )
            let decision = policy.determineDelivery()

            // Execute delivery based on decision
            let resultMessage = transcriptDestination?.deliver(text: textToDeliver, decision: decision) ?? "Delivery failed"
            deliverHook?(textToDeliver)
            let deliverDuration = Date().timeIntervalSince(deliverStart)
            logger.info("deliver: \(resultMessage) (\(String(format: "%.3f", deliverDuration))s)")

            // 0.3.1: publication of the delivered transcript is itself an
            // authoritative write.
            guard isAuthoritative(generation) else {
                logger.info("Stale delivery retired before publishing transcript")
                return
            }
            currentTranscript = textToDeliver
        } else {
            logger.warning("No transcript text to deliver")
        }
        // Brief delay so the UI shows the delivering state
        // Cancellation-aware: a cancelled workflow exits here instead of
        // falling through to the final state write below.
        try? await Task.sleep(nanoseconds: 200_000_000)
        // 0.3.1: only the authoritative generation may restore .ready.
        guard isAuthoritative(generation) else {
            logger.info("Stale delivery tail retired; not restoring ready")
            return
        }
        state = .ready
    }

    /// Get the last raw transcript (uncorrected)
    public func getLastRawTranscript() -> String? {
        return lastRawTranscript
    }

    /// Get the last corrected transcript
    public func getLastCorrectedTranscript() -> String? {
        return lastCorrectedTranscript
    }

    /// Get the list of applied corrections from the last correction
    public func getLastAppliedCorrections() -> [AppliedCorrection] {
        return lastAppliedCorrections
    }

    /// Reload user corrections manually (for UI trigger)
    public func reloadUserCorrections() async {
        guard let engine = correctionEngine else {
            logger.warning("No correction engine; cannot reload")
            return
        }
        await engine.reloadUserCorrections()
    }

    /// Check if correction is enabled based on user preferences
    public func isCorrectionEnabled() -> Bool {
        let preferences = TranscriptCorrectionPreferences.load()
        return preferences.mode == .personalCorrection
    }

    /// 0.3.1: cleanup first revokes the authority of every outstanding
    /// workflow generation, then cancels owned tasks, then performs the same
    /// narrow resource teardown as before. Provider unload remains
    /// fire-and-forget under existing semantics (completion observability is
    /// a later slice); what changes is that no retired continuation can
    /// mutate state or invoke delivery after this returns.
    public func cleanup() {
        generation &+= 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        modelLoadTask?.cancel()
        audioCapture?.cancel()
        Task {
            await asrProvider?.unload()
        }
        state = .idle
    }

    public func quit() {
        // SessionCoordinator does NOT terminate the application
        // AppDelegate owns termination lifecycle via applicationShouldTerminate
        cleanup()
    }

    public func retry() async {
        await cleanupAndReset()
        let capturedGeneration = generation
        modelLoadTask = Task { [weak self] in
            await self?.initialize(generation: capturedGeneration)
        }
    }

    private func cleanupAndReset() async {
        generation &+= 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
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

    private func writeInitDiagnostic(_ message: String) {
        let line = "[\(Date().ISO8601Format())] SessionCoordinator: \(message)\n"
        let path = "/tmp/voicedock-init-diagnostics.log"
        let url = URL(fileURLWithPath: path)
        FileHandle.appendAnnotationsToLog(url, line)
    }
}

// MARK: - FileHandle helper for append-only diagnostics
extension FileHandle {
    static func appendAnnotationsToLog(_ url: URL, _ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let fileHandle = try? FileHandle(forUpdating: url) {
            try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: data)
            try? fileHandle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
