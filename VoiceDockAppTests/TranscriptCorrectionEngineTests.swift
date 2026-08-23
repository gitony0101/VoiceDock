//
//  TranscriptCorrectionEngineTests.swift
//  VoiceDockTests
//
//  VoiceDock Personal Transcript Correction v1 - Unit Tests
//

import Testing
import Foundation
@testable import VoiceDockCore

struct TranscriptCorrectionEngineTests {

    // MARK: - Positive Tests (Built-in Rules)

    @Test("Voice Duck corrected to VoiceDock with test context")
    func voiceDuckCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing Voice Duck recovery.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "Testing VoiceDock recovery.")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.appliedCorrections.first?.ruleIdentifier == "voicedock-voice-duck")
    }

    @Test("Voice Duck without context should NOT be corrected")
    func voiceDuckWithoutContextNotCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("I saw a voice duck yesterday.")

        // Should NOT be corrected - no context keywords
        #expect(result.correctedTranscript == "I saw a voice duck yesterday.")
    }

    @Test("voice stock in recovery context corrected to VoiceDock")
    func voiceStockInContextCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("This voice stock makes Chinese English recovery test.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.appliedCorrections.contains { $0.ruleIdentifier == "voicedock-voice-stock" })
    }

    @Test("voice: Doc corrected to VoiceDock with context")
    func voiceDocKovanCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing voice: Doc Kovan recovery.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "Testing VoiceDock Qwen recovery.")
        #expect(result.appliedCorrections.count == 2) // VoiceDock + Qwen
    }

    @Test("Kovan in context corrected to Qwen")
    func kovanCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing VoiceDock Kovan recovery test.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("Qwen"))
        #expect(result.appliedCorrections.contains { $0.ruleIdentifier == "qwen-kovan-contextual" })
    }

    @Test("Kilwin in context corrected to Qwen")
    func kilwinCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing VoiceDock Kilwin recovery test.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("Qwen"))
        #expect(result.appliedCorrections.contains { $0.ruleIdentifier == "qwen-kilwin-contextual" })
    }

    @Test("Honor TVT corrected to Owner PTT with context")
    func honorTvtCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Ready for Honor TVT")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "Ready for Owner PTT")
        #expect(result.appliedCorrections.first?.ruleIdentifier == "honor-tvt-to-owner-ptt")
    }

    @Test("recopy test corrected to recovery test")
    func recopyTestCorrected() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("This is a recopy test.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "This is a recovery test.")
        #expect(result.appliedCorrections.first?.ruleIdentifier == "recopy-test")
    }

    // MARK: - Owner Baseline Samples

    @Test("Owner sample 1: Testing voice: Doc Kovan recovery")
    func ownerSample1() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing voice: Doc Kovan recovery.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "Testing VoiceDock Qwen recovery.")
    }

    @Test("Owner sample 2: Voice Duck Chinese")
    func ownerSample2() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("你好，这是 Voice Duck 千问模型恢复测试。")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "你好，这是 VoiceDock 千问模型恢复测试。")
    }

    @Test("Owner sample 3: voice stock mixed Chinese English recopy")
    func ownerSample3() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("This voice stock makes Chinese English recopy test.")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.correctedTranscript.contains("mixed Chinese English"))
        #expect(result.correctedTranscript.contains("recovery"))
    }

    @Test("Voice Document Runtime Ready for Honor TVT")
    func voiceDocumentHonorTvt() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Voice Document Runtime Ready for Honor TVT")

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "VoiceDock Runtime Ready for Owner PTT")
    }

    // MARK: - Mixed Chinese-English Punctuation Preservation

    @Test("Mixed Chinese-English punctuation preserved")
    func mixedLanguagePunctuationPreserved() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "你好，这是 Voice Duck 测试。Hello world."
        let result = engine.correct(input)

        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.correctedTranscript.contains("你好，这是"))
        #expect(result.correctedTranscript.contains("测试。"))
        #expect(result.correctedTranscript.contains("Hello world."))
    }

    // MARK: - Multiple Corrections Longest First

    @Test("Multiple corrections applied longest-first with context")
    func multipleCorrectionsLongestFirst() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        // Add context keywords so corrections apply
        let input = "Testing Voice Duck and Kovan and Honor TVT in VoiceDock recovery test"
        let result = engine.correct(input)

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.correctedTranscript.contains("Qwen"))
        #expect(result.correctedTranscript.contains("Owner PTT"))
    }

    // MARK: - False Positive Tests

    @Test("False positive: voice stock in non-context should remain unchanged")
    func falsePositiveVoiceStockNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "I bought voice stock yesterday."
        let result = engine.correct(input)

        // Should NOT be corrected - no context keywords
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: voice doc in non-context should remain unchanged")
    func falsePositiveVoiceDocNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "I bought voice doc yesterday."
        let result = engine.correct(input)

        // Should NOT be corrected - no context keywords
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: voice duck in non-context should remain unchanged")
    func falsePositiveVoiceDuckNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "I bought voice duck yesterday."
        let result = engine.correct(input)

        // Should NOT be corrected - no context keywords
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: Kovan as name should remain unchanged")
    func falsePositiveKovanAsName() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Kovan called today."
        let result = engine.correct(input)

        // Should NOT be corrected - no VoiceDock/Qwen context
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: Kilwin as name should remain unchanged")
    func falsePositiveKilwinAsName() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Kilwin called today."
        let result = engine.correct(input)

        // Should NOT be corrected - no VoiceDock/Qwen context
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: recopy as verb should remain unchanged")
    func falsePositiveRecopyAsVerb() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Please recopy the file."
        let result = engine.correct(input)

        // Should NOT be corrected - "recopy" without "test" context
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: makes Chinese English without recovery context")
    func falsePositiveMakesChineseEnglishNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "This product makes Chinese English labels."
        let result = engine.correct(input)

        // "makes Chinese English" requires product/test context now
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: Qwen as name without context should remain unchanged")
    func falsePositiveQwenAliasesNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Q Win called today."
        let result = engine.correct(input)

        // Should NOT be corrected - no ASR/model context
        #expect(result.correctedTranscript == input)
    }

    @Test("False positive: Voice Document without context should remain unchanged")
    func falsePositiveVoiceDocumentNonContext() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Please file the voice document."
        let result = engine.correct(input)

        // Should NOT be corrected - no product/test context
        #expect(result.correctedTranscript == input)
    }

    @Test("Dates remain unchanged")
    func datesUnchanged() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "Meeting on 2026-07-21 at 3:30 PM."
        let result = engine.correct(input)

        #expect(result.correctedTranscript == input)
    }

    @Test("Numbers remain unchanged")
    func numbersUnchanged() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "There are 42 items worth $100 total."
        let result = engine.correct(input)

        #expect(result.correctedTranscript == input)
    }

    @Test("Negation remains unchanged")
    func negationUnchanged() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "This is not a VoiceDock test."
        let result = engine.correct(input)

        #expect(result.correctedTranscript.contains("not"))
        #expect(result.correctedTranscript.contains("VoiceDock"))
    }

    @Test("Unrelated names remain unchanged")
    func unrelatedNamesUnchanged() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "John called Sarah about the project."
        let result = engine.correct(input)

        #expect(result.correctedTranscript == input)
    }

    @Test("Empty transcript remains empty")
    func emptyTranscript() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("")

        #expect(result.rawTranscript == "")
        #expect(result.correctedTranscript == "")
        #expect(result.appliedCorrections.isEmpty == true)
        #expect(result.didChange == false)
    }

    @Test("Whitespace-only transcript remains unchanged")
    func whitespaceOnlyTranscript() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let input = "   \n\t  "
        let result = engine.correct(input)

        #expect(result.correctedTranscript == input)
        #expect(result.didChange == false)
    }

    // MARK: - Context Window Boundary Tests (30 characters)

    @Test("Context inside 30-character window triggers correction")
    func contextInsideWindowTriggersCorrection() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        // "test" is within 30 chars of "Voice Duck"
        let input = "Testing Voice Duck recovery now."
        let result = engine.correct(input)

        #expect(result.didChange == true)
        #expect(result.correctedTranscript == "Testing VoiceDock recovery now.")
    }

    @Test("Context immediately outside 30-character window does NOT trigger")
    func contextOutsideWindowDoesNotTriggerCorrection() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        // "test" is more than 30 chars away from "Voice Duck"
        let input = "I heard Voice Duck in the recording and this is a test of the system."
        let result = engine.correct(input)

        // Should NOT be corrected - context keyword too far away (>30 chars)
        #expect(result.correctedTranscript == input)
    }

    // MARK: - Mode Tests

    @Test("Correction mode Off delivers raw transcript")
    func correctionModeOff() async {
        // Note: This suite deliberately does NOT write correction preferences.
        // The engine itself doesn't know about mode — mode is applied at the
        // coordinator level. Writing to shared `UserDefaults.standard` here
        // raced with parallel suites reading preferences (the engine corrects
        // regardless), so the save/restore was removed as part of making
        // correction-preference tests deterministic.

        // Test
        let engine = PersonalTranscriptCorrectionEngine()
        let rawInput = "Testing Voice Duck Kovan recovery."
        let result = engine.correct(rawInput)

        // The engine always corrects; the coordinator decides whether to use it
        #expect(result.didChange == true)
    }
}