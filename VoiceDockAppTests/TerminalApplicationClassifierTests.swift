//
//  TerminalApplicationClassifierTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

final class TerminalApplicationClassifierTests: XCTestCase {

    // MARK: - Known Terminals

    func testAppleTerminalIsRecognized() {
        XCTAssertTrue(
            TerminalApplicationClassifier.isTerminal(bundleId: "com.apple.Terminal"),
            "Apple Terminal should be recognized"
        )
    }

    func testITerm2IsRecognized() {
        XCTAssertTrue(
            TerminalApplicationClassifier.isTerminal(bundleId: "com.googlecode.iterm2"),
            "iTerm2 should be recognized"
        )
    }

    func testWarpIsRecognized() {
        XCTAssertTrue(
            TerminalApplicationClassifier.isTerminal(bundleId: "dev.warp.Warp"),
            "Warp terminal should be recognized"
        )
    }

    // MARK: - Non-Terminals

    func testTextEditIsNotTerminal() {
        XCTAssertFalse(
            TerminalApplicationClassifier.isTerminal(bundleId: "com.apple.TextEdit"),
            "TextEdit should not be classified as terminal"
        )
    }

    func testXcodeIsNotTerminal() {
        XCTAssertFalse(
            TerminalApplicationClassifier.isTerminal(bundleId: "com.apple.dt.Xcode"),
            "Xcode should not be classified as terminal"
        )
    }

    func testNilBundleIdIsNotTerminal() {
        XCTAssertFalse(
            TerminalApplicationClassifier.isTerminal(bundleId: nil),
            "Nil bundle ID should not be classified as terminal"
        )
    }

    func testUnknownAppIsNotTerminal() {
        XCTAssertFalse(
            TerminalApplicationClassifier.isTerminal(bundleId: "com.example.unknown"),
            "Unknown bundle ID should not be classified as terminal"
        )
    }

    // MARK: - Known Terminals List

    func testAllKnownTerminalsContainsExpectedApps() {
        let terminals = TerminalApplicationClassifier.allKnownTerminals

        XCTAssertTrue(terminals.contains("com.apple.Terminal"), "Apple Terminal should be in list")
        XCTAssertTrue(terminals.contains("com.googlecode.iterm2"), "iTerm2 should be in list")
        XCTAssertTrue(terminals.contains("dev.warp.Warp"), "Warp should be in list")
    }

    func testAllKnownTerminalsIsSorted() {
        let terminals = TerminalApplicationClassifier.allKnownTerminals
        let sorted = terminals.sorted()

        XCTAssertEqual(terminals, sorted, "allKnownTerminals should be sorted")
    }

    // MARK: - Known Terminals Set

    func testKnownTerminalsSetContainsExpectedApps() {
        let knownTerminals = TerminalApplicationClassifier.knownTerminals

        XCTAssertTrue(knownTerminals.contains("com.apple.Terminal"))
        XCTAssertTrue(knownTerminals.contains("com.googlecode.iterm2"))
        XCTAssertTrue(knownTerminals.contains("dev.warp.Warp"))
    }
}