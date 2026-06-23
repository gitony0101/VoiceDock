//
//  MockASRProvider.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
@testable import VoiceDockCore

/// Mock ASR provider for testing SessionCoordinator
actor MockASRProvider: ASRProvider {
    var loadShouldFail = false
    var transcribeResult: String = "mock transcript"
    var transcribeShouldFail = false

    var loadCalled = false
    var warmupCalled = false
    var transcribeCalled = false
    var unloadCalled = false
    var lastTranscribedAudio: [Float]?

    func load() async throws {
        loadCalled = true
        if loadShouldFail {
            throw VoiceDockError.modelLoadFailed(underlying: nil)
        }
    }

    func warmup() async throws {
        warmupCalled = true
    }

    func transcribe(audio: [Float]) async throws -> String {
        transcribeCalled = true
        lastTranscribedAudio = audio
        if transcribeShouldFail {
            throw VoiceDockError.transcriptionFailed(underlying: nil)
        }
        return transcribeResult
    }

    func unload() async {
        unloadCalled = true
    }

    // Test helpers
    func getLoadCalled() -> Bool { loadCalled }
    func getWarmupCalled() -> Bool { warmupCalled }
    func getTranscribeCalled() -> Bool { transcribeCalled }
    func getUnloadCalled() -> Bool { unloadCalled }
    func getLastTranscribedAudio() -> [Float]? { lastTranscribedAudio }
}