//
//  TranscriptCorrectionDefaultTests.swift
//  VoiceDock
//
//  VoiceDock 0.4.4c1 — Correction default (off-by-default) fallback tests.
//
//  Product target: Correction OFF by default on a clean install. These tests
//  pin the three CDEF behaviors from the 0.4.4c1 specification:
//
//    CDEF1  no saved key          → .off
//    CDEF2  saved .off            → .off
//    CDEF3  saved .personalCorrection → .personalCorrection
//
//  They exercise only the `load(from:)` fallback path (no persisted key) and
//  the preservation of explicitly saved values. Correction does NOT participate
//  in readiness, and no correction-engine rule/behavior is asserted here.
//

import Testing
import Foundation
@testable import VoiceDockCore

struct TranscriptCorrectionDefaultTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.voicedock.correctiondefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removeObject(forKey: "voicedock.transcriptCorrectionMode")
        defaults.removeObject(forKey: "voicedock.userCorrectionsFile")
        return defaults
    }

    // CDEF1: no saved key → off
    @Test("No saved correction key defaults to Off")
    func cdef1_noSavedKeyIsOff() {
        let defaults = makeDefaults()
        let prefs = TranscriptCorrectionPreferences.load(from: defaults)
        #expect(prefs.mode == .off)
    }

    // CDEF2: saved off → off
    @Test("Saved Off stays Off")
    func cdef2_savedOffIsOff() {
        let defaults = makeDefaults()
        TranscriptCorrectionPreferences(mode: .off, loadUserCorrections: false).save(to: defaults)
        let prefs = TranscriptCorrectionPreferences.load(from: defaults)
        #expect(prefs.mode == .off)
    }

    // CDEF3: saved personalCorrection → personalCorrection (explicit preference preserved)
    @Test("Saved PersonalCorrection is preserved")
    func cdef3_savedPersonalCorrectionIsPreserved() {
        let defaults = makeDefaults()
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save(to: defaults)
        let prefs = TranscriptCorrectionPreferences.load(from: defaults)
        #expect(prefs.mode == .personalCorrection)
    }

    // Companion: an explicitly saved value survives a round-trip and a
    // subsequent load does not drift back to Off.
    @Test("Explicit persisted mode does not migrate to Off")
    func explicitSavedModeDoesNotMigrate() {
        let defaults = makeDefaults()

        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: true).save(to: defaults)
        let first = TranscriptCorrectionPreferences.load(from: defaults)
        #expect(first.mode == .personalCorrection)
        #expect(first.loadUserCorrections == true)

        // A second load (fresh struct) still preserves the explicit value.
        let second = TranscriptCorrectionPreferences.load(from: defaults)
        #expect(second.mode == .personalCorrection)
    }
}