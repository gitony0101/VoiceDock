//
//  TranscriptDestinationTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
import AppKit
@testable import VoiceDockCore

final class TranscriptDestinationTests: XCTestCase {
    var sut: TranscriptDestination!

    override func setUp() {
        super.setUp()
        sut = TranscriptDestination()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testPasteCopiesTextToClipboard() {
        let testText = "Test transcription result"

        // Clear clipboard first
        NSPasteboard.general.clearContents()

        // Paste text
        sut.paste(text: testText, sendReturn: false)

        // Verify clipboard contents
        let clipboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(clipboardText, testText, "Clipboard should contain the test text")
    }

    func testPasteWithEmptyText() {
        // TranscriptDestination refuses empty text to avoid disrupting the target app.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sentinel", forType: .string)
        sut.paste(text: "", sendReturn: false)

        let clipboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(clipboardText, "sentinel", "Empty paste should leave clipboard untouched")
    }

    func testPostKeyDownCreatesValidEvents() {
        // This is a smoke test to ensure the method doesn't crash
        // Actual key event testing requires Accessibility permissions
        sut.paste(text: "test", sendReturn: true)
    }
}
