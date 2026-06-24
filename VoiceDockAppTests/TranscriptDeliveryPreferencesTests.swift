//
//  TranscriptDeliveryPreferencesTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

final class TranscriptDeliveryPreferencesTests: XCTestCase {
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Create isolated UserDefaults for testing
        testDefaults = UserDefaults(suiteName: "test.voicedock.preferences")
        XCTAssertNotNil(testDefaults, "Test UserDefaults suite should be created")

        // Clear any existing values
        testDefaults.removeObject(forKey: "voicedock.automaticPaste")
        testDefaults.removeObject(forKey: "voicedock.sendReturnAfterPaste")
    }

    override func tearDown() {
        // Clean up test defaults
        testDefaults.removeObject(forKey: "voicedock.automaticPaste")
        testDefaults.removeObject(forKey: "voicedock.sendReturnAfterPaste")
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultValuesMatchMigrationRequirements() {
        // Candidate 6 migration: automaticPaste=ON (matches C6), sendReturn=OFF (safer)
        let prefs = TranscriptDeliveryPreferences.load(from: testDefaults)

        XCTAssertTrue(prefs.automaticPaste, "Default automaticPaste should be ON for Candidate 6 migration")
        XCTAssertFalse(prefs.sendReturnAfterPaste, "Default sendReturnAfterPaste should be OFF for safety")
    }

    // MARK: - Persistence

    func testPreferencesPersistToUserDefaults() {
        let prefs = TranscriptDeliveryPreferences(automaticPaste: false, sendReturnAfterPaste: true)
        prefs.save(to: testDefaults)

        let loaded = TranscriptDeliveryPreferences.load(from: testDefaults)

        XCTAssertEqual(loaded.automaticPaste, false, "automaticPaste should persist")
        XCTAssertEqual(loaded.sendReturnAfterPaste, true, "sendReturnAfterPaste should persist")
    }

    func testMissingKeysUseDefaults() {
        // Ensure no keys are set
        testDefaults.removeObject(forKey: "voicedock.automaticPaste")
        testDefaults.removeObject(forKey: "voicedock.sendReturnAfterPaste")

        let loaded = TranscriptDeliveryPreferences.load(from: testDefaults)

        XCTAssertTrue(loaded.automaticPaste, "Missing automaticPaste should default to true")
        XCTAssertFalse(loaded.sendReturnAfterPaste, "Missing sendReturnAfterPaste should default to false")
    }

    // MARK: - Independent Mutations

    func testChangingAutomaticPasteDoesNotAffectSendReturn() {
        // Start with both false
        var prefs = TranscriptDeliveryPreferences(automaticPaste: false, sendReturnAfterPaste: false)
        prefs.save(to: testDefaults)

        // Change only automaticPaste
        prefs.automaticPaste = true
        prefs.save(to: testDefaults)

        let loaded = TranscriptDeliveryPreferences.load(from: testDefaults)

        XCTAssertTrue(loaded.automaticPaste, "automaticPaste should be updated")
        XCTAssertFalse(loaded.sendReturnAfterPaste, "sendReturnAfterPaste should remain unchanged")
    }

    func testChangingSendReturnDoesNotAffectAutomaticPaste() {
        // Start with known state
        var prefs = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: false)
        prefs.save(to: testDefaults)

        // Change only sendReturnAfterPaste
        prefs.sendReturnAfterPaste = true
        prefs.save(to: testDefaults)

        let loaded = TranscriptDeliveryPreferences.load(from: testDefaults)

        XCTAssertTrue(loaded.automaticPaste, "automaticPaste should remain unchanged")
        XCTAssertTrue(loaded.sendReturnAfterPaste, "sendReturnAfterPaste should be updated")
    }

    // MARK: - Equatable

    func testEquatableConformance() {
        let prefs1 = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: false)
        let prefs2 = TranscriptDeliveryPreferences(automaticPaste: true, sendReturnAfterPaste: false)
        let prefs3 = TranscriptDeliveryPreferences(automaticPaste: false, sendReturnAfterPaste: false)

        XCTAssertEqual(prefs1, prefs2, "Identical preferences should be equal")
        XCTAssertNotEqual(prefs1, prefs3, "Different preferences should not be equal")
    }
}