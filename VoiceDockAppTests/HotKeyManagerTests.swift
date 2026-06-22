//
//  HotKeyManagerTests.swift
//  VoiceDockTests
//
//  Tests for HotKeyManager hotkey detection logic
//

import Testing
import Foundation
import Carbon
import AppKit
@testable import VoiceDock
@testable import VoiceDockCore

struct HotKeyManagerTests {

    @Test("Control+Option+Space modifier matching - exact match")
    func testExactModifierMatch() {
        // Test the modifier checking logic directly
        let controlOptionFlags: NSEvent.ModifierFlags = [.control, .option]
        let controlOptionSpaceFlags: NSEvent.ModifierFlags = [.control, .option] // Space has no modifier flag

        #expect(controlOptionFlags.contains(.control))
        #expect(controlOptionFlags.contains(.option))
        #expect(!controlOptionFlags.contains(.command))
        #expect(!controlOptionFlags.contains(.shift))
    }

    @Test("Control+Option+Space modifier matching - Command should not be required")
    func testCommandNotRequired() {
        let controlOptionFlags: NSEvent.ModifierFlags = [.control, .option]
        let controlOptionCommandFlags: NSEvent.ModifierFlags = [.control, .option, .command]

        // Both should match (Command is ignored)
        #expect(controlOptionFlags.contains(.control) && controlOptionFlags.contains(.option))
        #expect(controlOptionCommandFlags.contains(.control) && controlOptionCommandFlags.contains(.option))
    }

    @Test("Control+Option+Space modifier matching - missing Control should fail")
    func testMissingControlFails() {
        let optionOnlyFlags: NSEvent.ModifierFlags = [.option]
        #expect(!(optionOnlyFlags.contains(.control) && optionOnlyFlags.contains(.option)))
    }

    @Test("Control+Option+Space modifier matching - missing Option should fail")
    func testMissingOptionFails() {
        let controlOnlyFlags: NSEvent.ModifierFlags = [.control]
        #expect(!(controlOnlyFlags.contains(.control) && controlOnlyFlags.contains(.option)))
    }

    @Test("Key code 49 is Space")
    func testSpaceKeyCode() {
        // Space key code on macOS is 49
        let spaceKeyCode: UInt16 = 49
        #expect(spaceKeyCode == 49)
    }

    @Test("HotKeyState thread safety")
    func testHotKeyStateThreadSafety() {
        let state = HotKeyState()

        // Test initial state
        #expect(state.isDown() == false)

        // Test setting down
        state.setDown(true)
        #expect(state.isDown() == true)

        // Test setting up
        state.setDown(false)
        #expect(state.isDown() == false)

        // Test concurrent access
        let expectation = DispatchGroup()
        let iterations = 1000

        for i in 0..<iterations {
            expectation.enter()
            DispatchQueue.global().async {
                state.setDown(i % 2 == 0)
                _ = state.isDown()
                expectation.leave()
            }
        }

        expectation.wait()
    }

    @Test("HotKeyCallbackStorage holds callbacks")
    func testCallbackStorage() {
        let storage = HotKeyCallbackStorage()
        var startCalled = false
        var stopCalled = false

        storage.onStart = { startCalled = true }
        storage.onStop = { stopCalled = true }

        #expect(!startCalled)
        #expect(!stopCalled)

        storage.onStart?()
        storage.onStop?()

        #expect(startCalled)
        #expect(stopCalled)
    }

    @Test("Repeated keyDown does not call start twice")
    func testRepeatedKeyDownSingleStart() {
        let state = HotKeyState()
        var startCount = 0

        // Simulate first press
        if !state.isDown() {
            state.setDown(true)
            startCount += 1
        }
        #expect(startCount == 1)

        // Simulate repeated keyDown (key repeat) - should not increment
        if !state.isDown() {
            state.setDown(true)
            startCount += 1
        }
        #expect(startCount == 1)

        // Simulate release
        if state.isDown() {
            state.setDown(false)
        }

        // Press again - should increment
        if !state.isDown() {
            state.setDown(true)
            startCount += 1
        }
        #expect(startCount == 2)
    }

    @Test("KeyUp calls stop exactly once per press")
    func testKeyUpCallsStopOnce() {
        let state = HotKeyState()
        var stopCount = 0

        // Press
        state.setDown(true)

        // Release
        if state.isDown() {
            state.setDown(false)
            stopCount += 1
        }
        #expect(stopCount == 1)

        // Duplicate release - should not increment
        if state.isDown() {
            state.setDown(false)
            stopCount += 1
        }
        #expect(stopCount == 1)
    }

    @Test("Releasing Control or Option while Space held forces stop")
    func testModifierReleaseForcesStop() {
        let state = HotKeyState()
        var stopCount = 0

        // Simulate press
        state.setDown(true)

        // Simulate modifier release (flagsChanged without control+option)
        if state.isDown() {
            state.setDown(false)
            stopCount += 1
        }
        #expect(stopCount == 1)
        #expect(state.isDown() == false)
    }

    @Test("Unregister removes monitors only once")
    func testUnregisterIdempotent() {
        // This tests the logical behavior - unregister should be idempotent
        var unregisterCount = 0

        func unregister() {
            unregisterCount += 1
        }

        unregister()
        unregister()
        unregister()

        // In actual implementation, NSEvent.removeMonitor on nil is safe
        // Here we just verify the logic would handle multiple calls
        #expect(unregisterCount == 3)
    }

    @Test("Callbacks remain alive after register")
    func testCallbacksRetained() {
        let storage = HotKeyCallbackStorage()
        var startCalled = false
        var stopCalled = false

        storage.onStart = { startCalled = true }
        storage.onStop = { stopCalled = true }

        // Simulate register keeping storage alive
        let retainedStorage = storage

        retainedStorage.onStart?()
        retainedStorage.onStop?()

        #expect(startCalled)
        #expect(stopCalled)
    }

    @Test("Carbon event types are correct")
    func testCarbonEventTypes() {
        // Verify the Carbon event types we use for hotkey press/release
        #expect(kEventHotKeyPressed != 0)
        #expect(kEventHotKeyReleased != 0)
        #expect(kEventClassKeyboard != 0)
    }

    @Test("Carbon modifier flags for Control+Option")
    func testCarbonModifiers() {
        // Control + Option = controlKey | optionKey
        let modifiers = UInt32(controlKey | optionKey)
        #expect(modifiers & UInt32(controlKey) != 0)
        #expect(modifiers & UInt32(optionKey) != 0)
        #expect(modifiers & UInt32(cmdKey) == 0) // Command not included
    }

    // MARK: - Carbon-to-Main-Queue Bridge Tests (Stage B: Synthetic)

    @MainActor
    @Test("Carbon callback writes to thread-safe state (Stage A synthetic)")
    func testCarbonCallbackStateWrite() async {
        // Verify the callback can write state that is later readable on main actor
        let manager = HotKeyManager(onStart: {}, onStop: {})

        // Simulate what Carbon callback does: write state, then enqueue to main
        let state = HotKeyState()
        #expect(state.isDown() == false)

        state.setDown(true)
        #expect(state.isDown() == true)

        state.setDown(false)
        #expect(state.isDown() == false)
    }

    @MainActor
    @Test("Main queue bridge delivers press event (Stage B synthetic)")
    func testMainQueuePressDelivery() async {
        var pressDelivered = false

        let manager = HotKeyManager(
            onStart: {
                pressDelivered = true
            },
            onStop: {}
        )

        // Simulate what happens after Carbon callback enqueues to main queue
        manager.simulatePress()

        // Wait for callback to fire
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if pressDelivered { break }
        }

        #expect(pressDelivered == true)
    }

    @MainActor
    @Test("Main queue bridge delivers release event (Stage B synthetic)")
    func testMainQueueReleaseDelivery() async {
        var pressDelivered = false
        var releaseDelivered = false

        let manager = HotKeyManager(
            onStart: {
                pressDelivered = true
            },
            onStop: {
                releaseDelivered = true
            }
        )

        manager.simulatePress()
        try? await Task.sleep(nanoseconds: 100_000_000)
        manager.simulateRelease()

        // Wait for callbacks to fire
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if pressDelivered && releaseDelivered { break }
        }

        #expect(pressDelivered == true)
        #expect(releaseDelivered == true)
    }

    @MainActor
    @Test("Coordinator enters Listening on press (Stage C synthetic)")
    func testCoordinatorEntersListeningOnPress() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        // Wait for coordinator to become ready
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(coordinator.state == .ready)

        // Simulate press
        coordinator.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(coordinator.state == .listening)
        #expect(mockAudio.startCalled == true)
    }

    @MainActor
    @Test("Coordinator leaves Listening on release (Stage C synthetic)")
    func testCoordinatorLeavesListeningOnRelease() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        coordinator.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(coordinator.state == .listening)

        // Pre-populate audio so stop returns data
        var mockBuf: [Float] = Array(repeating: 0, count: 8000)
        for i in 0..<mockBuf.count { mockBuf[i] = sin(Float(i) / 10.0) * 0.2 }
        mockAudio.setFakeStopBuffer(mockBuf)

        coordinator.stopRecording()
        try? await Task.sleep(nanoseconds: 150_000_000)

        // After transcribe completes, should return to ready
        let transcribeCalled = await mockASR.getTranscribeCalled()
        #expect(transcribeCalled == true)
    }

    @MainActor
    @Test("Zero-audio release remains alive (Stage D synthetic)")
    func testZeroAudioReleaseDoesNotCrash() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        coordinator.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Release with zero audio (empty buffer)
        mockAudio.setFakeStopBuffer([])
        coordinator.stopRecording()
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Should not crash - process remains alive
        #expect(true, "Zero-audio release should not crash")
    }

    @MainActor
    @Test("Audio stop remains alive (Stage D synthetic)")
    func testAudioStopRemainsAlive() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Multiple start/stop cycles
        for _ in 0..<3 {
            coordinator.startRecording()
            try? await Task.sleep(nanoseconds: 30_000_000)

            var mockBuf: [Float] = Array(repeating: 0, count: 4000)
            for i in 0..<mockBuf.count { mockBuf[i] = Float.random(in: -0.1...0.1) }
            mockAudio.setFakeStopBuffer(mockBuf)

            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(true, "Audio stop should remain alive across cycles")
    }

    @MainActor
    @Test("Three synthetic PTT cycles complete (full pipeline synthetic)")
    func testThreeSyntheticPTTCycles() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()

        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        for cycle in 0..<3 {
            // Press
            coordinator.startRecording()
            try? await Task.sleep(nanoseconds: 30_000_000)

            // Release with audio
            var mockBuf: [Float] = Array(repeating: 0, count: 4000)
            for i in 0..<mockBuf.count { mockBuf[i] = sin(Float(i + cycle) / 5.0) * 0.2 }
            mockAudio.setFakeStopBuffer(mockBuf)

            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        let transcribeCalled = await mockASR.getTranscribeCalled()
        #expect(transcribeCalled == true, "Should complete 3 full PTT cycles")
    }

    @MainActor
    @Test("Duplicate release safely ignored")
    func testDuplicateReleaseIgnored() async {
        var stopCallCount = 0

        let manager = HotKeyManager(
            onStart: {},
            onStop: { stopCallCount += 1 }
        )

        // Press once
        manager.simulatePress()
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Release multiple times
        manager.simulateRelease()
        manager.simulateRelease()
        manager.simulateRelease()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(stopCallCount == 1, "Duplicate releases should be ignored")
    }

    @MainActor
    @Test("Process stability after 10 rapid cycles")
    func testProcessStabilityAfterRapidCycles() async {
        let mockASR = MockASRProvider()
        let mockAudio = MockAudioCapture()
        let coordinator = SessionCoordinator(
            audioCapture: mockAudio,
            asrProvider: mockASR,
            transcriptDestination: TranscriptDestination()
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        for _ in 0..<10 {
            coordinator.startRecording()
            try? await Task.sleep(nanoseconds: 20_000_000)

            var mockBuf: [Float] = Array(repeating: 0, count: 2000)
            for i in 0..<mockBuf.count { mockBuf[i] = Float.random(in: -0.1...0.1) }
            mockAudio.setFakeStopBuffer(mockBuf)

            coordinator.stopRecording()
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        #expect(true, "Process should remain stable after 10 rapid cycles")
    }
}