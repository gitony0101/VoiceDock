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

    // 0.3.1: legacy load-hold flag retained for API compatibility; the active
    // gating mechanism is the per-call gate table above.
    private var shouldHoldLoad = false
    private var loadGateOpened = false

    /// Audio received per transcribe() call, in call order. Lets tests prove
    /// every retry attempt of one session observes the same immutable snapshot.
    private(set) var transcribeAudioLog: [[Float]] = []

    var loadCalled = false
    var warmupCalled = false
    var transcribeCalled = false
    var unloadCalled = false
    var lastTranscribedAudio: [Float]?

    // 0.3.3 recovery-contract instrumentation (R1–R8): invocation counts and
    // per-call deterministic suspension gates so tests can pin a SPECIFIC
    // load call in .loadingModel and prove exactly-once initialization
    // ownership with clean attribution windows.
    private(set) var loadCallCount = 0
    private(set) var warmupCallCount = 0

    // 0.3.3: holdLoadCalls[callIndex] = true means load() invocation number
    // (callIndex + 1) suspends at its own dedicated gate until
    // releaseLoadCall(callIndex) is called. Each call gets an independent
    // gate — releasing #1 never releases #2.
    private var holdLoadCalls: [Bool] = []
    private var loadCallGateOpened: [Bool] = []
    /// Set when a gated load call has entered its hold (before suspending).
    private(set) var loadCallsInsideHold: Set<Int> = []

    func load() async throws {
        loadCalled = true
        let callIndex = loadCallCount
        loadCallCount += 1
        if callIndex < holdLoadCalls.count, holdLoadCalls[callIndex] {
            await waitForPerCallLoadGate(callIndex: callIndex)
            // NON-COOPERATIVE mode: after release, this load completes
            // successfully even though the calling Task may have been
            // cancelled while suspended. This models a real provider whose
            // load is not cooperatively cancellable; generation authority in
            // SessionCoordinator must stay correct regardless.
        }
        if loadShouldFail {
            throw VoiceDockError.modelLoadFailed(underlying: nil)
        }
    }

    private func waitForPerCallLoadGate(callIndex: Int) async {
        if callIndex < loadCallGateOpened.count, loadCallGateOpened[callIndex] { return }
        loadCallsInsideHold.insert(callIndex)
        defer { loadCallsInsideHold.remove(callIndex) }
        while !(callIndex < loadCallGateOpened.count && loadCallGateOpened[callIndex]) {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
                // Polling keeps the hold deterministic for live generations;
                // cancellation breaks the wait so retry()'s drain (R2) of a
                // retired generation can never deadlock on this mock.
            } catch {
                // NON-COOPERATIVE semantics: a cancelled caller stops
                // WAITING but the load still completes successfully — the
                // provider operation itself is not cooperatively cancellable.
                return
            }
        }
        // After release (or after cancellation broke the wait), fall through:
        // load() proceeds to its normal success/failure outcome regardless of
        // Task.isCancelled. Generation authority in SessionCoordinator is the
        // correctness boundary, not mock cancellation.
    }

    /// Hold load() invocation #(index+1) at its own independent gate.
    /// `nonCooperative: true` means the released call returns SUCCESS even if
    /// its caller Task was cancelled while held (models non-cancellable
    /// provider work). The default polling wait is cancellation-aware, which
    /// only affects whether the CALL stops holding — never the outcome.
    func holdLoadCall(at index: Int) async {
        while holdLoadCalls.count <= index {
            holdLoadCalls.append(false)
            loadCallGateOpened.append(false)
        }
        holdLoadCalls[index] = true
        loadCallGateOpened[index] = false
    }

    /// Release ONLY load() invocation #(index+1). Other held calls stay put.
    func releaseLoadCall(at index: Int) async {
        guard index < loadCallGateOpened.count else { return }
        loadCallGateOpened[index] = true
    }

    /// True once load() invocation #(index+1) has entered its hold.
    func isLoadCallInsideHold(_ index: Int) -> Bool {
        loadCallsInsideHold.contains(index)
    }

    func warmup() async throws {
        warmupCalled = true
        warmupCallCount += 1
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
        // 0.3.3: cancellation-aware hold. A retired initialization generation
        // (cancelled by retry()'s drain, R2) must not hold its gate forever —
        // otherwise retry() awaiting the retired task would deadlock. Polling
        // keeps the hold deterministic for live generations while letting
        // cancellation break the wait for retired ones.
        while !loadGateOpened {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return // cancelled/retired: stop holding
            }
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
        // 0.3.3: legacy shared-gate API preserved for existing 0.3.1/0.3.2
        // tests. Implemented as "hold whatever call arrives next, one at a
        // time": each arriving load call gets its own gate entry appended,
        // so openLoadGate releases exactly ONE held call (the earliest still
        // held), never several at once.
        holdLoadCalls.append(true)
        loadCallGateOpened.append(false)
    }

    func openLoadGate() {
        // Release the EARLIEST still-held call only (per-call semantics).
        // Note: firstIndex(where:) receives the ELEMENT (Bool), not the
        // index, so scan indices explicitly.
        for i in loadCallGateOpened.indices {
            if i < holdLoadCalls.count, holdLoadCalls[i], !loadCallGateOpened[i] {
                loadCallGateOpened[i] = true
                return
            }
        }
    }

    nonisolated(unsafe) var recordAudioLog = false

    func getTranscribeAudioLog() -> [[Float]] { transcribeAudioLog }

    func getLoadCalled() -> Bool { loadCalled }
    func getWarmupCalled() -> Bool { warmupCalled }
    func getTranscribeCalled() -> Bool { transcribeCalled }
    func getUnloadCalled() -> Bool { unloadCalled }
    func getLastTranscribedAudio() -> [Float]? { lastTranscribedAudio }

    // 0.3.3 recovery seams (actor-isolated accessors).
    func getLoadCallCount() -> Int { loadCallCount }
    func getWarmupCallCount() -> Int { warmupCallCount }

    /// Actor-isolated setter so tests can flip load failure deterministically
    /// without unsafely crossing actor isolation from the main actor.
    func setLoadShouldFail(_ value: Bool) async {
        loadShouldFail = value
    }

    private var holdFirstNCalls: Int = 0
    private var failFirstNCalls: Int = 0

    /// Actor-isolated setter so tests on the main actor can configure the
    /// stubbed transcript without crossing actor isolation unsafely.
    func setTranscribeResult(_ result: String) async {
        transcribeResult = result
    }
}