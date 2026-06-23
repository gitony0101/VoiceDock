//
//  SessionCoordinatorTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    var sut: SessionCoordinator!
    var mockASRProvider: MockASRProvider!
    var mockAudioCapture: MockAudioCapture!

    override func setUp() {
        super.setUp()
        mockASRProvider = MockASRProvider()
        mockAudioCapture = MockAudioCapture()
    }

    override func tearDown() {
        sut = nil
        mockASRProvider = nil
        mockAudioCapture = nil
        super.tearDown()
    }

    func testInitialStateTransitionsToReady() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(sut.state, .ready, "Coordinator should reach ready state")
    }

    func testStartRecordingTransitionsToListening() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)

        XCTAssertEqual(sut.state, .listening, "Should transition to listening state")
        XCTAssertTrue(mockAudioCapture.startCalled, "AudioCapture.start should be called")
    }

    func testDuplicatePressIgnoredWhileListening() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        sut.startRecording()
        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)

        XCTAssertEqual(sut.state, .listening)
        XCTAssertEqual(mockAudioCapture.startCallCount, 1)
    }

    func testStopRecordingFromListeningCallsTranscribe() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Pre-populate mock capture so Stop yields non-empty audio.
        var mockBuf: [Float] = Array(repeating: 0, count: 16000)
        for i in 0..<mockBuf.count { mockBuf[i] = sin(Float(i) / 5.0) * 0.3 }
        mockAudioCapture.setFakeStopBuffer(mockBuf)

        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)
        sut.stopRecording()
        try? await Task.sleep(nanoseconds: 200_000_000)

        let transcribeCalled = await mockASRProvider.getTranscribeCalled()
        XCTAssertTrue(transcribeCalled, "Transcribe should have been called")
    }

    func testReleaseOutsideListeningIsIgnored() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        sut.stopRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)

        XCTAssertEqual(sut.state, .ready)
        XCTAssertFalse(mockAudioCapture.stopCalled)
    }

    func testZeroAudioReleaseReturnsReadyWithoutTranscribe() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        mockAudioCapture.setFakeStopBuffer([])
        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)
        sut.stopRecording()
        try? await Task.sleep(nanoseconds: 200_000_000)

        let transcribeCalled = await mockASRProvider.getTranscribeCalled()
        XCTAssertFalse(transcribeCalled, "Empty audio should not be sent to ASR")
        XCTAssertEqual(sut.state, .ready, "Empty release should recover to ready")
    }

    func testAudioStartFailureFollowedByReleaseKeepsAppAlive() async {
        mockAudioCapture.startShouldThrow = true
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)
        sut.stopRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)

        if case .failed = sut.state {
            XCTAssertTrue(mockAudioCapture.cancelCalled)
            XCTAssertFalse(mockAudioCapture.stopCalled)
        } else {
            XCTFail("Audio start failure should enter failed state")
        }
    }

    func testCleanup() async {
        sut = SessionCoordinator(
            audioCapture: mockAudioCapture,
            asrProvider: mockASRProvider,
            transcriptDestination: TranscriptDestination()
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        sut.startRecording()
        try? await Task.sleep(nanoseconds: 75_000_000)
        sut.cleanup()
        XCTAssertTrue(mockAudioCapture.cancelCalled)
    }
}
