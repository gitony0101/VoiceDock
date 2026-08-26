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
        /// Workflow authority has been revoked and provider teardown has
        /// started but is not yet proven complete. Recording is rejected.
        case cleaningUp
        /// Cleanup has completed: workflow authority retired AND the provider
        /// unload for that cleanup generation finished.
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

    // 0.3.3 recovery ownership. The 0.3.1 `generation` remains the sole
    // authority for state writes and external side effects; this metadata
    // only identifies WHICH lifecycle task owns WHICH generation so a
    // retired initialization can be drained without ever touching a newer
    // recovery generation's task (legacy R2/R4 evidence).
    private var modelLoadTaskGeneration: Int = 0

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

    // 0.3.2 observable teardown. One owned unload operation per cleanup
    // cycle; completion is awaited before `.idle` is published, and repeat
    // cleanup calls join the in-flight unload instead of starting a second.
    private var providerUnloadTask: Task<Void, Never>?

    // 0.3.3 recovery window flag. True from the synchronous entry of retry()
    // until the new lifecycle task is spawned. While a recovery drains the
    // previous lifecycle task or an in-flight canonical teardown, the
    // teardown completion may transiently publish `.idle`; this flag keeps
    // PTT admission closed across that window so recording stays
    // ready-only-and-not-recovering for the entire recovery.
    private var isRecovering = false

    /// Cleanup-cycle identity. Incremented ONLY when a brand-new unload
    /// begins — never when a duplicate cleanup() call joins an in-flight
    /// teardown — so a joined cleanup cannot invalidate the completion that
    /// is supposed to publish `.idle`. Deliberately distinct from the
    /// product-workflow `generation`: cleanup completion has its own
    /// authority (0.3.2 §11).
    private var cleanupCycle: Int = 0

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
        // 0.3.3: the initial lifecycle task owns `capturedGeneration`.
        modelLoadTaskGeneration = capturedGeneration
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
            // 0.3.3 (legacy R7 backoff): a retired initialization generation
            // must stop burning retry-backoff time once superseded. Task
            // cancellation is the retirement signal; generation authority
            // remains the correctness boundary for any non-cancellable work.
            try Task.checkCancellation()
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
    /// 0.3.1/0.3.2: only `.ready` accepts a new recording. `.idle` means the
    /// workflow has been torn down and provider unload has completed; it must
    /// not mean ready-to-record. `.cleaningUp` means teardown is in flight.
    /// - Returns: Bool indicating whether recording was accepted
    @discardableResult
    public func startRecording() -> Bool {
        logger.info("startRecording called, state=\(String(describing: self.state))")
        writeRuntimeDiagnostic("COORDINATOR_START_ENTER")
        // 0.3.3 (R7): recording is rejected for the entire recovery window,
        // including while recovery drains a prior lifecycle task or an
        // in-flight teardown whose completion may transiently publish .idle.
        guard state == .ready, !isRecovering else {
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

    /// 0.3.2 cleanup semantics:
    ///
    /// 1. Retire the current workflow generation (0.3.1 authority rule).
    /// 2. Cancel owned initialization/transcription tasks.
    /// 3. Cancel audio capture.
    /// 4. Enter `.cleaningUp` (authority revoked; teardown started but not
    ///    proven complete).
    /// 5. Begin exactly one provider unload (owned task).
    /// 6. Only after that unload completes, publish `.idle`.
    ///
    /// Idempotence: a second cleanup while teardown is in flight joins the
    /// existing operation — it does not create a second unload, regress the
    /// state, or re-enable recording.
    ///
    /// The completion closure runs as part of the owned unload task and is
    /// the only writer of the terminal `.idle`. Because the task captured
    /// its own cleanup token at creation, later generation bumps (from a
    /// future re-cleanup cycle) cannot invalidate this completion: the
    /// cleanup authority is distinct from the product workflow generation.
    public func cleanup() {
        // Steps 1–2: revoke product-workflow authority and cancel owned tasks.
        // 0.3.3: also retire the lifecycle task ownership record so a
        // subsequent recovery never drains this retired task.
        generation &+= 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        modelLoadTask?.cancel()
        modelLoadTask = nil
        modelLoadTaskGeneration = generation

        // Step 3: stop audio capture synchronously (existing contract).
        audioCapture?.cancel()

        // Step 4+5: enter .cleaningUp and start exactly one unload.
        if providerUnloadTask == nil {
            state = .cleaningUp
            cleanupCycle &+= 1
            let cycle = cleanupCycle
            let capturedGeneration = generation
            providerUnloadTask = Task { [weak self] in
                await self?.performProviderUnload(cycle: cycle, generation: capturedGeneration)
            }
        } else {
            // Teardown already in flight from an earlier cleanup call:
            // observe it without creating duplicate work or regressing state.
            logger.info("Cleanup already in progress; joining existing teardown")
        }
    }

    /// Owned teardown body. Runs exactly once per cleanup cycle. The cycle
    /// token gives the cleanup completion its own authority, independent of
    /// product-workflow generation bumps. Provider unload is not assumed
    /// cancellable — the task awaits it to natural completion so `.idle`
    /// always means teardown actually done.
    ///
    /// 0.3.3: the completion also suppresses `.idle` while a recovery (R7)
    /// holds PTT admission closed — the recovery's own `.loadingModel` write
    /// remains the published state across the drain window.
    private func performProviderUnload(cycle: Int, generation: Int) async {
        await asrProvider?.unload()
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.providerUnloadTask = nil
            // Cleanup-completion authority: this cycle's teardown owns the
            // terminal write unless a newer cleanup cycle has begun.
            guard cycle == self.cleanupCycle else { return }
            // 0.3.3: during an active recovery, the recovery owns the visible
            // state (.loadingModel); do not transiently publish .idle.
            guard !self.isRecovering else { return }
            self.state = .idle
        }
    }

    /// 0.3.2 observability seam: completes once the provider teardown for
    /// the most recent cleanup has finished (state == .idle). Safe to call
    /// repeatedly and safe when no cleanup has run (returns immediately).
    public func awaitCleanupCompletion() async {
        if let task = providerUnloadTask {
            _ = await task.value
        }
    }

    public func quit() {
        // SessionCoordinator does NOT terminate the application
        // AppDelegate owns termination lifecycle via applicationShouldTerminate
        cleanup()
    }

    /// 0.3.3 recovery (ported from legacy R1–R8 evidence, adapted to the
    /// canonical 0.3.1/0.3.2 authority model):
    ///
    /// R7/START-ADMISSION: `.loadingModel` is published synchronously,
    /// before the first await, so PTT admission is closed immediately and
    /// `startRecording()` is rejected for the entire recovery window.
    /// Canonical remains ready-only recording; `.idle` never admits.
    ///
    /// R4: concurrent retries coalesce. All retries that begin while
    /// generation G is current share one recovery; only the first to reach
    /// the spawn point opens G+1. Later arrivals see a superseded entry
    /// generation and return without draining or superseding the newer task.
    ///
    /// R2: the prior lifecycle initialization task is cancelled AND awaited
    /// before a new initialization generation begins, so an old initialize()
    /// can never run concurrently with (or after) the recovery one.
    ///
    /// R8: if canonical 0.3.2 provider teardown (`providerUnloadTask`) is in
    /// flight, recovery awaits its completion BEFORE loading — load never
    /// overlaps unload. When no teardown exists, no forced unload is issued:
    /// the provider's reload contract permits load-without-unload.
    ///
    /// R5/R6: the spawned initialization runs load → warmup → authoritative
    /// `.ready`, or lands deterministically in `.failed` (from which another
    /// retry can recover again).
    public func retry() async {
        // R7: pin the non-ready state synchronously, before any await.
        isRecovering = true
        state = .loadingModel
        writeRuntimeDiagnostic("COORDINATOR_RETRY_ENTER")
        let entryGeneration = generation

        // R4: coalescing window — all concurrent retries observe the same
        // entry generation on the main actor; exactly one performs the work.
        guard isAuthoritative(entryGeneration) else {
            writeRuntimeDiagnostic("COORDINATOR_RETRY_COALESCED generation=\(entryGeneration)")
            return
        }

        // R2: retire the previous lifecycle task and drain it. The ownership
        // check means we only ever drain the task of the generation being
        // retired — a newer recovery's task is never touched.
        if let task = modelLoadTask, modelLoadTaskGeneration <= entryGeneration {
            task.cancel()
            await task.value
        }

        // R8: never load while a canonical teardown is still in flight.
        if let unloadTask = providerUnloadTask {
            _ = await unloadTask.value
        }

        // No recording may survive into recovery.
        audioCapture?.cancel()
        audioBuffer.removeAll()

        // R2/R3: open exactly ONE new authoritative generation owned by the
        // spawned task. From this point the retired generation cannot publish
        // .ready/.failed or any success side effect (0.3.1 authority gates).
        transcriptionTask?.cancel()
        transcriptionTask = nil
        generation &+= 1
        state = .loadingModel

        let capturedGeneration = generation
        writeRuntimeDiagnostic("COORDINATOR_RECOVERY_SPAWNED generation=\(capturedGeneration)")
        modelLoadTask = Task.detached { [weak self] in
            await self?.initialize(generation: capturedGeneration)
        }
        modelLoadTaskGeneration = capturedGeneration
        // Recovery window closes only after the new lifecycle task is
        // registered; from here the generation gates own correctness.
        isRecovering = false
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
