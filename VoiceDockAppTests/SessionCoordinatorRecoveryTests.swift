//
//  SessionCoordinatorRecoveryTests.swift
//  VoiceDockAppTests
//
//  0.3.3 recovery lifecycle contract tests (R1–R8), ported semantically from
//  the legacy working-tree implementation and adapted to the canonical
//  0.3.1 generation-authority / 0.3.2 observable-teardown semantics.
//
//  Key adaptations vs legacy:
//  - Recording admission stays READY_ONLY: .idle and every other state are
//    rejected (legacy's `.ready || .idle` admission was NOT ported).
//  - Recovery integrates with canonical providerUnloadTask (R8): a load may
//    not begin while a teardown is in flight; no forced unload is issued when
//    no teardown exists (reload-without-unload contract).
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class SessionCoordinatorRecoveryTests: XCTestCase {

    // MARK: - Helpers

    /// Poll until state matches, with timeout.
    private func waitForState(
        _ sut: SessionCoordinator,
        matches predicate: @escaping (SessionCoordinator.State) -> Bool,
        _ message: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(sut.state) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for state: \(message) (last=\(sut.state))", file: file, line: line)
    }

    private func waitForReady(_ sut: SessionCoordinator) async {
        await waitForState(sut, matches: { $0 == .ready }, "ready")
    }

    private func makeAudio() -> [Float] {
        (0..<16000).map { sin(Float($0) / 5.0) * 0.3 }
    }

    // MARK: - T-R1 / T-R5: failed → retry → recovery succeeds → ready

    func testTR1_failedThenRetrySucceeds() async {
        let mockASRProvider = MockASRProvider()
        await mockASRProvider.setLoadShouldFail(true)
        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )
        // Initial load fails through all backoff attempts (~6s of backoff).
        await waitForState(sut, matches: {
            if case .failed = $0 { return true }
            return false
        }, "failed after initial load failures")

        await mockASRProvider.setLoadShouldFail(false)
        await sut.retry()
        await waitForReady(sut)

        XCTAssertEqual(sut.state, .ready, "Successful recovery after failure must reach ready (R5)")
        let loadCount = await mockASRProvider.getLoadCallCount()
        XCTAssertGreaterThanOrEqual(loadCount, 1, "Retry must reload the provider (R5)")
        let warmupCount = await mockASRProvider.getWarmupCallCount()
        XCTAssertGreaterThanOrEqual(warmupCount, 1, "Recovery requires warmup (R5)")

        sut.cleanup()
    }

    // MARK: - T-R2: retry drains prior lifecycle task before new initialization

    /// Ordering proof with per-call gating and a clean attribution window:
    ///
    /// Phase 1: A's load (#1) is held inside the gate; retry() pins
    ///          .loadingModel and must NOT start B (loadCallCount == 1).
    /// Phase 2: #1 is released with NON-COOPERATIVE success semantics — even
    ///          though retry() cancelled A's Task while it was held, the load
    ///          completes successfully. A then fully retires (its authority
    ///          gates must reject every publication).
    /// Phase 3: recovery B starts load #2, which is independently held.
    ///          Attribution window: A retired + B held ⇒ state == .loadingModel.
    /// Phase 4: releasing #2 lets the AUTHORITATIVE B reach .ready — proving
    ///          the final .ready belongs to B, never to stale A.
    func testTR2_retryDrainsPriorLifecycleTaskBeforeNewLoad() async {
        let mockASR = MockASRProvider()
        // Hold load calls #1 AND #2 up front: #1 pins initialization A,
        // #2 will pin recovery B the moment its load begins. Registering
        // both BEFORE the coordinator exists removes the registration race.
        await mockASR.holdLoadCall(at: 0)
        await mockASR.holdLoadCall(at: 1)

        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASR,
            transcriptDestination: nil
        )

        // Phase 1: wait until call #1 is definitely INSIDE its hold.
        let deadline = Date().addingTimeInterval(2.0)
        var enteredHold = false
        while Date() < deadline {
            if await mockASR.isLoadCallInsideHold(0) { enteredHold = true; break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(enteredHold, "load call #1 should be suspended inside its hold")
        var loadCount = await mockASR.getLoadCallCount()
        XCTAssertEqual(loadCount, 1, "exactly one load call before retry")

        // retry(): synchronously pins .loadingModel before its first await.
        await sut.retry()
        XCTAssertEqual(sut.state, .loadingModel, "retry must pin .loadingModel")

        // DRAIN SEMANTICS NOTE: retry() retires A by CANCELLATION — A's
        // provider wait breaks immediately (the mock stops holding on
        // cancellation), so B can spawn and even START load #2 while #1's
        // gate entry is still nominally "held". The authoritative ordering
        // proof is therefore:
        //   (a) stale A publishes NOTHING (checked below after release), and
        //   (b) B cannot COMPLETE until its own gate (#2) is released —
        //       so any terminal state before that release could only come
        //       from stale A, and must be absent.
        // Phase 2: NON-COOPERATIVE release of #1 — A's cancelled Task still
        // observes a successful load; A then resumes into retirement.
        await mockASR.releaseLoadCall(at: 0)
        // Give A a bounded window to fully retire.
        try? await Task.sleep(nanoseconds: 400_000_000)

        if case .ready = sut.state {
            XCTFail("stale A must NOT publish .ready after retirement")
        }
        if case .failed = sut.state {
            XCTFail("stale A must NOT publish .failed after retirement")
        }

        // Phase 3: require B has started exactly one new load and is now
        // pinned in ITS OWN hold (#2). This proves drain-of-A preceded B.
        let bStartedDeadline = Date().addingTimeInterval(5)
        while Date() < bStartedDeadline {
            if await mockASR.isLoadCallInsideHold(1) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        loadCount = await mockASR.getLoadCallCount()
        XCTAssertEqual(loadCount, 2, "recovery B must start exactly one new load after A drained")
        let bInHold = await mockASR.isLoadCallInsideHold(1)
        XCTAssertTrue(bInHold, "recovery load #2 should be suspended in its own hold")

        // CLEAN ATTRIBUTION WINDOW: A retired, B held before completing.
        guard case .loadingModel = sut.state else {
            return XCTFail("attribution window requires state == .loadingModel (got \(sut.state)); stale A published a terminal state")
        }

        // Phase 4: release B → authoritative .ready belongs to B alone.
        await mockASR.releaseLoadCall(at: 1)
        await waitForReady(sut)
        XCTAssertEqual(sut.state, .ready, "final .ready must come from authoritative recovery B")
        let warmups = await mockASR.getWarmupCallCount()
        XCTAssertGreaterThanOrEqual(warmups, 1, "B completed warmup on its path to ready")

        sut.cleanup()
    }

    // MARK: - T-R3: retry during in-flight unload awaits teardown before loading

    func testTR3_retryAwaitsInFlightUnloadBeforeLoading() async {
        let mockASR = MockASRProvider()
        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASR,
            transcriptDestination: nil
        )
        await waitForReady(sut)

        // Hold the FIRST unload at its gate so canonical teardown suspends.
        await mockASR.holdUnload(calls: 1)

        sut.cleanup()
        XCTAssertEqual(sut.state, .cleaningUp)

        // Give the owned teardown task a bounded window to start; canonical
        // cleanup spawns it as a Task, so its first instruction is not
        // synchronous with the cleanup() call itself.
        let unloadStartedDeadline = Date().addingTimeInterval(2)
        while Date() < unloadStartedDeadline {
            if (await mockASR.getUnloadCallCount()) >= 1 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let unloadCallsBefore = await mockASR.getUnloadCallCount()
        XCTAssertEqual(unloadCallsBefore, 1, "teardown started exactly once")

        let loadsBeforeRecovery = await mockASR.getLoadCallCount()

        // Retry while teardown is suspended: recovery must await the unload
        // BEFORE issuing any new load().
        let retryTask = Task { await sut.retry() }

        try? await Task.sleep(nanoseconds: 300_000_000)
        let loadsWhileUnloadHeld = await mockASR.getLoadCallCount()
        XCTAssertEqual(
            loadsWhileUnloadHeld, loadsBeforeRecovery + 0,
            "recovery must NOT begin a new load while canonical teardown is in flight"
        )

        // Release the teardown; recovery may then proceed.
        await mockASR.openUnloadGate()
        await retryTask.value
        // Give the spawned lifecycle task a bounded window to reach load();
        // the assertion below proves no NEW load happened while the unload
        // was held (loadsWhileUnloadHeld above), and that exactly one new
        // load eventually begins after teardown completed.
        let readyAfterRecovery = Date().addingTimeInterval(5)
        while Date() < readyAfterRecovery {
            if case .ready = sut.state { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if case .ready = sut.state {} else {
            XCTFail("recovery must complete after teardown released")
        }

        let loadsAfterRecovery = await mockASR.getLoadCallCount()
        XCTAssertEqual(
            loadsAfterRecovery, loadsBeforeRecovery + 1,
            "recovery must issue exactly one new load after teardown completed"
        )
        await waitForReady(sut)

        let unloadCallsAfter = await mockASR.getUnloadCallCount()
        XCTAssertEqual(unloadCallsAfter, 1, "no forced second unload (reload-without-unload contract)")

        sut.cleanup()
    }

    // MARK: - T-R4: two rapid retries coalesce deterministically

    func testTR4_concurrentRetriesCoalesceSingleWinner() async {
        let mockASRProvider = MockASRProvider()
        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )
        await waitForReady(sut)

        async let r1: Void = sut.retry()
        async let r2: Void = sut.retry()
        _ = await (r1, r2)
        await waitForReady(sut)

        XCTAssertEqual(sut.state, .ready, "Coalesced recovery still reaches ready")
        sut.cleanup()
    }

    // MARK: - T-R5b: recovery failure lands deterministic .failed; retry again reaches .ready

    func testTR5_recoveryFailureLandsInFailedStateThenRecoversAgain() async {
        let mockASRProvider = MockASRProvider()
        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )
        await waitForReady(sut)

        await mockASRProvider.setLoadShouldFail(true)
        await sut.retry()
        await waitForState(sut, matches: {
            if case .failed = $0 { return true }
            return false
        }, "failed after recovery load failures")

        // R6: the failed state is deterministic — another retry is accepted
        // and can recover again.
        await mockASRProvider.setLoadShouldFail(false)
        await sut.retry()
        await waitForReady(sut)

        sut.cleanup()
    }

    // MARK: - T-R6: retry synchronously publishes non-ready state before first await

    func testTR6_retrySynchronouslyPublishesLoadingModelAndBlocksRecording() async {
        let mockASRProvider = MockASRProvider()
        let mockAudioCapture = MockAudioCapture()
        let sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )
        await waitForReady(sut)

        // Hold every load() so recovery stays pinned in .loadingModel.
        await mockASRProvider.enableLoadHold()
        // Open the initial init's gate first so we reach .ready above — done.
        // Now hold subsequent loads:
        // enableLoadHold already keeps the gate closed for future calls.

        _ = await sut.retry()

        // retry() returned having pinned .loadingModel synchronously before
        // any await; the recovery load is suspended at the held gate.
        XCTAssertEqual(sut.state, .loadingModel, "Recovery must pin loadingModel")

        let accepted = sut.startRecording()
        XCTAssertFalse(accepted, "Recording must not start during recovery (R7)")
        XCTAssertEqual(mockAudioCapture.startCallCount, 0, "audio capture start count must remain zero")

        await mockASRProvider.openLoadGate()
        await waitForReady(sut)

        // Post-recovery admission invariant still holds from .ready.
        XCTAssertTrue(sut.startRecording(), ".ready must accept recording after recovery completes")
        XCTAssertEqual(mockAudioCapture.startCallCount, 1)
        sut.stopRecording()

        sut.cleanup()
    }

    // MARK: - T-R7: canonical start-admission matrix

    func testTR7_startAdmissionMatrix_readyOnly() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let sut = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: nil
        )

        // .starting / .loadingModel: rejected
        XCTAssertFalse(sut.startRecording(), ".loadingModel must reject recording")
        XCTAssertEqual(mockAudio.startCallCount, 0)

        await waitForReady(sut)

        // .ready: accepted
        XCTAssertTrue(sut.startRecording(), ".ready must accept recording")
        XCTAssertEqual(mockAudio.startCallCount, 1)
        sut.stopRecording()
        await waitForState(sut, matches: { $0 == .ready }, "back to ready after workflow")

        // → .cleaningUp: rejected
        await mockASR.holdUnload(calls: 1)
        sut.cleanup()
        XCTAssertEqual(sut.state, .cleaningUp)
        XCTAssertFalse(sut.startRecording(), ".cleaningUp must reject recording")
        XCTAssertEqual(mockAudio.startCallCount, 1)

        // → .idle: rejected
        await mockASR.openUnloadGate()
        await waitForState(sut, matches: { $0 == .idle }, "idle")
        XCTAssertFalse(sut.startRecording(), ".idle must reject recording (READY_ONLY)")
        XCTAssertEqual(mockAudio.startCallCount, 1, "capture must never start outside .ready")

        // .failed: rejected
        await mockASR.holdUnload(calls: 0)
        await mockASR.setLoadShouldFail(true)
        await sut.retry()
        await waitForState(sut, matches: {
            if case .failed = $0 { return true }
            return false
        }, "failed")
        XCTAssertFalse(sut.startRecording(), ".failed must reject recording")
        XCTAssertEqual(mockAudio.startCallCount, 1)
    }

    // MARK: - T-R8: stale old initialization cannot supersede newer recovery generation

    /// Stale-publish proof with NON-COOPERATIVE cancellation semantics:
    ///
    /// A's load (#1) completes SUCCESSFULLY even though retry() cancelled
    /// A's Task while it was held — modelling a provider whose load is not
    /// cooperatively cancellable. The phase-scoped attribution window (A
    /// retired + B held) must show NO .ready and NO .failed from stale A.
    func testTR8_staleInitializationCannotSupersedeNewerRecoveryGeneration() async {
        let mockASR = MockASRProvider()
        // Hold BOTH load calls up front: #1 pins stale initialization A,
        // #2 pins recovery B the moment its load begins (no registration
        // race — both gates exist before the coordinator is created).
        await mockASR.holdLoadCall(at: 0)
        await mockASR.holdLoadCall(at: 1)

        let sut = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASR,
            transcriptDestination: nil
        )

        // Wait until A is definitely suspended inside its hold.
        let deadline = Date().addingTimeInterval(2.0)
        var enteredHold = false
        while Date() < deadline {
            if await mockASR.isLoadCallInsideHold(0) { enteredHold = true; break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(enteredHold, "load call #1 should be suspended inside its hold")

        // Recovery B retires/cancels A while its load is mid-flight.
        await sut.retry()

        // NON-COOPERATIVE release: load #1 returns success despite the
        // cancellation of A's Task. A resumes into retirement.
        await mockASR.releaseLoadCall(at: 0)
        try? await Task.sleep(nanoseconds: 400_000_000)

        if case .ready = sut.state {
            XCTFail("stale A (cancelled, non-cooperative success) must NOT publish .ready")
        }
        if case .failed = sut.state {
            XCTFail("stale A (cancelled, non-cooperative success) must NOT publish .failed")
        }

        // Independently require B's load #2 to be pinned in its own hold.
        let bStartedDeadline = Date().addingTimeInterval(5)
        while Date() < bStartedDeadline {
            if await mockASR.isLoadCallInsideHold(1) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let loadCount = await mockASR.getLoadCallCount()
        XCTAssertEqual(loadCount, 2, "recovery B starts exactly one load after A drained")
        let bInHold = await mockASR.isLoadCallInsideHold(1)
        XCTAssertTrue(bInHold, "B's load #2 should be held for the attribution window")

        // CLEAN ATTRIBUTION WINDOW: A retired/completed, B not yet complete.
        guard case .loadingModel = sut.state else {
            return XCTFail("attribution window requires state == .loadingModel (got \(sut.state)); stale A published a terminal state")
        }

        // Only after releasing B may state become .ready.
        await mockASR.releaseLoadCall(at: 1)
        await waitForReady(sut)
        XCTAssertEqual(sut.state, .ready, "authoritative recovery B owns the terminal .ready")

        sut.cleanup()
    }

    // MARK: - Stress: concurrent retry coalescing ×30

    func testStress_ConcurrentRetryCoalescing_30x() async {
        for i in 0..<30 {
            let mockASRProvider = MockASRProvider()
            let sut = SessionCoordinator(
                audioCapture: MockAudioCapture(),
                asrProvider: mockASRProvider,
                transcriptDestination: nil
            )
            await waitForReady(sut)

            async let r1: Void = sut.retry()
            async let r2: Void = sut.retry()
            _ = await (r1, r2)
            await waitForReady(sut)

            guard case .ready = sut.state else {
                return XCTFail("Iteration \(i): expected .ready after coalesced retries")
            }
            sut.cleanup()
        }
    }

    // MARK: - Stress: retry while unload held ×30

    func testStress_RetryWhileUnloadHeld_30x() async {
        for i in 0..<30 {
            let mockASR = MockASRProvider()
            let sut = SessionCoordinator(
                audioCapture: MockAudioCapture(),
                asrProvider: mockASR,
                transcriptDestination: nil
            )
            await waitForReady(sut)

            await mockASR.holdUnload(calls: 1)
            sut.cleanup()
            XCTAssertEqual(sut.state, .cleaningUp, "Iteration \(i)")

            let loadsBefore = await mockASR.getLoadCallCount()
            let retryTask = Task { await sut.retry() }

            try? await Task.sleep(nanoseconds: 100_000_000)
            let loadsHeld = await mockASR.getLoadCallCount()
            XCTAssertEqual(
                loadsHeld, loadsBefore,
                "Iteration \(i): no new load while teardown in flight"
            )

            await mockASR.openUnloadGate()
            await retryTask.value
            await waitForReady(sut)
            XCTAssertEqual(sut.state, .ready, "Iteration \(i)")

            sut.cleanup()
            await mockASR.openUnloadGate()
        }
    }

    // MARK: - Stress: stale initialization vs newer recovery generation ×30

    func testStress_StaleInitVsNewRecoveryGeneration_30x() async {
        for i in 0..<30 {
            let mockASR = MockASRProvider()
            // Hold BOTH load calls up front (no registration race).
            await mockASR.holdLoadCall(at: 0)
            await mockASR.holdLoadCall(at: 1)

            let sut = SessionCoordinator(
                audioCapture: MockAudioCapture(),
                asrProvider: mockASR,
                transcriptDestination: nil
            )

            let deadline = Date().addingTimeInterval(2.0)
            var enteredHold = false
            while Date() < deadline {
                if await mockASR.isLoadCallInsideHold(0) { enteredHold = true; break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(enteredHold, "Iteration \(i): load #1 inside hold")

            await sut.retry()

            // NON-COOPERATIVE release of A's load despite cancellation.
            await mockASR.releaseLoadCall(at: 0)
            try? await Task.sleep(nanoseconds: 100_000_000)

            // Require B pinned in its own gate (#2) for the attribution window.
            let bDeadline = Date().addingTimeInterval(5)
            while Date() < bDeadline {
                if await mockASR.isLoadCallInsideHold(1) { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            let loadCount = await mockASR.getLoadCallCount()
            XCTAssertEqual(loadCount, 2, "Iteration \(i): exactly one recovery load after A drained")
            let bInHold = await mockASR.isLoadCallInsideHold(1)
            XCTAssertTrue(bInHold, "Iteration \(i): B held in its own gate")

            // CLEAN ATTRIBUTION WINDOW: A retired/completed, B held.
            guard case .loadingModel = sut.state else {
                return XCTFail("Iteration \(i): attribution window requires .loadingModel (got \(sut.state))")
            }

            // Release B → authoritative .ready.
            await mockASR.releaseLoadCall(at: 1)
            await waitForReady(sut)
            XCTAssertEqual(sut.state, .ready, "Iteration \(i)")

            sut.cleanup()
        }
    }
}
