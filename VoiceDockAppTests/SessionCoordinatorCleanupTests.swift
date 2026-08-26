//
//  SessionCoordinatorCleanupTests.swift
//  VoiceDockAppTests
//
//  0.3.2 observable cleanup & provider teardown regression tests.
//
//  Core invariant: `.idle` means workflow authority is retired AND the
//  provider unload for that cleanup cycle has actually completed.
//  `.cleaningUp` means authority revoked and teardown started but not yet
//  proven complete. Duplicate cleanups join; they never duplicate unload work
//  or regress state.
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class SessionCoordinatorCleanupTests: XCTestCase {

    // MARK: - Helpers

    private func makeAudio() -> [Float] {
        (0..<16000).map { sin(Float($0) / 5.0) * 0.3 }
    }

    /// Build a coordinator wired to mocks and wait until it reaches .ready.
    private func makeReadyCoordinator(
        holdTranscribe: Int = 0,
        failTranscribe: Int = 0,
        holdUnloadCalls: Int = 0,
        transcript: String = "mock transcript"
    ) async -> (SessionCoordinator, MockASRProvider, MockAudioCapture)? {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        if holdTranscribe > 0 { await mockASR.holdTranscribe(calls: holdTranscribe) }
        if failTranscribe > 0 { await mockASR.failTranscribe(calls: failTranscribe) }
        if holdUnloadCalls > 0 { await mockASR.holdUnload(calls: holdUnloadCalls) }
        await mockASR.setTranscribeResult(transcript)

        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if case .ready = coordinator.state { return (coordinator, mockASR, mockAudio) }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if case .ready = coordinator.state { return (coordinator, mockASR, mockAudio) }
        return nil
    }

    /// Drive a full record → stop cycle and wait for transcription to begin.
    private func beginRecording(
        _ coordinator: SessionCoordinator,
        _ mockAudio: MockAudioCapture
    ) async {
        mockAudio.setFakeStopBuffer(makeAudio())
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopRecording()
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if case .transcribing = coordinator.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForState(
        _ coordinator: SessionCoordinator,
        target: SessionCoordinator.State,
        timeoutSeconds: Double = 3.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if coordinator.state == target { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return coordinator.state == target
    }

    // MARK: - C1: cleanup from ready (observable teardown)

    func testC1_cleanupFromReady_observableTeardown() async {
        guard let (coordinator, mockASR, _) = await makeReadyCoordinator(holdUnloadCalls: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        // Cleanup starts: authority revoked, unload begins, .cleaningUp shown.
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp, "cleanup must enter .cleaningUp")

        // Unload suspended at gate: state must stay .cleaningUp — NOT idle.
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(coordinator.state, .cleaningUp, ".cleaningUp must persist while unload is in flight")
        let unloadStarted = await mockASR.getUnloadCalled()
        XCTAssertTrue(unloadStarted, "provider.unload() must have started")

        // Release the unload; only then may .idle appear.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle, ".idle must follow actual unload completion")
        XCTAssertEqual(coordinator.state, .idle)

        // Observability seam resolves after completion.
        await coordinator.awaitCleanupCompletion()
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - C2: duplicate cleanup joins, never duplicates unload

    func testC2_duplicateCleanup_singleUnload() async {
        guard let (coordinator, mockASR, _) = await makeReadyCoordinator(holdUnloadCalls: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp)

        // Second cleanup while teardown is in flight: join, no new unload.
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp, "duplicate cleanup must not regress state")

        // Third call for good measure.
        coordinator.cleanup()

        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle)

        let unloadCalls = await mockASR.getUnloadCallCount()
        XCTAssertEqual(unloadCalls, 1, "duplicate cleanups must not launch additional unloads")
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - C3: cleanup during suspended transcription

    func testC3_cleanupDuringSuspendedTranscription_fullLifecycle() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }
        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        await beginRecording(coordinator, mockAudio)
        XCTAssertEqual(coordinator.state, .transcribing)

        // Cleanup retires the transcription generation and starts teardown.
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp, "cleanup during transcription must enter .cleaningUp")

        // Stale workflow resumes into retirement: no state write, no delivery.
        await mockASR.openTranscribeGate()

        // Teardown completes only when unload finishes.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle, ".idle requires completed provider teardown")

        // 0.3.1 stale-completion invariants preserved through the new path.
        XCTAssertEqual(deliveryCount, 0, "ZERO stale deliveries required")
        XCTAssertNil(coordinator.currentTranscript, "retired session must not publish transcript")
        if case .failed = coordinator.state {
            return XCTFail("stale failure must not publish .failed")
        }
        let unloadCalls = await mockASR.getUnloadCallCount()
        XCTAssertEqual(unloadCalls, 1)
    }

    // MARK: - C4: stale initialization vs cleanup

    func testC4_staleInitialization_vsCleanupCompletion() async {
        let mockASR = MockASRProvider()
        await mockASR.enableLoadHold()
        await mockASR.holdUnload(calls: 1)

        let coordinator = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASR,
            transcriptDestination: nil
        )

        // Wait until initialization A is suspended inside provider.load().
        let deadline = Date().addingTimeInterval(2.0)
        var loadCalled = false
        while Date() < deadline {
            if await mockASR.getLoadCalled() { loadCalled = true; break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(loadCalled, "load() should have been invoked")

        // Cleanup supersedes A and enters its observable teardown.
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp)

        // Release initialization A into retirement: it may not publish state.
        await mockASR.openLoadGate()

        // Complete teardown; the cleanup completion owns the final .idle.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle, "cleanup completion owns final .idle")

        if case .ready = coordinator.state {
            return XCTFail("stale initialization must not publish .ready")
        }
        if case .failed = coordinator.state {
            return XCTFail("stale initialization must not publish .failed")
        }
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - C5: start rejected during cleaningUp

    func testC5_startRejectedDuringCleaningUp() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdUnloadCalls: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp)

        XCTAssertFalse(coordinator.startRecording(), "startRecording must be rejected during .cleaningUp")
        XCTAssertEqual(mockAudio.startCallCount, 0, "audio capture must never start during .cleaningUp")

        await mockASR.openUnloadGate()
        _ = await waitForState(coordinator, target: .idle)
    }

    // MARK: - C6: start rejected after idle

    func testC6_startRejectedAfterIdle() async {
        guard let (coordinator, _, mockAudio) = await makeReadyCoordinator() else {
            return XCTFail("Coordinator did not reach .ready")
        }

        coordinator.cleanup()
        await coordinator.awaitCleanupCompletion()
        XCTAssertEqual(coordinator.state, .idle)

        XCTAssertFalse(coordinator.startRecording(), "startRecording must be rejected from .idle")
        XCTAssertEqual(mockAudio.startCallCount, 0)
    }

    // MARK: - C7: cleanup with nil provider reaches idle deterministically

    func testC7_cleanupWithNilProvider_reachesIdle() async {
        let coordinator = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: nil,
            transcriptDestination: nil
        )
        // No provider: init skips load; give it a moment then clean up.
        try? await Task.sleep(nanoseconds: 100_000_000)

        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp, "teardown lifecycle applies even without provider")

        let reachedIdle = await waitForState(coordinator, target: .idle, timeoutSeconds: 2.0)
        XCTAssertTrue(reachedIdle, "nil-provider cleanup must reach .idle without hanging")
    }

    // MARK: - C8: happy production-like lifecycle with cleanup tail

    func testC8_happyLifecycle_throughCleanupTail() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(transcript: "hello world") else {
            return XCTFail("Coordinator did not reach .ready")
        }
        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        // ready → listening
        mockAudio.setFakeStopBuffer(makeAudio())
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.state, .listening)

        // listening → transcribing → delivering → ready
        coordinator.stopRecording()
        let readyAgain = await waitForState(coordinator, target: .ready)
        XCTAssertTrue(readyAgain, "workflow must complete back to .ready before cleanup")
        XCTAssertEqual(coordinator.currentTranscript, "hello world")
        XCTAssertEqual(deliveryCount, 1, "delivery invoked exactly once pre-cleanup")

        // ready → cleaningUp → idle
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp)
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle)
        let unloadCalls = await mockASR.getUnloadCallCount()
        XCTAssertEqual(unloadCalls, 1)
    }

    // MARK: - Stress: C1/C2/C3/C4 ×30 each

    func testStress_C1_CleanupObservableCompletion_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, _) = await makeReadyCoordinator(holdUnloadCalls: 1) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            coordinator.cleanup()
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i)")
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i): must stay .cleaningUp while unload held")
            await mockASR.openUnloadGate()
            let reached = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reached, "Iteration \(i): .idle must follow unload completion")
            XCTAssertEqual(coordinator.state, .idle, "Iteration \(i)")
        }
    }

    func testStress_C2_DuplicateCleanup_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, _) = await makeReadyCoordinator(holdUnloadCalls: 1) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            coordinator.cleanup()
            coordinator.cleanup()
            coordinator.cleanup()
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i): no state regression on join")
            await mockASR.openUnloadGate()
            let reached = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reached, "Iteration \(i)")
            let unloadCalls = await mockASR.getUnloadCallCount()
            XCTAssertEqual(unloadCalls, 1, "Iteration \(i): exactly one unload despite duplicate cleanups")
        }
    }

    func testStress_C3_CleanupDuringTranscription_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            var deliveryCount = 0
            coordinator.deliverHook = { _ in deliveryCount += 1 }

            await beginRecording(coordinator, mockAudio)
            coordinator.cleanup()
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i)")
            await mockASR.openTranscribeGate()
            await mockASR.openUnloadGate()
            let reached = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reached, "Iteration \(i)")
            XCTAssertEqual(deliveryCount, 0, "Iteration \(i): ZERO stale deliveries")
            XCTAssertEqual(coordinator.state, .idle, "Iteration \(i)")
        }
    }

    func testStress_C4_StaleInitVsCleanup_30x() async {
        for i in 0..<30 {
            let mockASR = MockASRProvider()
            await mockASR.enableLoadHold()
            await mockASR.holdUnload(calls: 1)

            let coordinator = SessionCoordinator(
                audioCapture: MockAudioCapture(),
                asrProvider: mockASR,
                transcriptDestination: nil
            )
            let deadline = Date().addingTimeInterval(2.0)
            var loadCalled = false
            while Date() < deadline {
                if await mockASR.getLoadCalled() { loadCalled = true; break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(loadCalled, "Iteration \(i): load() should have been invoked")

            coordinator.cleanup()
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i)")
            await mockASR.openLoadGate()
            await mockASR.openUnloadGate()
            let reached = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reached, "Iteration \(i)")
            if case .ready = coordinator.state {
                return XCTFail("Iteration \(i): stale init published .ready")
            }
            if case .failed = coordinator.state {
                return XCTFail("Iteration \(i): stale init published .failed")
            }
        }
    }
}
