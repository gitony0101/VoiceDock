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
}
