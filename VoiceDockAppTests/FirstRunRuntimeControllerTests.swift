//
//  FirstRunRuntimeControllerTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.4.4b — Deterministic tests for the first-run speech-runtime
//  boundary. No network, no real model load, no production storage/preferences.
//
//  These tests pin the two first-run invariants:
//
//    1. A missing/invalid selected model is a SETUP PREREQUISITE, not a
//       runtime failure: no coordinator is constructed and no provider load is
//       attempted (D1).
//    2. An authoritative install of the required model starts the runtime
//       exactly once, with no overlap from repeated/stale/cancelled/failed
//       notices (D5).
//
//  `speechRuntimeReady` is asserted as "required model valid AND
//  coordinator.state == .ready" — never `activeModel != nil`.
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class FirstRunRuntimeControllerTests: XCTestCase {
    let fast = ASRModelSelection.qwen3_0_6B_8bit
    let quality = ASRModelSelection.qwen3_1_7B_4bit

    var tempBaseDir: URL!
    var storage: ModelStorage!
    /// The selected model supplied to the controller's selection provider.
    var selected: ASRModelSelection = .qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockFirstRunTests", isDirectory: true)
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

    /// A counting coordinator factory that produces a coordinator backed by a
    /// fresh MockASRProvider each call and records the number of constructions.
    private func makeController(
        loadShouldFail: Bool = false,
        constructionCounter: (() -> Void)? = nil
    ) -> (controller: FirstRunRuntimeController, lastProvider: () -> MockASRProvider?) {
        let providerBox = ProviderBox()
        let factory: (@MainActor () -> SessionCoordinator?) = {
            constructionCounter?()
            let mock = MockASRProvider()
            Task { await mock.setLoadShouldFail(loadShouldFail) }
            providerBox.provider = mock
            return SessionCoordinator(
                audioCapture: MockAudioCapture(),
                asrProvider: mock,
                transcriptDestination: TranscriptDestination(
                    isAccessibilityTrusted: { false },
                    postKeyboardEvent: { _, _ in }
                )
            )
        }
        let controller = FirstRunRuntimeController(
            storage: storage,
            selectedModelProvider: { [weak self] in self?.selected ?? .qwen3_0_6B_8bit },
            coordinatorProvider: factory
        )
        return (controller, { providerBox.provider })
    }

    /// A tiny Sendable-safe holder so the test can reach the provider created
    /// by the factory across the @MainActor closure.
    private final class ProviderBox: @unchecked Sendable {
        var provider: MockASRProvider?
    }

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

    private func waitUntil(timeout: TimeInterval = 5.0, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - B1: fresh install / Fast invalid → no load, no runtime failure

    func testB1_missingModelNoProviderLoadNoRuntimeFailure() async throws {
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }

        await controller.checkRequiredModel()
        XCTAssertFalse(controller.requiredModelValid)
        XCTAssertEqual(controller.speechRuntimePhase, .modelRequired)

        let started = controller.startIfRequiredModelValid()
        XCTAssertFalse(started, "a missing model must not start the runtime")
        XCTAssertNil(controller.coordinator, "no coordinator should be constructed for a missing model")
        XCTAssertEqual(constructions, 0, "no provider should be constructed for a missing model")
        XCTAssertFalse(controller.speechRuntimeReady)
    }

    // MARK: - B2: Fast already valid at launch → normal load + warmup

    func testB2_validFastAtLaunchLoadsNormally() async throws {
        try await seedInstalled(fast.modelDescriptor)

        let (controller, lastProvider) = makeController()
        await controller.checkRequiredModel()
        XCTAssertTrue(controller.requiredModelValid)

        XCTAssertTrue(controller.startIfRequiredModelValid())
        let coordinator = controller.coordinator
        XCTAssertNotNil(coordinator)

        // Normal init path: load + warmup → ready.
        await waitUntil { controller.speechRuntimePhase == .runtimeReady }
        XCTAssertTrue(controller.speechRuntimeReady)

        let provider = lastProvider()
        XCTAssertNotNil(provider)
        let loaded = await provider?.getLoadCalled() ?? false
        let warmed = await provider?.getWarmupCalled() ?? false
        XCTAssertTrue(loaded, "a valid model must load")
        XCTAssertTrue(warmed, "a valid model must warm up")
    }

    // MARK: - B3: Fast download succeeds → exactly one controlled start

    func testB3_fastDownloadSuccessStartsExactlyOnce() async throws {
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }
        await controller.checkRequiredModel()
        XCTAssertFalse(controller.requiredModelValid)

        // Install Fast authoritatively, then deliver the completion notice.
        try await seedInstalled(fast.modelDescriptor)
        controller.handleInstalled(fast)

        await waitUntil { constructions == 1 }
        XCTAssertEqual(constructions, 1, "exactly one coordinated start after install")
        await waitUntil { controller.speechRuntimePhase == .runtimeReady }
        XCTAssertTrue(controller.speechRuntimeReady)
    }

    // MARK: - B4: download fails → no recovery

    func testB4_failedDownloadNoRecovery() async throws {
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }
        await controller.checkRequiredModel()

        // No install actually performed; a notice for a still-missing model
        // must NOT start the runtime (the controller re-validates storage).
        controller.handleInstalled(fast)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(constructions, 0, "a still-missing model must not start the runtime")
        XCTAssertNil(controller.coordinator)
        XCTAssertEqual(controller.speechRuntimePhase, .modelRequired)
    }

    // MARK: - B5: download cancelled → no recovery

    func testB5_cancelledDownloadNoRecovery() async throws {
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }
        await controller.checkRequiredModel()

        // A cancellation never installs the model; a notice must not start.
        controller.handleInstalled(fast)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(constructions, 0)
        XCTAssertNil(controller.coordinator)
    }

    // MARK: - B7: Quality installed while Fast selected → no Fast disruption

    func testB7_qualityInstallWhileFastSelectedNoDisruption() async throws {
        try await seedInstalled(fast.modelDescriptor)
        selected = .qwen3_0_6B_8bit
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }
        await controller.checkRequiredModel()
        XCTAssertTrue(controller.startIfRequiredModelValid())
        await waitUntil { controller.speechRuntimePhase == .runtimeReady }

        let constructionsAfterFast = constructions

        // Quality installs while Fast is selected/active: no new start.
        controller.handleInstalled(quality)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(constructions, constructionsAfterFast, "Quality install must not restart the Fast runtime")
        XCTAssertTrue(controller.speechRuntimeReady)
    }

    // MARK: - B8/B12: repeated/fast-installed notices → no overlap; Quality missing does not block Fast

    func testB8_repeatedFastInstalledNoticesNoOverlap() async throws {
        var constructions = 0
        let (controller, _) = makeController { constructions += 1 }
        await controller.checkRequiredModel()
        try await seedInstalled(fast.modelDescriptor)

        // Many repeated authoritative notices: exactly one start.
        for _ in 0..<20 {
            controller.handleInstalled(fast)
        }
        await waitUntil { controller.speechRuntimePhase == .runtimeReady }
        XCTAssertEqual(constructions, 1, "repeated installed notices must not overlap recovery")
    }

    func testB12_qualityMissingDoesNotBlockFastReadiness() async throws {
        try await seedInstalled(fast.modelDescriptor)
        // Quality intentionally NOT installed.
        selected = .qwen3_0_6B_8bit
        let (controller, _) = makeController()
        await controller.checkRequiredModel()
        XCTAssertTrue(controller.requiredModelValid, "Fast valid must not depend on Quality")
        XCTAssertTrue(controller.startIfRequiredModelValid())
        await waitUntil { controller.speechRuntimePhase == .runtimeReady }
        XCTAssertTrue(controller.speechRuntimeReady)
    }

    // MARK: - B9: valid Fast but provider load fails → genuine .runtimeFailed

    func testB9_validFastButLoadFailsGenuineFailure() async throws {
        try await seedInstalled(fast.modelDescriptor)
        let (controller, lastProvider) = makeController(loadShouldFail: true)
        await controller.checkRequiredModel()
        XCTAssertTrue(controller.requiredModelValid)
        XCTAssertTrue(controller.startIfRequiredModelValid())

        // Load fails through backoff; the coordinator lands .failed.
        await waitUntil(timeout: 15) {
            if case .failed = controller.coordinator?.state { return true }
            return false
        }
        XCTAssertEqual(controller.speechRuntimePhase, .runtimeFailed, "a valid-but-failing model must be a genuine runtime failure, not modelRequired")
        XCTAssertFalse(controller.speechRuntimeReady)
        XCTAssertNotNil(lastProvider(), "provider was constructed; failure is genuine, not a missing-model setup state")
    }

    // MARK: - B10/B11: speechRuntimeReady derivation

    func testB10_activeModelNonNilButFailedCoordinatorIsNotReady() async throws {
        try await seedInstalled(fast.modelDescriptor)
        let (controller, _) = makeController(loadShouldFail: true)
        await controller.checkRequiredModel()
        _ = controller.startIfRequiredModelValid()
        await waitUntil(timeout: 15) {
            if case .failed = controller.coordinator?.state { return true }
            return false
        }
        // Even though requiredModelValid is true (and an active model could be
        // set), the coordinator is failed → speechRuntimeReady is false.
        XCTAssertFalse(controller.speechRuntimeReady)
    }

    func testB11_readyCoordinatorWithValidModelIsReady() async throws {
        try await seedInstalled(fast.modelDescriptor)
        let (controller, _) = makeController()
        await controller.checkRequiredModel()
        _ = controller.startIfRequiredModelValid()
        await waitUntil { controller.coordinator?.state == .ready }
        XCTAssertTrue(controller.speechRuntimeReady)
    }

    // MARK: - S1: download completion → recovery ×30

    func testS1_downloadCompletionRecoveryThirtyTimes() async throws {
        for i in 0..<30 {
            let fresh = try await makeFreshSetup()
            var constructions = 0
            let (controller, _) = fresh.makeController { constructions += 1 }
            await controller.checkRequiredModel()
            try await fresh.seedInstalled(fast.modelDescriptor)
            controller.handleInstalled(fast)
            await waitUntil { controller.speechRuntimePhase == .runtimeReady }
            XCTAssertEqual(constructions, 1, "iteration \(i): exactly one start")
        }
    }

    // MARK: - S2: cancel → retry → successful install → one recovery ×30

    func testS2_cancelThenSuccessOneRecoveryThirtyTimes() async throws {
        for i in 0..<30 {
            let fresh = try await makeFreshSetup()
            var constructions = 0
            let (controller, _) = fresh.makeController { constructions += 1 }
            await controller.checkRequiredModel()

            // simulate cancel (no install): notice does NOT start.
            controller.handleInstalled(fast)
            // simulate a later successful install: notice starts exactly once.
            try await fresh.seedInstalled(fast.modelDescriptor)
            controller.handleInstalled(fast)
            await waitUntil { controller.speechRuntimePhase == .runtimeReady }
            XCTAssertEqual(constructions, 1, "iteration \(i): exactly one start after cancel→success")
        }
    }

    // MARK: - S3: failure → retry → success → one recovery ×30

    func testS3_failureThenSuccessOneRecoveryThirtyTimes() async throws {
        for i in 0..<30 {
            let fresh = try await makeFreshSetup()
            var constructions = 0
            let (controller, _) = fresh.makeController { constructions += 1 }
            await controller.checkRequiredModel()

            // failure notice (still missing) → no start.
            controller.handleInstalled(fast)
            if constructions != 0 { return XCTFail("iteration \(i): failed download started runtime") }

            // success notice → exactly one start.
            try await fresh.seedInstalled(fast.modelDescriptor)
            controller.handleInstalled(fast)
            await waitUntil { controller.speechRuntimePhase == .runtimeReady }
            XCTAssertEqual(constructions, 1, "iteration \(i): exactly one start after failure→success")
        }
    }

    // MARK: - S5: repeated installed refresh while recovery in progress → no duplicate ×30

    func testS5_repeatedInstalledWhileRecoveringNoDuplicateThirtyTimes() async throws {
        for i in 0..<30 {
            let fresh = try await makeFreshSetup()
            var constructions = 0
            let (controller, _) = fresh.makeController { constructions += 1 }
            await controller.checkRequiredModel()
            try await fresh.seedInstalled(fast.modelDescriptor)

            // Repeated notices while recovery would be in progress.
            for _ in 0..<10 {
                controller.handleInstalled(fast)
            }
            await waitUntil { controller.speechRuntimePhase == .runtimeReady }
            XCTAssertEqual(constructions, 1, "iteration \(i): no duplicate recovery")
        }
    }

    // MARK: - Stress fixture

    /// A fresh temp-dir model storage per stress iteration, plus convenience
    /// wrappers to seed and build a controller against it.
    @MainActor
    private struct FreshSetup {
        let storage: ModelStorage

        func seedInstalled(_ descriptor: QwenModelDescriptor) async throws {
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

        func makeController(
            constructionCounter: @escaping () -> Void
        ) -> (controller: FirstRunRuntimeController, lastProvider: () -> MockASRProvider?) {
            let providerBox = FirstRunRuntimeControllerTests.ProviderBox()
            let selectedBox = SelectedBox()
            selectedBox.selected = .qwen3_0_6B_8bit
            let factory: (@MainActor () -> SessionCoordinator?) = {
                constructionCounter()
                let mock = MockASRProvider()
                providerBox.provider = mock
                return SessionCoordinator(
                    audioCapture: MockAudioCapture(),
                    asrProvider: mock,
                    transcriptDestination: TranscriptDestination(
                        isAccessibilityTrusted: { false },
                        postKeyboardEvent: { _, _ in }
                    )
                )
            }
            let controller = FirstRunRuntimeController(
                storage: storage,
                selectedModelProvider: { selectedBox.selected },
                coordinatorProvider: factory
            )
            return (controller, { providerBox.provider })
        }

        private final class SelectedBox: @unchecked Sendable {
            var selected: ASRModelSelection = .qwen3_0_6B_8bit
        }
    }

    private func makeFreshSetup() async throws -> FreshSetup {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockFirstRunStress", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FreshSetup(storage: ModelStorage(baseDirectory: dir))
    }
}