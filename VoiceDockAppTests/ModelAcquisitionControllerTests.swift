//
//  ModelAcquisitionControllerTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.4.3 — Model download UI controller deterministic tests.
//
//  Covers the UI-facing `ModelAcquisitionController` against a temp-dir
//  `ModelStorage` and an injected downloader seam. No network access, no
//  production models, no production UserDefaults. The installer's real
//  transaction semantics (staging identity, lock release, cleanup) drive the
//  controller through initial refresh, download, progress, success, failure,
//  cancellation, retry, and stale-completion authority.
//

import XCTest
import Foundation
@testable import VoiceDockCore

/// A Sendable-safe suspend/resume gate. Tests can `wait()` (suspending) and
/// later `open()` (releasing all waiters). This replaces `AsyncStream.Iterator`,
/// which is not `Sendable` and therefore cannot cross a `Sendable` enum's
/// associated value under Swift 6 strict concurrency.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()

    /// Suspend until `open()` is called, or propagate `CancellationError` if
    /// the calling task is cancelled first (mimicking a real download that
    /// aborts its in-flight work on cancellation).
    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.pending = continuation
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let cont = pending
            pending = nil
            lock.unlock()
            cont?.resume(throwing: CancellationError())
        }
    }

    func open() {
        lock.lock()
        let cont = pending
        pending = nil
        lock.unlock()
        cont?.resume(returning: ())
    }

    /// True once a waiter has stored its continuation and is suspended. Tests
    /// poll this before `open()` so they never open a gate whose waiter has not
    /// yet arrived (which would otherwise be a no-op that the download then
    /// blocks on forever).
    func hasWaiter() -> Bool {
        lock.lock()
        let waiting = pending != nil
        lock.unlock()
        return waiting
    }

    private var pending: CheckedContinuation<Void, Error>?
}

/// A controllable snapshot downloader. Gates are keyed by model directory
/// name, so tests can hold one descriptor's download open while a second
/// completes independently, deterministically proving a stale operation cannot
/// overwrite a newer one.
private actor GatedDownloader: ModelSnapshotDownloading {
    enum Mode: Sendable {
        /// Write a valid model tree, then (optionally) wait on a gate.
        case succeed
        /// Throw after (optionally) waiting on a gate.
        case fail
        /// Throw CancellationError after (optionally) waiting on a gate.
        case cancel
    }

    let mode: Mode
    /// Gates keyed by model directory name (fast vs quality), so a test can
    /// hold one descriptor's download open independently of the other's,
    /// regardless of the order the downloads happen to start in. A nil entry
    /// means the matching descriptor runs ungated.
    let gatesByDirectory: [String: AsyncGate]
    /// Number of `download` invocations observed.
    private(set) var callCount = 0

    init(mode: Mode, gatesByDirectory: [String: AsyncGate] = [:]) {
        self.mode = mode
        self.gatesByDirectory = gatesByDirectory
    }

    func downloadCallCount() -> Int { callCount }

    func download(
        descriptor: QwenModelDescriptor,
        to destination: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws {
        callCount += 1
        // Gates keyed by descriptor so ordering of concurrent download starts
        // (which the MainActor task scheduler controls) cannot swap gate
        // bindings between two descriptors.
        let gate = gatesByDirectory[descriptor.canonicalDirectoryName]

        switch mode {
        case .succeed:
            // Emit intermediate progress to exercise the normalized callback.
            progressHandler?(0.1)
            progressHandler?(0.55)
            progressHandler?(0.9)
            progressHandler?(0.95)
            try writeValidModel(descriptor: descriptor, at: destination)
            progressHandler?(1.0)
            if let gate {
                try await gate.wait()
            }
        case .fail:
            progressHandler?(0.2)
            if let gate {
                try await gate.wait()
            }
            throw ModelAcquisitionStubError.downloadBoom
        case .cancel:
            progressHandler?(0.3)
            if let gate {
                try await gate.wait()
            }
            throw CancellationError()
        }
    }

    private func writeValidModel(descriptor: QwenModelDescriptor, at destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)

        for file in descriptor.requiredFiles {
            let fileURL = destination.appendingPathComponent(file)
            if file == "config.json" {
                let data = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
                try data.write(to: fileURL)
            } else {
                try Data("mock content".utf8).write(to: fileURL)
            }
        }

        // A non-indexed safetensors file is sufficient for validation.
        let safetensorsURL = destination.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)
    }
}

private struct ModelAcquisitionStubError: Error, Equatable {
    let message: String
    static let downloadBoom = ModelAcquisitionStubError(message: "download failed")
}

@MainActor
final class ModelAcquisitionControllerTests: XCTestCase {
    let fast = ASRModelSelection.qwen3_0_6B_8bit
    let quality = ASRModelSelection.qwen3_1_7B_4bit

    var tempBaseDir: URL!
    var storage: ModelStorage!
    /// The currently selected model (proven immutable by download by T10).
    var selected: ASRModelSelection = .qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockAcquisitionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBaseDir = tempDir
        storage = ModelStorage(baseDirectory: tempDir)
        selected = .qwen3_0_6B_8bit
    }

    override func tearDown() async throws {
        if let tempDir = tempBaseDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempBaseDir = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeController(
        downloader: ModelSnapshotDownloading,
        storage: ModelStorage? = nil
    ) -> ModelAcquisitionController {
        let resolvedStorage = storage ?? self.storage!
        let installer = ModelInstaller(storage: resolvedStorage, downloader: downloader)
        return ModelAcquisitionController(
            installer: installer,
            storage: resolvedStorage,
            selectedModelProvider: { [weak self] in self?.selected ?? .qwen3_0_6B_8bit }
        )
    }

    /// A fresh temp-dir `ModelStorage`, isolated per stress iteration so a
    /// cancelled/stale task from one iteration can never contaminate the next.
    private func makeFreshStorage() throws -> ModelStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockAcquisitionStress", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ModelStorage(baseDirectory: dir)
    }

    private func makeDownloader(
        mode: GatedDownloader.Mode,
        gatesByDirectory: [String: AsyncGate] = [:]
    ) -> GatedDownloader {
        GatedDownloader(mode: mode, gatesByDirectory: gatesByDirectory)
    }

    /// Wait until `predicate` holds, yielding the MainActor so published
    /// updates and detached task hops are observed.
    private func waitUntil(timeout: TimeInterval = 2.0, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Wait until an async `predicate` holds (e.g. an actor's observable
    /// backend state), yielding to the cooperative scheduler between polls.
    private func waitUntilAsync(timeout: TimeInterval = 5.0, _ predicate: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await predicate()) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Seed an installed Fast model tree directly (no download) so refresh sees
    /// it as valid.
    private func seedInstalled(_ descriptor: QwenModelDescriptor) async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in descriptor.requiredFiles {
            let url = dir.appendingPathComponent(file)
            if file == "config.json" {
                let data = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
                try data.write(to: url)
            } else {
                try Data("mock".utf8).write(to: url)
            }
        }
        try Data(repeating: 0x42, count: 1024).write(to: dir.appendingPathComponent("model.safetensors"))
    }

    // MARK: - T1 initial refresh: Fast installed, Quality missing

    func testInitialRefresh_FastInstalled_QualityMissing() async throws {
        try await seedInstalled(fast.modelDescriptor)

        let controller = makeController(downloader: makeDownloader(mode: .succeed))
        await controller.refreshInstalled()

        XCTAssertEqual(controller.state(for: fast), .installed)
        XCTAssertEqual(controller.state(for: quality), .idle)
    }

    // MARK: - T2 both missing

    func testInitialRefresh_BothMissing() async throws {
        let controller = makeController(downloader: makeDownloader(mode: .succeed))
        await controller.refreshInstalled()

        XCTAssertEqual(controller.state(for: fast), .idle)
        XCTAssertEqual(controller.state(for: quality), .idle)
    }

    // MARK: - T3 download enters downloading state

    func testDownload_EntersDownloadingState() async throws {
        let downloader = makeDownloader(mode: .succeed)
        let controller = makeController(downloader: downloader)

        controller.download(quality)

        XCTAssertEqual(controller.state(for: quality), .downloading(progress: 0))
        XCTAssertEqual(controller.activeOperation, quality)

        // Allow the (uncontested) download to finish so the actor's task drains.
        await waitUntil { controller.state(for: self.quality) == .installed }
    }

    // MARK: - T4 progress callback updates progress

    func testProgress_UpdatesProgress() async throws {
        // Hold completion open so we observe the intermediate progress updates.
        let gate = AsyncGate()
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [quality.modelDescriptor.canonicalDirectoryName: gate])
        let controller = makeController(downloader: downloader)

        controller.download(quality)

        // Wait for the 0.9 progress to be observed (controller clamps to 0…1).
        await waitUntil {
            if case .downloading(let p) = controller.state(for: self.quality), p >= 0.9 {
                return true
            }
            return false
        }

        if case .downloading(let p) = controller.state(for: quality) {
            XCTAssertGreaterThanOrEqual(p, 0.9)
            XCTAssertLessThanOrEqual(p, 1.0)
        } else {
            XCTFail("expected downloading state, got \(controller.state(for: quality))")
        }

        await waitUntil { gate.hasWaiter() }  // ensure the download is actually blocked
        gate.open()  // release completion
        await waitUntil { controller.state(for: self.quality) == .installed }
    }

    // MARK: - T5 successful install: revalidate → installed, ownership cleared

    func testSuccess_RevalidatesInstalled_ClearsOwnership() async throws {
        let downloader = makeDownloader(mode: .succeed)
        let controller = makeController(downloader: downloader)

        controller.download(quality)
        await waitUntil { controller.state(for: self.quality) == .installed }

        let isValid = await storage.isModelValid(quality.modelDescriptor)
        XCTAssertTrue(isValid)
        XCTAssertNil(controller.activeOperation)
        XCTAssertEqual(controller.state(for: quality), .installed)
    }

    // MARK: - T6 failure: failed state, ownership cleared, retry possible

    func testFailure_FailedState_OwnershipCleared_RetryPossible() async throws {
        let downloader = makeDownloader(mode: .fail)
        let controller = makeController(downloader: downloader)

        controller.download(quality)
        await waitUntil {
            if case .failed = controller.state(for: self.quality) { return true }
            return false
        }

        XCTAssertNil(controller.activeOperation)
        if case .failed(let message) = controller.state(for: quality) {
            XCTAssertNotNil(message)
        } else {
            XCTFail("expected failed state, got \(controller.state(for: quality))")
        }

        // Retry now succeeds with a fresh downloader.
        let retryDownloader = makeDownloader(mode: .succeed)
        let retryController = ModelAcquisitionController(
            installer: ModelInstaller(storage: storage, downloader: retryDownloader),
            storage: storage,
            selectedModelProvider: { [weak self] in self?.selected ?? .qwen3_0_6B_8bit }
        )
        retryController.retry(quality)
        await waitUntil { retryController.state(for: self.quality) == .installed }
        XCTAssertEqual(retryController.state(for: quality), .installed)
    }

    // MARK: - T7 cancellation: no red failure, authoritative state restored, cleared

    func testCancellation_NoRedFailure_AuthoritativeRestored_Cleared() async throws {
        let gate = AsyncGate()
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [quality.modelDescriptor.canonicalDirectoryName: gate])
        let controller = makeController(downloader: downloader)

        controller.download(quality)
        await waitUntil { gate.hasWaiter() }  // download genuinely blocked before cancel

        controller.cancel()
        await waitUntil { controller.activeOperation == nil }

        switch controller.state(for: quality) {
        case .idle:
            break  // Not installed → back to idle, no red failure.
        case .failed:
            XCTFail("cancellation must not produce a red failure state")
        default:
            break
        }

        XCTAssertNil(controller.activeOperation)

        let isValid = await storage.isModelValid(quality.modelDescriptor)
        XCTAssertFalse(isValid, "cancel of an uninstalled model must not install it")
    }

    // MARK: - T8 cancel → immediate retry

    func testCancelThenImmediateRetry() async throws {
        let gate = AsyncGate()
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [quality.modelDescriptor.canonicalDirectoryName: gate])
        let controller = makeController(downloader: downloader)

        controller.download(quality)
        await waitUntil { gate.hasWaiter() }  // download genuinely blocked before cancel

        controller.cancel()
        await waitUntil { controller.activeOperation == nil }
        // Deterministically wait for the cancelled install to release the
        // single-flight lock before retrying, so retry never sees a stale
        // "installation already in progress".
        await waitUntilAsync {
            !(await self.storage.isInstallationInProgress(for: self.quality.modelDescriptor))
        }

        // Immediate retry with a fresh, non-gated downloader.
        let retryDownloader = makeDownloader(mode: .succeed)
        let controller2 = makeController(downloader: retryDownloader)
        controller2.retry(quality)
        await waitUntil { controller2.state(for: self.quality) == .installed }

        XCTAssertEqual(controller2.state(for: quality), .installed)
    }

    // MARK: - T9 stale operation A completes after operation B begins

    func testStaleCompletion_CannotOverwriteNewer() async throws {
        // Two distinct descriptors so there is no single-flight lock contention:
        // A (Fast) can still be deterministically in flight while B (Quality)
        // begins as the newer operation. Both are gated; A is stale, B is new.
        let gateA = AsyncGate()
        let gateB = AsyncGate()
        // Gates bound by descriptor (fast→A, quality→B) so task-start ordering
        // cannot swap them, and the stale scenario is deterministic.
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [fast.modelDescriptor.canonicalDirectoryName: gateA, quality.modelDescriptor.canonicalDirectoryName: gateB])
        let controller = makeController(downloader: downloader)

        controller.download(fast)  // generation 1 (A), blocks on gateA
        await waitUntil { gateA.hasWaiter() }  // A's download is genuinely blocked

        // Newer operation B begins while A is still in flight: cancels A, bumps
        // the generation, and (gated) is now the owner but not yet complete.
        controller.download(quality)  // generation 2 (B), blocks on gateB
        await waitUntil { gateB.hasWaiter() }  // B's download is genuinely blocked

        // A is cancelled by B's start: its completion (cancellation unwind) is
        // stale (generation 1 != 2) and must NOT clear B's ownership. Give the
        // unwind a moment to run, then assert B still owns the operation.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // B remains the authoritative owner — A's stale completion must not
        // have cleared activeOperation or flipped Fast's row.
        XCTAssertEqual(controller.activeOperation, quality, "stale A must not clear B's ownership")
        XCTAssertTrue(
            {
                if case .downloading = controller.state(for: quality) { return true }
                return false
            }(),
            "B must still be in flight after A's stale completion"
        )

        // Release B's gate: B completes and becomes installed.
        gateB.open()
        await waitUntil {
            if case .installed = controller.state(for: self.quality) { return true }
            return false
        }

        // B remains authoritative: Quality installed; ownership cleared.
        XCTAssertEqual(controller.state(for: quality), .installed)
        XCTAssertNil(controller.activeOperation)
        let isValid = await storage.isModelValid(quality.modelDescriptor)
        XCTAssertTrue(isValid)
    }

    // MARK: - T10 downloading Quality must not modify selected Fast model

    func testDownloadingQuality_DoesNotModifySelectedFast() async throws {
        selected = .qwen3_0_6B_8bit
        let downloader = makeDownloader(mode: .succeed)
        let controller = makeController(downloader: downloader)

        controller.download(quality)
        await waitUntil { controller.state(for: self.quality) == .installed }

        XCTAssertEqual(controller.selectedModelProvider(), .qwen3_0_6B_8bit)
        XCTAssertEqual(selected, .qwen3_0_6B_8bit)
    }

    // MARK: - T11 already installed model displayed as installed, no redundant acquisition

    func testAlreadyInstalled_NoRedundantAcquisition() async throws {
        try await seedInstalled(fast.modelDescriptor)

        let downloader = makeDownloader(mode: .succeed)
        let controller = makeController(downloader: downloader)

        await controller.refreshInstalled()
        XCTAssertEqual(controller.state(for: fast), .installed)

        // Re-refresh still installed, and no download was invoked.
        await controller.refreshInstalled()
        XCTAssertEqual(controller.state(for: fast), .installed)
        let calls = await downloader.downloadCallCount()
        XCTAssertEqual(calls, 0, "refresh must not attempt a download for an already-installed model")
    }

    // MARK: - T12 presentation: Fast first + recommended, Quality second + optional

    func testPresentation_FastFirstRecommended_QualitySecondOptional() {
        XCTAssertEqual(
            ModelAcquisitionController.presentationOrder,
            [.qwen3_0_6B_8bit, .qwen3_1_7B_4bit]
        )
        XCTAssertEqual(
            ModelAcquisitionController.presentationOrder.first,
            .qwen3_0_6B_8bit,
            "Fast must sort first"
        )
        XCTAssertEqual(
            ModelAcquisitionController.isRecommended[.qwen3_0_6B_8bit],
            true,
            "Fast must be recommended"
        )
        XCTAssertEqual(
            ModelAcquisitionController.isRecommended[.qwen3_1_7B_4bit],
            false,
            "Quality must be optional"
        )
    }

    // MARK: - T13 onInstalled: authoritative install completion signal (0.4.4b)

    func testOnInstalledFiresExactlyOnceOnSuccess() async throws {
        let downloader = makeDownloader(mode: .succeed)
        let controller = makeController(downloader: downloader)
        var fired: [ASRModelSelection] = []
        controller.onInstalled = { fired.append($0) }

        controller.download(quality)
        await waitUntil { controller.state(for: self.quality) == .installed }

        XCTAssertEqual(fired, [quality], "authoritative success must fire exactly one onInstalled notice")
    }

    func testOnInstalledDoesNotFireOnFailure() async throws {
        let downloader = makeDownloader(mode: .fail)
        let controller = makeController(downloader: downloader)
        var fired: [ASRModelSelection] = []
        controller.onInstalled = { fired.append($0) }

        controller.download(quality)
        await waitUntil {
            if case .failed = controller.state(for: self.quality) { return true }
            return false
        }

        XCTAssertEqual(fired, [], "failed download must not fire an install completion notice")
    }

    func testOnInstalledDoesNotFireOnCancellation() async throws {
        let gate = AsyncGate()
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [quality.modelDescriptor.canonicalDirectoryName: gate])
        let controller = makeController(downloader: downloader)
        var fired: [ASRModelSelection] = []
        controller.onInstalled = { fired.append($0) }

        controller.download(quality)
        await waitUntil { gate.hasWaiter() }
        controller.cancel()
        await waitUntil { controller.activeOperation == nil }

        XCTAssertEqual(fired, [], "cancelled download must not fire an install completion notice")
    }

    func testOnInstalledDoesNotFireFromStaleCompletion() async throws {
        // Two distinct models: A (Fast) starts, then B (Quality) supersedes it.
        // A's completion is stale and must not fire onInstalled.
        let gateA = AsyncGate()
        let gateB = AsyncGate()
        let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [
            fast.modelDescriptor.canonicalDirectoryName: gateA,
            quality.modelDescriptor.canonicalDirectoryName: gateB
        ])
        let controller = makeController(downloader: downloader)
        var fired: [ASRModelSelection] = []
        controller.onInstalled = { fired.append($0) }

        controller.download(fast)   // A (stale)
        await waitUntil { gateA.hasWaiter() }
        controller.download(quality) // B (current); cancels A
        await waitUntil { gateB.hasWaiter() }

        // Release A first (stale completion), assert it does not fire.
        gateA.open()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired.contains(fast), "stale A completion must not fire onInstalled")

        // Release B: the authoritative install fires exactly once for Quality.
        gateB.open()
        await waitUntil {
            if case .installed = controller.state(for: self.quality) { return true }
            return false
        }
        XCTAssertEqual(fired, [quality], "only the authoritative B install fires onInstalled")
    }

    // MARK: - Stress: cancel → retry × 30

    func testStressCancelThenRetryThirtyTimes() async throws {
        for iteration in 0..<30 {
            let freshStorage = try makeFreshStorage()
            let gate = AsyncGate()
            let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [fast.modelDescriptor.canonicalDirectoryName: gate])
            let controller = makeController(downloader: downloader, storage: freshStorage)

            controller.download(fast)
            await waitUntil {
                if case .downloading = controller.state(for: self.fast) { return true }
                return false
            }
            // Ensure the installer has actually claimed the lock (the download
            // is in flight, blocked on the gate) before we cancel it.
            await waitUntilAsync {
                await freshStorage.isInstallationInProgress(for: self.fast.modelDescriptor)
            }
            controller.cancel()
            await waitUntil { controller.activeOperation == nil }

            // Deterministically wait for the cancelled install to release the
            // single-flight lock before retrying, so the retry never observes
            // a stale "installation already in progress".
            await waitUntilAsync {
                !(await freshStorage.isInstallationInProgress(for: self.fast.modelDescriptor))
            }

            // Retry with a fresh, ungated downloader against the SAME storage.
            let retryDownloader = makeDownloader(mode: .succeed)
            let retryController = makeController(downloader: retryDownloader, storage: freshStorage)
            retryController.retry(fast)
            await waitUntil { retryController.state(for: self.fast) == .installed }

            XCTAssertEqual(retryController.state(for: fast), .installed, "iteration \(iteration)")
        }
    }

    // MARK: - Stress: failure → retry × 30

    func testStressFailureRetryThirtyTimes() async throws {
        for iteration in 0..<30 {
            let freshStorage = try makeFreshStorage()
            let failing = makeDownloader(mode: .fail)
            let controller = makeController(downloader: failing, storage: freshStorage)
            controller.download(fast)
            await waitUntil {
                if case .failed = controller.state(for: self.fast) { return true }
                return false
            }

            // Failure must not leave a stale lock: retry succeeds in place.
            let retryDownloader = makeDownloader(mode: .succeed)
            let controller2 = makeController(downloader: retryDownloader, storage: freshStorage)
            controller2.retry(fast)
            await waitUntil { controller2.state(for: self.fast) == .installed }

            XCTAssertEqual(controller2.state(for: fast), .installed, "iteration \(iteration)")
        }
    }

    // MARK: - Stress: stale completion A → newer B authority × 30

    func testStressStaleCompletionNewerAuthorityThirtyTimes() async throws {
        for iteration in 0..<30 {
            let freshStorage = try makeFreshStorage()
            let gateA = AsyncGate()
            let gateB = AsyncGate()
            // Gates bound by descriptor (fast→A, quality→B); distinct descriptors
            // avoid single-flight lock contention.
            let downloader = makeDownloader(mode: .succeed, gatesByDirectory: [fast.modelDescriptor.canonicalDirectoryName: gateA, quality.modelDescriptor.canonicalDirectoryName: gateB])
            let controller = makeController(downloader: downloader, storage: freshStorage)

            controller.download(fast)  // A in flight, gated (stale)
            await waitUntil { gateA.hasWaiter() }  // A's download genuinely blocked

            // Newer operation B begins (cancels A, bumps generation), gated.
            controller.download(quality)  // B in flight, gated (current)
            await waitUntil { gateB.hasWaiter() }  // B's download genuinely blocked

            // A's cancellation unwind is stale (generation 1 != 2); it must not
            // clear B's ownership even after it runs.
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(controller.activeOperation, quality, "stale A must not clear B's ownership — iteration \(iteration)")

            // Release B: B completes and becomes the authoritative installed model.
            gateB.open()
            await waitUntil {
                if case .installed = controller.state(for: self.quality) { return true }
                return false
            }
            await waitUntilAsync {
                await freshStorage.isModelValid(self.quality.modelDescriptor)
            }

            XCTAssertEqual(controller.state(for: quality), .installed, "iteration \(iteration)")
            XCTAssertNil(controller.activeOperation, "iteration \(iteration)")
        }
    }
}