////
//  SessionCoordinatorLifecycleTests.swift
//  VoiceDockAppTests
//
//  0.3.1 lifecycle-guard regression tests. Proves that a retired async
//  workflow (superseded generation) can neither mutate SessionCoordinator
//  state nor invoke external transcript delivery (clipboard / Cmd-V / Return).
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class SessionCoordinatorLifecycleTests: XCTestCase {

    // MARK: - Helpers

    /// Bounded wait for a target lifecycle state.
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

    private func makeAudio() -> [Float] {
        (0..<16000).map { sin(Float($0) / 5.0) * 0.3 }
    }

    /// Build a coordinator with the given mock configuration and wait for it
    /// to reach .ready. Returns nil if readiness is not reached in time.
    private func makeReadyCoordinator(
        holdTranscribe: Int = 0,
        failTranscribe: Int = 0,
        holdLoad: Bool = false,
        transcript: String = "mock transcript"
    ) async -> (SessionCoordinator, MockASRProvider, MockAudioCapture)? {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        if holdTranscribe > 0 { await mockASR.holdTranscribe(calls: holdTranscribe) }
        if failTranscribe > 0 { await mockASR.failTranscribe(calls: failTranscribe) }
        if holdLoad { await mockASR.enableLoadHold() }
        await mockASR.setTranscribeResult(transcript)

        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination(
                isAccessibilityTrusted: { false },
                postKeyboardEvent: { _, _ in }
            )
        )

        // Wait for initialization to reach .ready (or .loadingModel if held).
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if case .ready = coordinator.state { return (coordinator, mockASR, mockAudio) }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if case .ready = coordinator.state { return (coordinator, mockASR, mockAudio) }
        return nil
    }

    // MARK: - T1: cleanup during suspended transcription

    func testT1_cleanupDuringSuspendedTranscription() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        mockAudio.setFakeStopBuffer(makeAudio())
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopRecording()

        // Wait for the workflow to enter .transcribing and suspend at the gate.
        let deadline1 = Date().addingTimeInterval(1.0)
        while Date() < deadline1 {
            if case .transcribing = coordinator.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(coordinator.state, .transcribing)

        // Cleanup while the transcription workflow is mid-flight.
        coordinator.cleanup()
        // 0.3.2: cleanup enters observable teardown, not instant .idle.
        XCTAssertEqual(coordinator.state, .cleaningUp)

        // Release the suspended workflow; it resumes into a stale generation.
        await mockASR.openTranscribeGate()
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Complete provider teardown so the cleanup cycle can reach .idle.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle, ".idle must follow actual unload completion")
        XCTAssertNil(coordinator.currentTranscript, "Stale generation must not publish transcript")
        XCTAssertEqual(deliveryCount, 0, "Stale generation must perform ZERO deliveries")
    }

    // MARK: - T2: stale transcription failure after cleanup

    func testT2_staleTranscriptionFailureAfterCleanup() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1, failTranscribe: 2) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        mockAudio.setFakeStopBuffer(makeAudio())
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopRecording()

        let deadline1 = Date().addingTimeInterval(1.0)
        while Date() < deadline1 {
            if case .transcribing = coordinator.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(coordinator.state, .transcribing)

        coordinator.cleanup()
        // 0.3.2: observable teardown state.
        XCTAssertEqual(coordinator.state, .cleaningUp)

        await mockASR.openTranscribeGate()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Complete provider teardown; then the terminal state must be .idle.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle)

        // A retired workflow finishing with an error is NOT a new failure.
        XCTAssertEqual(coordinator.state, .idle, "Stale failure must not publish .failed")
        if case .failed = coordinator.state {
            XCTFail("Stale generation must not publish .failed")
        }
        XCTAssertNil(coordinator.currentTranscript)
        XCTAssertEqual(deliveryCount, 0)
    }

    // MARK: - T3: cleanup during delivery boundary

    func testT3_cleanupDuringDeliveryBoundary() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        mockAudio.setFakeStopBuffer(makeAudio())
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopRecording()

        let deadline1 = Date().addingTimeInterval(1.0)
        while Date() < deadline1 {
            if case .transcribing = coordinator.state { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(coordinator.state, .transcribing)

        // Cleanup, then release so the workflow proceeds as a stale generation.
        coordinator.cleanup()
        // 0.3.2: observable teardown state.
        XCTAssertEqual(coordinator.state, .cleaningUp)

        await mockASR.openTranscribeGate()
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Complete provider teardown; stale generation must still not deliver
        // and the terminal state must be .idle (never a revert to .ready).
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle)

        // The deliver-time authority gates must hold: no delivery, no revert to .ready.
        XCTAssertEqual(deliveryCount, 0, "Stale generation must not invoke delivery at deliver boundary")
        XCTAssertEqual(coordinator.state, .idle, "State must not revert .idle → .ready from stale generation")
        XCTAssertNil(coordinator.currentTranscript)
    }

    // MARK: - T4: immutable audio snapshot

    func testT4_immutableAudioSnapshot() async {
        guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(failTranscribe: 2) else {
            return XCTFail("Coordinator did not reach .ready")
        }

        mockASR.recordAudioLog = true
        let audioA = makeAudio()
        mockAudio.setFakeStopBuffer(audioA)

        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopRecording()

        // Wait for both retry attempts to complete. Backoff is 2s after attempt 1.
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        let audioLog = await mockASR.getTranscribeAudioLog()
        XCTAssertGreaterThanOrEqual(audioLog.count, 2, "Expected retry attempts to log audio")

        // Every attempt for this session must observe exactly the same audio A.
        for (index, received) in audioLog.enumerated() {
            XCTAssertEqual(received.count, audioA.count, "Attempt \(index) sample count differs")
            XCTAssertEqual(received, audioA, "Attempt \(index) received different audio — snapshot is not immutable")
        }
    }

    // MARK: - T5: stale initialization completion

    func testT5_staleInitializationCompletion() async {
        let mockASR = MockASRProvider()
        await mockASR.enableLoadHold()

        let coordinator = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: mockASR,
            transcriptDestination: nil
        )

        // Wait until provider.load() has been called (and suspended at the gate).
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if await mockASR.getLoadCalled() { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let loadCalled = await mockASR.getLoadCalled()
        XCTAssertTrue(loadCalled, "load() should have been invoked")

        // Supersede generation A via cleanup.
        coordinator.cleanup()
        // 0.3.2: observable teardown state.
        XCTAssertEqual(coordinator.state, .cleaningUp)

        // Release the suspended initialization.
        await mockASR.openLoadGate()
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Complete provider teardown; the cleanup completion owns final .idle.
        await mockASR.openUnloadGate()
        let reachedIdle = await waitForState(coordinator, target: .idle)
        XCTAssertTrue(reachedIdle)

        // Generation A must establish no authoritative state.
        XCTAssertEqual(coordinator.state, .idle, "Stale initialization must not publish .ready/.failed")
        if case .ready = coordinator.state {
            XCTFail("Stale initialization must not publish .ready")
        }
        if case .failed = coordinator.state {
            XCTFail("Stale initialization must not publish .failed")
        }
    }

    // MARK: - T6: idle rejects startRecording

    func testT6_idleRejectsStartRecording() async {
        guard let (coordinator, _, _) = await makeReadyCoordinator() else {
            return XCTFail("Coordinator did not reach .ready")
        }

        // ready → cleanup → cleaningUp → idle
        coordinator.cleanup()
        XCTAssertEqual(coordinator.state, .cleaningUp)
        await coordinator.awaitCleanupCompletion()
        XCTAssertEqual(coordinator.state, .idle)

        // .idle must not accept a new recording.
        XCTAssertFalse(coordinator.startRecording(), "startRecording() must be rejected from .idle")
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - T7: happy path regression

    func testT7_happyPathRegression() async {
        guard let (coordinator, _, mockAudio) = await makeReadyCoordinator(transcript: "hello world") else {
            return XCTFail("Coordinator did not reach .ready")
        }

        var deliveryCount = 0
        coordinator.deliverHook = { _ in deliveryCount += 1 }

        mockAudio.setFakeStopBuffer(makeAudio())

        // ready → listening
        XCTAssertTrue(coordinator.startRecording())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.state, .listening)

        // listening → transcribing → delivering → ready
        coordinator.stopRecording()
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if case .ready = coordinator.state { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(coordinator.state, .ready, "Happy path must return to .ready")
        XCTAssertEqual(coordinator.currentTranscript, "hello world", "Transcript must be published")
        XCTAssertEqual(deliveryCount, 1, "Delivery must be invoked exactly once")
    }

    // MARK: - Stress: T1/T2/T3 repeated

    func testStress_T1_CleanupDuringSuspendedTranscription_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            var deliveryCount = 0
            coordinator.deliverHook = { _ in deliveryCount += 1 }
            mockAudio.setFakeStopBuffer(makeAudio())
            XCTAssertTrue(coordinator.startRecording())
            try? await Task.sleep(nanoseconds: 50_000_000)
            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)
            coordinator.cleanup()
            XCTAssertEqual(coordinator.state, .cleaningUp, "Iteration \(i): observable teardown state")
            await mockASR.openTranscribeGate()
            await mockASR.openUnloadGate()
            let reachedIdle = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reachedIdle, "Iteration \(i): .idle must follow unload completion")
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(coordinator.state, .idle, "Iteration \(i): state must remain .idle")
            XCTAssertNil(coordinator.currentTranscript, "Iteration \(i): no stale transcript")
            XCTAssertEqual(deliveryCount, 0, "Iteration \(i): ZERO deliveries")
        }
    }

    func testStress_T2_StaleFailure_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1, failTranscribe: 2) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            var deliveryCount = 0
            coordinator.deliverHook = { _ in deliveryCount += 1 }
            mockAudio.setFakeStopBuffer(makeAudio())
            XCTAssertTrue(coordinator.startRecording())
            try? await Task.sleep(nanoseconds: 50_000_000)
            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)
            coordinator.cleanup()
            await mockASR.openTranscribeGate()
            await mockASR.openUnloadGate()
            let reachedIdleT2 = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reachedIdleT2, "Iteration \(i): .idle must follow unload completion")
            XCTAssertEqual(coordinator.state, .idle, "Iteration \(i): stale failure must not publish .failed")
            if case .failed = coordinator.state {
                return XCTFail("Iteration \(i): stale generation published .failed")
            }
            XCTAssertEqual(deliveryCount, 0, "Iteration \(i): ZERO deliveries")
        }
    }

    func testStress_T3_DeliveryBoundary_30x() async {
        for i in 0..<30 {
            guard let (coordinator, mockASR, mockAudio) = await makeReadyCoordinator(holdTranscribe: 1) else {
                return XCTFail("Iteration \(i): coordinator did not reach .ready")
            }
            var deliveryCount = 0
            coordinator.deliverHook = { _ in deliveryCount += 1 }
            mockAudio.setFakeStopBuffer(makeAudio())
            XCTAssertTrue(coordinator.startRecording())
            try? await Task.sleep(nanoseconds: 50_000_000)
            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)
            coordinator.cleanup()
            await mockASR.openTranscribeGate()
            await mockASR.openUnloadGate()
            let reachedIdleT3 = await waitForState(coordinator, target: .idle)
            XCTAssertTrue(reachedIdleT3, "Iteration \(i): .idle must follow unload completion")
            XCTAssertEqual(deliveryCount, 0, "Iteration \(i): stale generation must not deliver")
            XCTAssertEqual(coordinator.state, .idle, "Iteration \(i): state must not revert to .ready")
        }
    }
}
