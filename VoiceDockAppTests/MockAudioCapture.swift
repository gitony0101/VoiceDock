//
//  MockAudioCapture.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import AVFoundation
import os.log
@testable import VoiceDockCore

private let logger = Logger(subsystem: "com.voicedock.tests", category: "MockAudioCapture")

/// Mock AudioCapture for testing - implements the protocol.
/// `start()` does NOT clear the recorded buffer; instead it starts accepting
/// pre-loaded samples; `stop()` returns the buffer.
final class MockAudioCapture: AudioCaptureProtocol {
    private(set) var startCalled = false
    private(set) var startCallCount = 0
    private(set) var stopCalled = false
    private(set) var cancelCalled = false
    private(set) var currentBuffer: [Float]
    private var stickyBuffer: [Float] = []
    var startShouldThrow = false

    init(initial: [Float] = []) {
        self.currentBuffer = initial
    }

    func start() throws {
        startCalled = true
        startCallCount += 1
        if startShouldThrow {
            throw VoiceDockError.audioEngineStartFailed
        }
        currentBuffer = stickyBuffer
        logger.info("start()")
    }

    func stop() -> [Float] {
        stopCalled = true
        let snapshot = self.currentBuffer
        logger.info("stop() returning \(snapshot.count) samples")
        return snapshot
    }

    func cancel() {
        cancelCalled = true
        // Don't clear currentBuffer; stop() may still need it for cancel-flow inspection.
        logger.info("cancel()")
    }

    /// Set samples that should be returned by `stop()`.
    func setFakeStopBuffer(_ buffer: [Float]) {
        self.stickyBuffer = buffer
        self.currentBuffer = buffer
    }
}
