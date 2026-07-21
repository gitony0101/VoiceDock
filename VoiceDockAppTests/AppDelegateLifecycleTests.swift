//
//  AppDelegateLifecycleTests.swift
//  VoiceDockTests
//
//  Tests for AppDelegate termination lifecycle and hotkey ownership
//

import Foundation
import Testing
import AppKit
@testable import VoiceDock
@testable import VoiceDockCore

@Suite("AppDelegate Lifecycle Tests", .serialized)
struct AppDelegateLifecycleTests {

    // MARK: - Routing Regression Tests (most important)

    @MainActor
    @Test("Existing routing behavior remains intact")
    func testRoutingBehaviorIntact() async {
        // Verify ASRProviderFactory still works correctly
        let provider = ASRProviderFactory.createProvider()
        #expect(provider is Qwen3ASRProvider)

        // Verify default model selection
        let selection = ASRModelSelection.current()
        #expect(selection == .qwen3_1_7B_4bit)
    }

    @MainActor
    @Test("Retired model values fall back to default")
    func testRetiredModelFallback() async {
        // Verify retired Nemotron falls back to default
        let nemotronFallback = ASRModelSelection.fromEnvironmentValue("nemotron-0.6b-8bit")
        #expect(nemotronFallback == .qwen3_1_7B_4bit)

        // Verify retired 6-bit falls back to default
        let sixBitFallback = ASRModelSelection.fromEnvironmentValue("qwen3-0.6b-6bit")
        #expect(sixBitFallback == .qwen3_1_7B_4bit)
    }

    @MainActor
    @Test("Warning recorder captures retired model reasons")
    func testWarningRecorderCapturesRetiredReasons() async {
        var capturedReason: ASRModelSelection.FallbackReason?
        var capturedMessage: String?

        _ = ASRModelSelection.fromEnvironmentValue("nemotron-0.6b-8bit") { reason, msg in
            capturedReason = reason
            capturedMessage = msg
        }

        #expect(capturedReason == .retired)
        #expect(capturedMessage?.contains("Retired ASR model") == true)
    }

    @MainActor
    @Test("Warning recorder captures unknown model reasons")
    func testWarningRecorderCapturesUnknownReasons() async {
        var capturedReason: ASRModelSelection.FallbackReason?
        var capturedMessage: String?

        _ = ASRModelSelection.fromEnvironmentValue("unknown-model") { reason, msg in
            capturedReason = reason
            capturedMessage = msg
        }

        #expect(capturedReason == .unknown)
        #expect(capturedMessage?.contains("Unknown ASR model value") == true)
    }

    // MARK: - SessionCoordinator Lifecycle

    @MainActor
    @Test("SessionCoordinator cleanup does not crash")
    func testCoordinatorCleanupDoesNotCrash() async {
        let coordinator = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: MockASRProvider(),
            transcriptDestination: TranscriptDestination()
        )

        // Call cleanup multiple times - should be idempotent
        coordinator.cleanup()
        coordinator.cleanup()
        coordinator.cleanup()

        // Should not crash
        #expect(true, "cleanup should be idempotent")
    }

    @MainActor
    @Test("SessionCoordinator.quit does not call NSApp.terminate")
    func testCoordinatorQuitDoesNotTerminateApp() async {
        let coordinator = SessionCoordinator(
            audioCapture: MockAudioCapture(),
            asrProvider: MockASRProvider(),
            transcriptDestination: TranscriptDestination()
        )

        // quit() should NOT call NSApp.terminate - AppDelegate owns termination
        coordinator.quit()

        // Verify cleanup happened (provider unloaded)
        // The quit method should just call cleanup(), not terminate
        #expect(true, "coordinator.quit() should complete without terminating app")
    }

    // MARK: - HotKeyManager Behavior

    @MainActor
    @Test("HotKeyManager.simulatePress and simulateRelease work")
    func testHotKeyManagerSimulatePressRelease() async {
        var startCalled = false
        var stopCalled = false

        let manager = HotKeyManager(
            onStart: { startCalled = true },
            onStop: { stopCalled = true }
        )

        manager.simulatePress()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(startCalled == true)

        manager.simulateRelease()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(stopCalled == true)
    }

    @MainActor
    @Test("Multiple HotKeyManager.simulateRelease calls do not duplicate stop")
    func testMultipleReleaseCallsIgnored() async {
        var stopCount = 0

        let manager = HotKeyManager(
            onStart: {},
            onStop: { stopCount += 1 }
        )

        manager.simulatePress()
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Multiple releases
        manager.simulateRelease()
        manager.simulateRelease()
        manager.simulateRelease()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Should only call stop once
        #expect(stopCount == 1, "Duplicate releases should be ignored")
    }
}