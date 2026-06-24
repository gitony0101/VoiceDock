//
//  TranscriptDeliveryPolicyTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class TranscriptDeliveryPolicyTests: XCTestCase {

    // MARK: - Copy to Clipboard (Automatic Paste OFF)

    func testAutomaticPasteOffResultsInCopyToClipboard() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: false, sendReturnAfterPaste: false)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.apple.TextEdit")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        XCTAssertEqual(decision, .copyToClipboard, "When automaticPaste is OFF, should copy to clipboard")
    }

    func testAutomaticPasteOffIgnoresSendReturnSetting() {
        // Even if sendReturn is ON, automaticPaste=OFF should win
        let preferences = TranscriptDeliveryPreferences(automaticPaste: false, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.apple.TextEdit")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        XCTAssertEqual(decision, .copyToClipboard, "automaticPaste=OFF should override sendReturn=ON")
    }

    // MARK: - Paste Without Return (Automatic Paste ON, Return OFF)

    func testAutomaticPasteOnWithReturnOffResultsInPasteOnly() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: false)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.apple.TextEdit")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        XCTAssertEqual(decision, .pasteTranscript, "Should paste without Return when Return is OFF")
    }

    // MARK: - Paste With Return (Both ON, Non-Terminal)

    func testBothOnInNonTerminalResultsInPasteAndReturn() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.apple.TextEdit")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        XCTAssertEqual(decision, .pasteAndSendReturn, "Should paste and send Return in non-terminal")
    }

    func testBothOnInUnknownAppResultsInPasteAndReturn() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: nil)
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        XCTAssertEqual(decision, .pasteAndSendReturn, "Should paste and send Return when app is unknown")
    }

    // MARK: - Terminal Safety (Both ON, Terminal App)

    func testBothOnInAppleTerminalResultsInReturnSuppression() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.apple.Terminal")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        if case .pasteWithReturnSuppressed(let reason) = decision {
            XCTAssertTrue(reason.contains("terminal"), "Reason should mention terminal")
            XCTAssertTrue(reason.contains("com.apple.Terminal"), "Reason should include bundle ID")
        } else {
            XCTFail("Expected pasteWithReturnSuppressed, got \(decision)")
        }
    }

    func testBothOnInITerm2ResultsInReturnSuppression() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: "com.googlecode.iterm2")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        if case .pasteWithReturnSuppressed(let reason) = decision {
            XCTAssertTrue(reason.contains("terminal"), "Reason should mention terminal")
        } else {
            XCTFail("Expected pasteWithReturnSuppressed, got \(decision)")
        }
    }

    func testBothOnInWarpResultsInReturnSuppression() {
        let preferences = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: true)
        let appProvider = MockFrontmostAppProvider(bundleId: "dev.warp.Warp")
        let policy = TranscriptDeliveryPolicy(preferences: preferences, appProvider: appProvider)

        let decision = policy.determineDelivery()

        if case .pasteWithReturnSuppressed(let reason) = decision {
            XCTAssertTrue(reason.contains("terminal"), "Reason should mention terminal")
        } else {
            XCTFail("Expected pasteWithReturnSuppressed, got \(decision)")
        }
    }

    // MARK: - Decision Equatable

    func testDecisionEquatable() {
        let decision1: TranscriptDeliveryDecision = .copyToClipboard
        let decision2: TranscriptDeliveryDecision = .copyToClipboard
        let decision3: TranscriptDeliveryDecision = .pasteTranscript

        XCTAssertEqual(decision1, decision2, "Identical decisions should be equal")
        XCTAssertNotEqual(decision1, decision3, "Different decisions should not be equal")
    }

    func testSuppressedReasonsAreCompared() {
        let decision1: TranscriptDeliveryDecision = .pasteWithReturnSuppressed(reason: "test")
        let decision2: TranscriptDeliveryDecision = .pasteWithReturnSuppressed(reason: "test")
        let decision3: TranscriptDeliveryDecision = .pasteWithReturnSuppressed(reason: "different")

        XCTAssertEqual(decision1, decision2, "Same reasons should be equal")
        XCTAssertNotEqual(decision1, decision3, "Different reasons should not be equal")
    }
}