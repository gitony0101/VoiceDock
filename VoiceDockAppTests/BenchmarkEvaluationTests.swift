//
//  BenchmarkEvaluationTests.swift
//  VoiceDockTests
//
//  VoiceDock 0.3.4a - Raw-ASR evaluation harness unit coverage.
//
//  Deterministic tests only. These MUST NOT load Qwen production models.
//  Covers:
//    A. corpus-V0 manifest decoding
//    B. legacy smoke-manifest backward compatibility
//    C. Fixture default/fallback behavior
//    D..I. script-run extraction (pure en, pure zh, mixed)
//    J. punctuation/numbers create no script runs
//    K..M. WER scoring + normalization
//    N. mixed cases produce no WER
//    O. critical-token scoring independence from script fidelity
//    P. result serialization round-trip
//

import Testing
import Foundation
@testable import VoiceDockCore

struct BenchmarkEvaluationTests {

    // MARK: - A. V0 corpus manifest decoding

    @Test("V0 manifest decodes 12 fixtures")
    func v0ManifestDecodesTwelveFixtures() throws {
        let url = URL(fileURLWithPath: "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock-Stable-Identity-Accessibility-Fix/evaluation/corpus-v0/manifest.json")
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(BenchmarkManifest.self, from: data)

        #expect(manifest.fixtures.count == 12)

        let ids = manifest.fixtures.map { $0.id }
        #expect(ids.contains("V0-01"))
        #expect(ids.contains("V0-12"))

        // Case V0-05 (zh/en) carries expected script runs + critical tokens.
        let v0_05 = try #require(manifest.fixtures.first { $0.id == "V0-05" })
        #expect(v0_05.expectedScriptRuns == ["zh", "en"])
        #expect(v0_05.criticalTokens == ["VoiceDock", "replay buffer"])
        #expect(v0_05.audioFile == "V0-05.wav")
        #expect(v0_05.category == "mixed-zh-en")

        // Case V0-04 carries negation; V0-12 carries numeric.
        let v0_04 = try #require(manifest.fixtures.first { $0.id == "V0-04" })
        #expect(v0_04.negationPresent == true)
        #expect(v0_04.category == "pure-zh")

        let v0_12 = try #require(manifest.fixtures.first { $0.id == "V0-12" })
        #expect(v0_12.numericPresent == true)
        #expect(v0_12.category == "numeric-en")

        // Reference transcripts present for all.
        for f in manifest.fixtures {
            #expect(!f.reference.isEmpty)
        }
    }

    // MARK: - B. Legacy smoke-manifest backward compatibility

    @Test("Legacy smoke manifest still decodes")
    func legacySmokeManifestDecodes() throws {
        let json = """
        {
          "version": "1.0.0",
          "description": "smoke",
          "fixtures": [
            { "id": "smoke-01", "name": "Smoke Test 01", "language": "en",
              "reference": "VoiceDock push to talk test",
              "keywords": ["VoiceDock", "push"],
              "criticalTokens": ["VoiceDock"] }
          ],
          "scoring": { "normalizedTextAccuracy": 0, "technicalKeywordRecall": 0,
            "negationNumberLogicalPreservation": 0, "manualSemanticPreservation": 0,
            "inferenceSpeedRTF": 0, "loadWarmupPerformance": 0,
            "memoryEfficiency": 0, "total": 0 },
          "hardFailures": []
        }
        """
        let manifest = try JSONDecoder().decode(BenchmarkManifest.self, from: Data(json.utf8))
        let fixture = try #require(manifest.fixtures.first)

        #expect(fixture.id == "smoke-01")
        #expect(fixture.name == "Smoke Test 01")
        #expect(fixture.language == "en")
        #expect(fixture.reference == "VoiceDock push to talk test")
        #expect(fixture.keywords == ["VoiceDock", "push"])
        // criticalTokens (camel) maps to criticalTokens.
        #expect(fixture.criticalTokens == ["VoiceDock"])
        // No audio_file/expected_script_runs given -> defaults applied.
        #expect(fixture.audioFile == "smoke-01.wav")
        #expect(fixture.expectedScriptRuns == [])
        #expect(fixture.isPureEnglish == false)
    }

    @Test("Smoke manifest file decodes via Bundle-independent path")
    func smokeManifestFilePathDecodes() throws {
        let url = URL(fileURLWithPath: "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock-Stable-Identity-Accessibility-Fix/Benchmarks/VoiceDockASRBench/smoke-manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SkippedError()
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(BenchmarkManifest.self, from: data)
        #expect(manifest.fixtures.first?.id == "smoke-01")
    }

    struct SkippedError: Error, CustomStringConvertible {
        var description: String { "smoke manifest file not on disk" }
    }

    // MARK: - C. Fixture default/fallback behavior

    @Test("Fixture defaults apply for missing optional fields")
    func fixtureDefaults() throws {
        let json = """
        { "case_id": "X1", "reference_transcript": "hello world",
          "expected_script_runs": ["en"] }
        """
        let f = try JSONDecoder().decode(Fixture.self, from: Data(json.utf8))

        #expect(f.name == "X1")              // defaults to id
        #expect(f.language == "")
        #expect(f.keywords == [])
        #expect(f.criticalTokens == [])
        #expect(f.audioFile == "X1.wav")     // defaults to "<id>.wav"
        #expect(f.negationPresent == false)
        #expect(f.numericPresent == false)
        #expect(f.category == "")
        #expect(f.isPureEnglish == true)     // ["en"]
    }

    @Test("Fixture requires either case_id or id")
    func fixtureRequiresIdentifier() {
        let json = #"{ "reference_transcript": "missing id" }"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(Fixture.self, from: Data(json.utf8))
        }
    }

    @Test("isPureEnglish only true for exactly [\"en\"]")
    func isPureEnglishClassification() {
        #expect(Fixture(id: "a", reference: "x", expectedScriptRuns: ["en"]).isPureEnglish)
        #expect(!Fixture(id: "b", reference: "x", expectedScriptRuns: ["zh"]).isPureEnglish)
        #expect(!Fixture(id: "c", reference: "x", expectedScriptRuns: ["zh", "en"]).isPureEnglish)
        #expect(!Fixture(id: "d", reference: "x", expectedScriptRuns: ["en", "zh"]).isPureEnglish)
        #expect(!Fixture(id: "e", reference: "x", expectedScriptRuns: []).isPureEnglish)
    }

    // MARK: - D/E/F/G/H/I. Script-run extraction

    @Test("Pure English transcript -> [en]")
    func scriptRunsPureEnglish() {
        let runs = extractScriptRuns("I am testing VoiceDock speech recognition in English.")
        #expect(runs == ["en"])
    }

    @Test("Pure Chinese transcript -> [zh]")
    func scriptRunsPureChinese() {
        let runs = extractScriptRuns("我今天正在测试中文语音识别，希望系统保持我说话时使用的原始语言。")
        #expect(runs == ["zh"])
    }

    @Test("zh/en mixed -> [zh, en]")
    func scriptRunsZhEn() {
        let runs = extractScriptRuns("我现在测试 VoiceDock and replay buffer.")
        #expect(runs == ["zh", "en"])
    }

    @Test("en/zh mixed -> [en, zh]")
    func scriptRunsEnZh() {
        let runs = extractScriptRuns("Today I am testing VoiceDock 的中文语音识别。")
        #expect(runs == ["en", "zh"])
    }

    @Test("zh/en/zh mixed -> [zh, en, zh]")
    func scriptRunsZhEnZh() {
        let runs = extractScriptRuns("这个 actor critic 算法在模拟中表现很好。")
        #expect(runs == ["zh", "en", "zh"])
    }

    @Test("en/zh/en mixed -> [en, zh, en]")
    func scriptRunsEnZhEn() {
        let runs = extractScriptRuns("PPO is a popular 强化学习 algorithm.")
        #expect(runs == ["en", "zh", "en"])
    }

    // MARK: - J. punctuation / numbers create no script runs

    @Test("Numbers do not create script runs")
    func numbersAreNeutral() {
        #expect(extractScriptRuns("the number is 42 in english") == ["en"])
        #expect(extractScriptRuns("数量是 5000 个") == ["zh"])
    }

    @Test("Punctuation and whitespace do not create script runs")
    func punctuationIsNeutral() {
        #expect(extractScriptRuns("Hello, world!!!") == ["en"])
        #expect(extractScriptRuns("你好，世界！") == ["zh"])
        #expect(extractScriptRuns("   ").isEmpty)
        #expect(extractScriptRuns("").isEmpty)
    }

    // MARK: - Language fidelity

    @Test("Language fidelity exact match")
    func languageFidelity() {
        #expect(calculateLanguageFidelity(expected: ["zh", "en"], observed: ["zh", "en"]))
        #expect(!calculateLanguageFidelity(expected: ["zh", "en"], observed: ["zh"]))
        #expect(!calculateLanguageFidelity(expected: ["zh", "en"], observed: ["en", "zh"]))
        #expect(!calculateLanguageFidelity(expected: ["en"], observed: ["zh"]))
        #expect(!calculateLanguageFidelity(expected: ["zh"], observed: ["zh", "en"]))
    }

    // MARK: - K/L/M. WER

    @Test("WER exact match is 0")
    func werExactMatch() {
        let wer = calculateWordErrorRate(
            "I am testing VoiceDock speech recognition.",
            "I am testing VoiceDock speech recognition.",
            isPureEnglish: true)
        #expect(wer == 0)
    }

    @Test("WER is nil for non-pure-English cases")
    func werNilForNonEnglish() {
        let wer = calculateWordErrorRate(
            "我今天正在测试中文语音识别。",
            "我今天正在测试中文。",
            isPureEnglish: false)
        #expect(wer == nil)
    }

    @Test("WER word-level normalization (case, punctuation, whitespace)")
    func werNormalization() {
        // Apostrophe contraction is one word; punctuation stripped; case folded.
        let wer = calculateWordErrorRate(
            "I do not want the model to CAN'T translate it.",
            "i do not want the model to can't translate it",
            isPureEnglish: true)
        #expect(wer == 0)
    }

    @Test("WER single substitution scores 1/N")
    func werSubstitution() {
        let wer = calculateWordErrorRate(
            "hello world foo",
            "hello there foo",
            isPureEnglish: true)
        // 1 substitution out of 3 reference words.
        #expect(wer == 1.0 / 3.0)
    }

    @Test("WER deletion scored against reference length")
    func werDeletion() {
        let wer = calculateWordErrorRate(
            "hello world foo bar",
            "hello foo bar",
            isPureEnglish: true)
        // "world" deleted -> distance 1 / 4 reference words.
        #expect(wer == 0.25)
    }

    @Test("WER insertion scores against reference length")
    func werInsertion() {
        let wer = calculateWordErrorRate(
            "hello world",
            "hello big world",
            isPureEnglish: true)
        // "big" inserted -> distance 1 / 2 reference words.
        #expect(wer == 0.5)
    }

    @Test("WER returns 1.0 when reference non-empty and hypothesis empty")
    func werEmptyHypothesis() {
        let wer = calculateWordErrorRate("hello world", "", isPureEnglish: true)
        #expect(wer == 1.0)
    }

    @Test("WER returns 0 when both empty")
    func werBothEmpty() {
        let wer = calculateWordErrorRate("", "", isPureEnglish: true)
        #expect(wer == 0.0)
    }

    // MARK: - O. critical-token recall independent of script fidelity

    @Test("Critical token recall independent of script-run fidelity")
    func criticalTokenScoringIndependent() {
        // Transcript has correct script runs AND contains the critical token.
        let good = """
        Transcript: PPO is a popular 强化学习 algorithm.
        """
        let tokens = ["PPO"]

        // Same critical-token recall regardless of the surrounding script shape,
        // provided the token substring is present and the script runs match.
        let recallWithMatchingScript = calculateCriticalTokenRecall(
            reference: "PPO is a popular 强化学习 algorithm.",
            hypothesis: "PPO is a popular 强化学习 algorithm.",
            criticalTokens: tokens)
        #expect(recallWithMatchingScript == 1.0)

        // Script-fidelity and token-recall are computed via separate functions
        // and do not bleed into each other: a token miss is independent of
        // whether script runs match.
        let missRecall = calculateCriticalTokenRecall(
            reference: "PPO is a popular 强化学习 algorithm.",
            hypothesis: "A is a popular 强化学习 algorithm.",
            criticalTokens: ["PPO"])
        #expect(missRecall == 0.0)
    }

    // MARK: - P. result serialization round-trip

    @Test("BenchmarkResult encodes and decodes round-trip")
    func resultRoundTrip() throws {
        let original = BenchmarkResult(
            modelIdentifier: "qwen3-0.6b-8bit",
            fixtureIdentifier: "V0-05",
            audioDuration: 3.2,
            sampleCount: 51200,
            waveformRMS: 0.1,
            modelLoadTime: 1.0,
            warmupTime: 0.5,
            inferenceTime: 2.1,
            realTimeFactor: 0.65625,
            processMemoryBeforeLoad: nil,
            processMemoryAfterLoad: nil,
            peakMemory: nil,
            transcript: "我现在测试 VoiceDock and replay buffer.",
            normalizedCharacterErrorRate: 0.12,
            wordErrorRate: nil,               // mixed case -> nil WER
            keywordRecall: 0.0,
            criticalTokenRecall: 1.0,
            negationPreserved: false,
            expectedScriptRuns: ["zh", "en"],
            observedScriptRuns: ["zh", "en"],
            languageFidelity: true,
            timestamp: "2026-08-26T00:00:00Z")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: data)

        #expect(decoded.modelIdentifier == original.modelIdentifier)
        #expect(decoded.fixtureIdentifier == "V0-05")
        #expect(decoded.wordErrorRate == nil)
        #expect(decoded.expectedScriptRuns == ["zh", "en"])
        #expect(decoded.observedScriptRuns == ["zh", "en"])
        #expect(decoded.languageFidelity == true)
        #expect(decoded.criticalTokenRecall == 1.0)
        #expect(decoded.negationPreserved == false)
        #expect(decoded.transcript == original.transcript)
    }

    @Test("BenchmarkReport (schema container) round-trips")
    func reportRoundTrip() throws {
        let result = BenchmarkResult(
            modelIdentifier: "qwen3-0.6b-8bit",
            fixtureIdentifier: "V0-01",
            audioDuration: 2.0,
            sampleCount: 32000,
            waveformRMS: 0.05,
            modelLoadTime: 1.0,
            warmupTime: 0.4,
            inferenceTime: 1.5,
            realTimeFactor: 0.75,
            processMemoryBeforeLoad: nil,
            processMemoryAfterLoad: nil,
            peakMemory: nil,
            transcript: "I am testing VoiceDock speech recognition in English.",
            normalizedCharacterErrorRate: 0.0,
            wordErrorRate: 0.0,
            keywordRecall: 0.0,
            criticalTokenRecall: 1.0,
            negationPreserved: false,
            expectedScriptRuns: ["en"],
            observedScriptRuns: ["en"],
            languageFidelity: true,
            timestamp: "2026-08-26T00:00:00Z")

        let report = BenchmarkReport(
            modelIdentifier: "qwen3-0.6b-8bit",
            modelDisplayName: "Qwen3 0.6B 8-bit",
            totalFixtures: 12,
            completedFixtures: 1,
            failedFixtures: 0,
            avgInferenceTime: 1.5,
            avgRealTimeFactor: 0.75,
            totalMemoryDelta: nil,
            avgCharacterErrorRate: 0.0,
            avgKeywordRecall: 0.0,
            avgCriticalTokenRecall: 1.0,
            results: [result],
            runTimestamp: "2026-08-26T00:00:00Z",
            runDuration: 3.0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        #expect(decoded.totalFixtures == 12)
        #expect(decoded.completedFixtures == 1)
        #expect(decoded.results.count == 1)
        #expect(decoded.results[0].fixtureIdentifier == "V0-01")
        #expect(decoded.results[0].wordErrorRate == 0.0)
        #expect(decoded.results[0].observedScriptRuns == ["en"])
        #expect(decoded.results[0].languageFidelity == true)
    }
}