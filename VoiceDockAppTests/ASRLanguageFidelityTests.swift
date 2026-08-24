//
//  ASRLanguageFidelityTests.swift
//  VoiceDockTests
//
//  VoiceDock 0.2 RC1 - ASR Language-Fidelity Regression Tests
//
//  Guards the release-blocking invariant that spoken Chinese (and mixed
//  Chinese-English) speech is delivered in the language actually spoken.
//  The owner-observed defect was "我今天测试 VoiceDock。" being delivered as
//  "I am testing VoiceDock today." These tests make every layer of that
//  failure observable:
//
//  A. PersonalTranscriptCorrectionEngine cannot translate.
//  B. SessionCoordinator correction/delivery path cannot translate.
//  C. The Qwen3 generation boundary carries the transcription-fidelity
//     system context (removal of the instruction fails the suite).
//

import Testing
import Foundation
@testable import VoiceDockCore

struct ASRLanguageFidelityTests {

    // MARK: - A. Correction engine must not translate

    @Test("Correction must not translate pure Chinese input to English")
    func correctionDoesNotTranslateChinese() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let raw = "我今天测试 VoiceDock。"

        let result = await MainActor.run { engine.correct(raw) }

        #expect(result.correctedTranscript == raw,
                "Correction changed a Chinese transcript: '\(result.correctedTranscript)'")
        #expect(result.didChange == false)
        // Explicit regression: the English rewrite observed by the owner must
        // never be produced by any VoiceDock stage.
        #expect(result.correctedTranscript != "I am testing VoiceDock today.")
        // Chinese characters survive verbatim.
        #expect(result.correctedTranscript.contains("我今天测试"))
    }

    @Test("Correction preserves mixed-language structure")
    func correctionPreservesMixedLanguageStructure() async throws {
        let engine = PersonalTranscriptCorrectionEngine()
        let raw = "我现在测试 VoiceDock and replay buffer。"

        let result = await MainActor.run { engine.correct(raw) }

        // Both language segments remain present, each in its original language.
        #expect(result.correctedTranscript.contains("我现在测试"))
        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.correctedTranscript.contains("replay buffer"))
        // No full English rewrite appeared.
        #expect(!result.correctedTranscript.contains("I am now testing"))
    }

    // MARK: - B. Coordinator correction/delivery path must not translate

    @MainActor
    @Test("Coordinator applyCorrection does not translate Chinese transcript")
    func coordinatorApplyCorrectionDoesNotTranslate() async throws {
        let originalPrefs = TranscriptCorrectionPreferences.load()
        defer { originalPrefs.save() }
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        let raw = "我今天测试 VoiceDock。"
        let result = await coordinator.applyCorrection(rawTranscript: raw)

        #expect(result.correctedTranscript == raw,
                "Coordinator-level correction translated the transcript: '\(result.correctedTranscript)'")

        // Raw-transcript recovery remains intact after correction.
        #expect(coordinator.getLastRawTranscript() == raw)
    }

    @MainActor
    @Test("Coordinator mode Off delivers raw transcript unchanged for Chinese")
    func coordinatorModeOffPreservesChinese() async throws {
        let originalPrefs = TranscriptCorrectionPreferences.load()
        defer { originalPrefs.save() }
        TranscriptCorrectionPreferences(mode: .off, loadUserCorrections: false).save()

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        let raw = "我现在正式测试中文语音识别。"
        let result = await coordinator.applyCorrection(rawTranscript: raw)

        #expect(result.correctedTranscript == raw)
        #expect(result.didChange == false)
    }

    // MARK: - B2. End-to-end mock-transcript delivery must not translate

    /// Drives the full coordinator workflow with MockASRProvider returning a
    /// raw Chinese transcript, verifying the delivered transcript equals the
    /// raw ASR output. Uses no injected destination so delivery does not touch
    /// the shared pasteboard; `currentTranscript` is still published.
    @MainActor
    @Test("Mock Chinese transcript survives full coordinator workflow unchanged")
    func mockChineseTranscriptSurvivesFullWorkflow() async throws {
        let originalPrefs = TranscriptCorrectionPreferences.load()
        defer { originalPrefs.save() }
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        let mockASR = MockASRProvider()
        let rawTranscript = "我今天测试 VoiceDock。"
        await mockASR.setTranscribeResult(rawTranscript)

        let mockCapture = MockAudioCapture()
        var audio: [Float] = Array(repeating: 0, count: 16_000)
        for i in 0..<audio.count { audio[i] = sin(Float(i) / 5.0) * 0.3 }
        mockCapture.setFakeStopBuffer(audio)

        let coordinator = SessionCoordinator(
            audioCapture: mockCapture,
            asrProvider: mockASR,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Wait for model-load initialization to reach ready/idle before PTT.
        let initDeadline = Date().addingTimeInterval(10)
        while !(coordinator.state == .ready || coordinator.state == .idle),
              Date() < initDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(coordinator.startRecording())
        try await Task.sleep(nanoseconds: 75_000_000)
        coordinator.stopRecording()

        // Bounded poll until transcription + delivery complete (back to ready).
        let doneDeadline = Date().addingTimeInterval(10)
        while coordinator.state != .ready && Date() < doneDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(coordinator.state == .ready, "Workflow did not complete within 10s")

        let delivered = try #require(coordinator.currentTranscript)
        #expect(delivered == rawTranscript,
                "Delivered transcript was rewritten by the pipeline: '\(delivered)'")
        #expect(!delivered.contains("I am testing"),
                "Chinese speech was translated to English")

        let transcribeCalled = await mockASR.getTranscribeCalled()
        #expect(transcribeCalled)

        // Raw-transcript recovery remains intact through the live workflow.
        #expect(coordinator.getLastRawTranscript() == rawTranscript)
        #expect(coordinator.getLastCorrectedTranscript() == rawTranscript)
    }

    @MainActor
    @Test("Mock mixed-language transcript keeps both language segments")
    func mockMixedTranscriptKeepsBothSegments() async throws {
        let originalPrefs = TranscriptCorrectionPreferences.load()
        defer { originalPrefs.save() }
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        let mockASR = MockASRProvider()
        let rawTranscript = "我现在测试 VoiceDock and replay buffer。"
        await mockASR.setTranscribeResult(rawTranscript)

        let mockCapture = MockAudioCapture()
        var audio: [Float] = Array(repeating: 0, count: 16_000)
        for i in 0..<audio.count { audio[i] = sin(Float(i) / 5.0) * 0.3 }
        mockCapture.setFakeStopBuffer(audio)

        let coordinator = SessionCoordinator(
            audioCapture: mockCapture,
            asrProvider: mockASR,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        let initDeadline = Date().addingTimeInterval(10)
        while !(coordinator.state == .ready || coordinator.state == .idle),
              Date() < initDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(coordinator.startRecording())
        try await Task.sleep(nanoseconds: 75_000_000)
        coordinator.stopRecording()

        let doneDeadline = Date().addingTimeInterval(10)
        while coordinator.state != .ready && Date() < doneDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(coordinator.state == .ready, "Workflow did not complete within 10s")

        let delivered = try #require(coordinator.currentTranscript)
        // Mixed structure preserved: each segment in its original language.
        #expect(delivered.contains("我现在测试"))
        #expect(delivered.contains("VoiceDock"))
        #expect(delivered.contains("replay buffer"))
        #expect(!delivered.lowercased().contains("i am now testing"))
    }

    // MARK: - C. Qwen3 generation carries the fidelity contract

    @Test("Transcription fidelity context is non-empty and states the invariant")
    func fidelityContextStatesInvariant() {
        let context = qwen3ASRTranscriptionFidelityContext

        #expect(!context.isEmpty, "Fidelity context was removed or emptied")
        #expect(context.lowercased().contains("transcribe"),
                "Fidelity context no longer requests transcription")
        #expect(context.lowercased().contains("preserve"),
                "Fidelity context no longer requires preserving the spoken language")
        #expect(context.lowercased().contains("do not translate"),
                "Fidelity context no longer forbids translation")
        #expect(context.lowercased().contains("summarize") || context.lowercased().contains("rewrite"),
                "Fidelity context no longer forbids summarization/rewriting")
        #expect(context.lowercased().contains("mixed-language"),
                "Fidelity context no longer addresses mixed-language speech")
    }
}
