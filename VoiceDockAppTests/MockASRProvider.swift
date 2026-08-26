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

    // 0.3.1 lifecycle-guard seams: deterministic suspension of in-flight
    // transcription so tests can interleave cleanup/supersession and release
    // the workflow afterwards. All gate state is actor-isolated.
    private var transcribeGateOpened = false
    private var transcribeWaiters: [CheckedContinuation<Void, Never>] = []
    private var transcribeCallIndex = 0

    // 0.3.1: load gate for stale-initialization tests (T5). Suspends
    // provider.load() until the test opens the gate, so a coordinator can be
    // superseded while initialization is mid-flight.
    private var loadGateOpened = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldLoad = false

    /// Audio received per transcribe() call, in call order. Lets tests prove
    /// every retry attempt of one session observes the same immutable snapshot.
    private(set) var transcribeAudioLog: [[Float]] = []

    var loadCalled = false
    var warmupCalled = false
    var transcribeCalled = false
    var unloadCalled = false
    var lastTranscribedAudio: [Float]?

    func load() async throws {
        loadCalled = true
        if shouldHoldLoad {
            await waitForLoadGate()
        }
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
        let attemptIndex = transcribeCallIndex
        transcribeCallIndex += 1

        if recordAudioLog {
            transcribeAudioLog.append(audio)
        }

        // Deterministic hold point: first N calls suspend until the test opens
        // the gate, so the coordinator can be cleaned up / superseded while a
        // workflow is mid-flight.
        if holdFirstNCalls > 0 && attemptIndex < holdFirstNCalls {
            await waitForTranscribeGate()
        }

        if failFirstNCalls > 0 && attemptIndex < failFirstNCalls {
            throw VoiceDockError.transcriptionFailed(underlying: nil)
        }

        if transcribeShouldFail {
            throw VoiceDockError.transcriptionFailed(underlying: nil)
        }
        return transcribeResult
    }

    private func waitForTranscribeGate() async {
        if transcribeGateOpened { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.transcribeWaiters.append(continuation)
        }
    }

    private func waitForLoadGate() async {
        if loadGateOpened { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.loadWaiters.append(continuation)
        }
    }

    func unload() async {
        unloadCalled = true
        let callIndex = unloadCallCount
        unloadCallCount += 1
        // 0.3.2 teardown seams: hold the first N unload() calls at a gate so
        // tests can observe the coordinator in .cleaningUp and prove
        // idempotence while teardown is mid-flight. Actor-isolated.
        if holdFirstNUnloads > 0 && callIndex < holdFirstNUnloads {
            await waitForUnloadGate()
        }
    }

    /// Number of times unload() was invoked (invocation count, not completion
    /// count — proves duplicate cleanup does not start a second unload).
    private(set) var unloadCallCount = 0

    func getUnloadCallCount() -> Int { unloadCallCount }

    /// Make the first N unload() calls suspend until openUnloadGate().
    func holdUnload(calls n: Int) {
        holdFirstNUnloads = n
    }

    private var holdFirstNUnloads: Int = 0
    private var unloadGateOpened = false
    private var unloadWaiters: [CheckedContinuation<Void, Never>] = []

    private func waitForUnloadGate() async {
        if unloadGateOpened { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.unloadWaiters.append(continuation)
        }
    }

    func openUnloadGate() {
        unloadGateOpened = true
        let waiters = unloadWaiters
        unloadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Test helpers
    //
    // Setup methods are async actor-isolated: the test harness awaits them
    // before the coordinator spawns the workflow, so there is no concurrent
    // access. openGate methods are actor-isolated but safe to call while a
    // workflow is suspended on a continuation (that suspension releases the
    // actor executor). get* accessors are actor-isolated and must be awaited.

    func holdTranscribe(calls n: Int) async {
        holdFirstNCalls = n
    }

    func failTranscribe(calls n: Int) async {
        failFirstNCalls = n
    }

    func openTranscribeGate() {
        transcribeGateOpened = true
        let waiters = transcribeWaiters
        transcribeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Make load() suspend at the gate until `openLoadGate()` is called.
    /// Set BEFORE the workflow starts.
    func enableLoadHold() async {
        shouldHoldLoad = true
    }

    func openLoadGate() {
        loadGateOpened = true
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    nonisolated(unsafe) var recordAudioLog = false

    func getTranscribeAudioLog() -> [[Float]] { transcribeAudioLog }

    func getLoadCalled() -> Bool { loadCalled }
    func getWarmupCalled() -> Bool { warmupCalled }
    func getTranscribeCalled() -> Bool { transcribeCalled }
    func getUnloadCalled() -> Bool { unloadCalled }
    func getLastTranscribedAudio() -> [Float]? { lastTranscribedAudio }

    private var holdFirstNCalls: Int = 0
    private var failFirstNCalls: Int = 0

    /// Actor-isolated setter so tests on the main actor can configure the
    /// stubbed transcript without crossing actor isolation unsafely.
    func setTranscribeResult(_ result: String) async {
        transcribeResult = result
    }
}