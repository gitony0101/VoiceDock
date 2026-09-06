//
//  PermissionManagerTests.swift
//  VoiceDockAppTests
//
//  Deterministic permission refresh and prompt regression tests.
//

import AVFoundation
import XCTest
@testable import VoiceDock

@MainActor
final class PermissionManagerTests: XCTestCase {
    private final class MockPermissionProvider: PermissionStatusProviding {
        var microphoneStatus: AVAuthorizationStatus = .notDetermined
        var microphoneRequestResult = false
        var accessibilityTrusted = false
        private(set) var microphoneRequestCount = 0
        private(set) var accessibilityPromptCount = 0

        func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
            microphoneStatus
        }

        func requestMicrophoneAccess() async -> Bool {
            microphoneRequestCount += 1
            microphoneStatus = microphoneRequestResult ? .authorized : .denied
            return microphoneRequestResult
        }

        func isAccessibilityTrusted() -> Bool {
            accessibilityTrusted
        }

        func requestAccessibilityPrompt() -> Bool {
            accessibilityPromptCount += 1
            return accessibilityTrusted
        }
    }

    func testAccessibilityTrueMapsToGrantedUIStatus() {
        let provider = MockPermissionProvider()
        provider.accessibilityTrusted = true

        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)

        XCTAssertTrue(manager.accessibilityStatus)
        XCTAssertEqual(manager.accessibilityPermissionStatus, .granted)
    }

    func testAccessibilityFalseMapsToDeniedUIStatus() {
        let provider = MockPermissionProvider()
        provider.accessibilityTrusted = false

        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)

        XCTAssertFalse(manager.accessibilityStatus)
        XCTAssertEqual(manager.accessibilityPermissionStatus, .denied)
    }

    func testLiveRefreshReplacesStaleCachedAccessibilityValue() {
        let provider = MockPermissionProvider()
        provider.accessibilityTrusted = false
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        XCTAssertFalse(manager.accessibilityStatus)

        provider.accessibilityTrusted = true
        manager.refresh(reason: .manualRefresh)

        XCTAssertTrue(manager.accessibilityStatus)
        XCTAssertEqual(manager.accessibilityPermissionStatus, .granted)
        XCTAssertEqual(manager.lastRefreshReason, .manualRefresh)
    }

    func testRefreshReasonsCoverRequiredLifecyclePointsWithoutPrompting() {
        let provider = MockPermissionProvider()
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        let reasons: [PermissionManager.RefreshReason] = [
            .applicationDidBecomeActive,
            .popoverWillOpen,
            .settingsReturn,
            .retry,
            .manualRefresh
        ]

        for reason in reasons {
            manager.refresh(reason: reason)
            XCTAssertEqual(manager.lastRefreshReason, reason)
        }

        XCTAssertEqual(provider.accessibilityPromptCount, 0)
    }

    func testMicrophoneRequestCompletionRefreshesPublishedStatus() async {
        let provider = MockPermissionProvider()
        provider.microphoneRequestResult = true
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        XCTAssertEqual(manager.microphoneStatus, .notDetermined)

        let status = await manager.requestMicrophone()

        XCTAssertEqual(status, .granted)
        XCTAssertEqual(manager.microphoneStatus, .granted)
        XCTAssertEqual(manager.lastRefreshReason, .microphoneRequestCompletion)
        XCTAssertEqual(provider.microphoneRequestCount, 1)
    }

    func testNormalRefreshDoesNotPromptForAccessibility() {
        let provider = MockPermissionProvider()
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)

        manager.refresh(reason: .applicationLaunch)
        manager.refresh(reason: .applicationDidBecomeActive)
        manager.refresh(reason: .popoverWillOpen)
        manager.refresh(reason: .settingsReturn)

        XCTAssertEqual(provider.accessibilityPromptCount, 0)
    }

    func testExplicitAccessibilityRequestMayPrompt() {
        let provider = MockPermissionProvider()
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)

        _ = manager.requestAccessibilityIfNeeded()

        XCTAssertEqual(provider.accessibilityPromptCount, 1)
        XCTAssertEqual(manager.lastRefreshReason, .accessibilityRequest)
    }

    func testPermissionRefreshRunsOnMainActor() {
        let provider = MockPermissionProvider()
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)

        manager.refresh(reason: .manualRefresh)

        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(manager.lastRefreshReason, .manualRefresh)
    }

    // MARK: - 0.4.4b microphone recovery (B13–B15)

    func testB13_notDeterminedRequestIsIdempotent() async {
        let provider = MockPermissionProvider()
        provider.microphoneStatus = .notDetermined
        provider.microphoneRequestResult = true
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        XCTAssertEqual(manager.microphoneStatus, .notDetermined)

        // First request prompts.
        _ = await manager.requestMicrophone()
        XCTAssertEqual(provider.microphoneRequestCount, 1, "first request must prompt once")
        XCTAssertEqual(manager.microphoneStatus, .granted)

        // A second request while already determined must NOT re-prompt.
        _ = await manager.requestMicrophone()
        XCTAssertEqual(provider.microphoneRequestCount, 1, "a determined status must not re-trigger the prompt")
    }

    func testB14_deniedMicrophoneExposesSettingsRecoveryWithoutMutatingTCC() async {
        let provider = MockPermissionProvider()
        provider.microphoneStatus = .denied
        provider.microphoneRequestResult = false
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        // Already .denied → requestMicrophone() must not prompt (idempotence).
        _ = await manager.requestMicrophone()
        XCTAssertEqual(manager.microphoneStatus, .denied)

        // A product-callable recovery URL for the microphone privacy pane.
        let url = manager.microphoneSettingsURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(
            url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )

        // Opening settings mutates neither the permission nor the TCC prompt.
        manager.openMicrophoneSettings()
        XCTAssertEqual(manager.microphoneStatus, .denied, "opening Settings must not mutate permission state")
        XCTAssertEqual(provider.microphoneRequestCount, 0, "a denied status must not be prompted")
        XCTAssertEqual(provider.accessibilityPromptCount, 0, "microphone recovery must not touch Accessibility")
    }

    func testB15_refreshDoesNotInferGrantedFromDenied() {
        let provider = MockPermissionProvider()
        provider.microphoneStatus = .denied
        let manager = PermissionManager(provider: provider, recordsDiagnostics: false)
        XCTAssertEqual(manager.microphoneStatus, .denied)

        // A plain refresh must not invent a granted state.
        manager.refresh(reason: .applicationDidBecomeActive)
        XCTAssertEqual(manager.microphoneStatus, .denied)
        manager.refresh(reason: .popoverWillOpen)
        XCTAssertEqual(manager.microphoneStatus, .denied)
        XCTAssertEqual(provider.microphoneRequestCount, 0, "refresh must never prompt")
    }
}
