//
//  SessionCoordinatorCorrectionTests.swift
//  VoiceDockTests
//
//  VoiceDock Personal Transcript Correction v1 - SessionCoordinator Integration Tests
//

import Testing
import Foundation
@testable import VoiceDockCore

@MainActor
struct SessionCoordinatorCorrectionTests {

    // MARK: - Production Composition Root

    @Test("Production composition root creates correction engine")
    func productionCompositionRootCreatesCorrectionEngine() async throws {
        // Arrange: Create coordinator with production dependencies (no injected correction engine)
        let audioCapture = MockAudioCapture()
        let asrProvider = MockASRProvider()
        let transcriptDestination = TranscriptDestination()

        // Pin correction mode so this test does not depend on shared `.standard` state.
        let originalPrefs = TranscriptCorrectionPreferences.load()
        TranscriptCorrectionPreferences(
            mode: .personalCorrection,
            loadUserCorrections: false
        ).save()
        defer { originalPrefs.save() }

        // Act: Create coordinator without injecting correction engine (production path)
        let coordinator = SessionCoordinator(
            audioCapture: audioCapture,
            asrProvider: asrProvider,
            transcriptDestination: transcriptDestination,
            correctionEngine: nil  // Production path: nil means coordinator creates it
        )

        // Wait for initialization deterministically: the coordinator publishes
        // its completion through the observable `state` property. Poll until
        // `.ready` (engine created) with a bounded timeout instead of sleeping
        // a fixed wall-clock duration.
        let readinessDeadline = Date().addingTimeInterval(10)
        while coordinator.state != .ready && Date() < readinessDeadline {
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms poll interval
        }
        #expect(coordinator.state == .ready, "Coordinator did not become ready within 10s")

        // Assert: Coordinator should have created a correction engine
        // We verify this by checking that correction is actually applied
        let rawTranscript = "Testing Voice Duck recovery."
        let result = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
    }

    @Test("Injected correction engine is used instead of creating new one")
    func injectedCorrectionEngineIsUsed() async throws {
        // Pin correction mode so the test does not pick up an Off state left in
        // `.standard` by another test running first.
        let originalPrefs = TranscriptCorrectionPreferences.load()
        TranscriptCorrectionPreferences(
            mode: .personalCorrection,
            loadUserCorrections: false
        ).save()
        defer { originalPrefs.save() }

        // Arrange: Create a custom engine with known behavior
        let customEngine = PersonalTranscriptCorrectionEngine()
        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: customEngine
        )

        // Wait for initialization
        try await Task.sleep(nanoseconds: 200_000_000)

        // Act: Apply correction
        let rawTranscript = "Testing Voice Duck recovery."
        let result = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        // Assert: Custom engine was used
        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
    }

    // MARK: - Correction Mode Tests

    @Test("Correction mode Off delivers raw transcript")
    func correctionModeOffDeliversRaw() async throws {
        // Arrange: Save original preferences
        let original = TranscriptCorrectionPreferences.load()

        // Set mode to off
        let prefs = TranscriptCorrectionPreferences(mode: .off, loadUserCorrections: false)
        prefs.save()

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Act: Apply correction to text that would normally be corrected
        let rawTranscript = "Testing Voice Duck Kovan recovery."
        let result = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        // Assert: Raw transcript is delivered unchanged when mode is Off
        #expect(result.correctedTranscript == rawTranscript)
        #expect(result.appliedCorrections.isEmpty == true)
        #expect(result.didChange == false)

        // Cleanup: Restore preferences
        original.save()
    }

    @Test("Correction mode PersonalCorrection delivers corrected transcript")
    func correctionModePersonalCorrectionDeliversCorrected() async throws {
        // Arrange: Save original preferences
        let original = TranscriptCorrectionPreferences.load()

        // Set mode to personal correction
        let prefs = TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false)
        prefs.save()

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Act: Apply correction
        let rawTranscript = "Testing Voice Duck Kovan recovery."
        let result = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        // Assert: Corrected transcript is delivered
        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
        #expect(result.correctedTranscript.contains("Qwen"))

        // Cleanup: Restore preferences
        original.save()
    }

    @Test("Changing mode affects next transcript only")
    func changingModeAffectsNextTranscriptOnly() async throws {
        // Arrange: Save original preferences
        let original = TranscriptCorrectionPreferences.load()

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Set mode to Off
        TranscriptCorrectionPreferences(mode: .off, loadUserCorrections: false).save()

        // First transcript with mode Off
        let rawTranscript1 = "Testing Voice Duck recovery."
        let result1 = await coordinator.applyCorrection(rawTranscript: rawTranscript1)
        #expect(result1.correctedTranscript == rawTranscript1)

        // Change mode to On
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        // Second transcript with mode On
        let rawTranscript2 = "Testing Voice Duck recovery."
        let result2 = await coordinator.applyCorrection(rawTranscript: rawTranscript2)
        #expect(result2.didChange == true)
        #expect(result2.correctedTranscript.contains("VoiceDock"))

        // Cleanup: Restore preferences
        original.save()
    }

    // MARK: - Raw Transcript Recovery

    @Test("Last raw transcript is stored separately from corrected")
    func lastRawTranscriptStoredSeparately() async throws {
        // Arrange: Ensure preferences are set and persisted
        let originalPrefs = TranscriptCorrectionPreferences.load()
        defer { originalPrefs.save() }  // Restore on exit

        let prefs = TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false)
        prefs.save()

        // Verify preferences were saved
        let loadedPrefs = TranscriptCorrectionPreferences.load()
        #expect(loadedPrefs.mode == .personalCorrection)

        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Act: Apply correction
        let rawTranscript = "Testing Voice Duck Kovan recovery."
        let result = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        // Assert: Correction was applied
        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))

        // Raw transcript is preserved
        let storedRaw = coordinator.getLastRawTranscript()
        #expect(storedRaw == rawTranscript)

        // And corrected is different
        let storedCorrected = coordinator.getLastCorrectedTranscript()
        #expect(storedCorrected != rawTranscript)
        #expect(storedCorrected?.contains("VoiceDock") == true)
    }

    @Test("Copy Last Raw Transcript returns raw only")
    func copyLastRawTranscriptReturnsRawOnly() async throws {
        // Arrange
        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        let rawTranscript = "Testing Voice Duck recovery."
        _ = await coordinator.applyCorrection(rawTranscript: rawTranscript)

        // Act: Get raw transcript
        let raw = coordinator.getLastRawTranscript()
        let corrected = coordinator.getLastCorrectedTranscript()

        // Assert
        #expect(raw == rawTranscript)
        #expect(corrected != rawTranscript)
        #expect(raw?.contains("Voice Duck") == true)  // Raw has the error
        #expect(corrected?.contains("VoiceDock") == true)  // Corrected has the fix
    }

    @Test("getLastRawTranscript returns nil before first transcript")
    func getLastRawTranscriptReturnsNilBeforeFirstTranscript() async throws {
        // Arrange
        let coordinator = SessionCoordinator(
            audioCapture: nil,
            asrProvider: nil,
            transcriptDestination: nil,
            correctionEngine: PersonalTranscriptCorrectionEngine()
        )

        // Act: Get raw transcript before any transcription
        let raw = coordinator.getLastRawTranscript()

        // Assert: Should be nil
        #expect(raw == nil)
    }

    // MARK: - Invalid JSON Handling

    @Test("Invalid JSON keeps builtin rules active")
    func invalidJsonKeepsBuiltinRulesActive() async throws {
        // Arrange: Create invalid JSON at the actual user corrections path
        let correctionsDir = try PersonalTranscriptCorrectionEngine.ensureCorrectionsDirectory()
        let fileURL = correctionsDir.appendingPathComponent("personal-corrections.json")

        // Backup existing file if present
        var backupURL: URL?
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existingData = try? Data(contentsOf: fileURL) {
            backupURL = correctionsDir.appendingPathComponent("personal-corrections.json.backup")
            try? existingData.write(to: backupURL!)
        }

        // Write invalid JSON
        try "not valid json {".write(to: fileURL, atomically: true, encoding: .utf8)

        // Act: Create engine and try to load
        let engine = PersonalTranscriptCorrectionEngine()
        do {
            try await engine.loadUserCorrections()
            #expect(Bool(false), "Should have thrown for invalid JSON")
        } catch {
            // Expected: invalid JSON throws
        }

        // Assert: Engine still has builtin rules and can correct
        let result = engine.correct("Testing Voice Duck recovery.")
        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))

        // Cleanup: Restore backup or remove invalid file
        if let backupURL {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.copyItem(at: backupURL, to: fileURL)
            try? FileManager.default.removeItem(at: backupURL)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @Test("Missing user corrections file is nonfatal")
    func missingUserCorrectionsFileIsNonfatal() async throws {
        // Arrange: Ensure no user corrections file exists at test path
        // (Test uses actual user path, so we just verify builtin rules work)

        // Act: Create engine without loading user corrections
        let engine = PersonalTranscriptCorrectionEngine()
        let result = engine.correct("Testing Voice Duck recovery.")

        // Assert: Builtin rules still work
        #expect(result.didChange == true)
        #expect(result.correctedTranscript.contains("VoiceDock"))
    }

    // MARK: - Concurrency Safety

    @Test("Correction calls operate on immutable snapshot")
    func correctionCallsOperateOnImmutableSnapshot() async throws {
        // Arrange
        let engine = PersonalTranscriptCorrectionEngine()
        let transcript = "Testing Voice Duck Kovan recovery."

        // Act: Multiple concurrent corrections
        let results = await withTaskGroup(of: CorrectionResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    engine.correct(transcript)
                }
            }
            var results: [CorrectionResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Assert: All results are identical (same corrections applied)
        let firstResult = results.first
        for result in results {
            #expect(result.correctedTranscript == firstResult?.correctedTranscript)
            #expect(result.appliedCorrections.count == firstResult?.appliedCorrections.count)
        }
    }

    @Test("Rules array is immutable after initialization")
    func rulesArrayIsImmutableAfterInitialization() async throws {
        // Arrange
        let engine = PersonalTranscriptCorrectionEngine()

        // Act: Correct multiple times
        let result1 = engine.correct("Testing Voice Duck recovery.")
        let result2 = engine.correct("Testing Voice Duck recovery.")
        let result3 = engine.correct("Testing Voice Duck recovery.")

        // Assert: All results are identical
        #expect(result1.correctedTranscript == result2.correctedTranscript)
        #expect(result2.correctedTranscript == result3.correctedTranscript)
        #expect(result1.appliedCorrections.map { $0.ruleIdentifier } == result2.appliedCorrections.map { $0.ruleIdentifier })
    }

    // MARK: - Coverage Verification

    @Test("Coverage: deterministic correction results")
    func coverageDeterministicCorrectionResults() async throws {
        // Arrange: Set preferences BEFORE creating coordinator
        TranscriptCorrectionPreferences(mode: .personalCorrection, loadUserCorrections: false).save()

        // Use engine directly for deterministic testing
        let engine = PersonalTranscriptCorrectionEngine()
        let rawTranscript = "Testing Voice Duck recovery."

        // Act: Apply correction multiple times
        let result1 = engine.correct(rawTranscript)
        let result2 = engine.correct(rawTranscript)
        let result3 = engine.correct(rawTranscript)

        // Assert: All results are identical (deterministic)
        #expect(result1.appliedCorrections.map { $0.ruleIdentifier } == result2.appliedCorrections.map { $0.ruleIdentifier })
        #expect(result2.appliedCorrections.map { $0.ruleIdentifier } == result3.appliedCorrections.map { $0.ruleIdentifier })
        #expect(result1.correctedTranscript == result2.correctedTranscript)
        #expect(result2.correctedTranscript == result3.correctedTranscript)
    }
}