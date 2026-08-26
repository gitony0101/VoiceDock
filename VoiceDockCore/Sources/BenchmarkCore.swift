//
//  BenchmarkCore.swift
//  VoiceDockCore
//
//  Shared benchmark logic for VoiceDock ASR model comparison
//

import Foundation
import AVFoundation

// MARK: - Benchmark Path Resolution

/// Resolves benchmark paths using Application Support directory by default.
/// Environment variables can override canonical defaults.
public enum BenchmarkPaths {
    /// Base directory: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel
    /// Can be overridden via VOICEDOCK_BENCHMARK_BASE environment variable.
    public static func baseDirectory() throws -> URL {
        // Check for environment variable override first
        if let baseEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_BASE"] {
            return URL(fileURLWithPath: NSString(string: baseEnv).expandingTildeInPath)
        }

        // Default to Application Support directory
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportURL
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("QwenDuel", isDirectory: true)
    }

    /// Default fixtures directory.
    /// Can be overridden via VOICEDOCK_BENCHMARK_FIXTURES environment variable.
    public static func fixturesDirectory() throws -> URL {
        if let fixturesEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_FIXTURES"] {
            return URL(fileURLWithPath: NSString(string: fixturesEnv).expandingTildeInPath)
        }
        return try baseDirectory().appendingPathComponent("fixtures", isDirectory: true)
    }

    /// Default manifest path.
    /// Can be overridden via VOICEDOCK_BENCHMARK_MANIFEST environment variable.
    public static func manifestPath() throws -> String {
        if let manifestEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_MANIFEST"] {
            return NSString(string: manifestEnv).expandingTildeInPath
        }
        return try baseDirectory()
            .appendingPathComponent("manifest.json", isDirectory: false)
            .path
    }

    /// Default output directory for results.
    /// Can be overridden via VOICEDOCK_BENCHMARK_OUTPUT environment variable.
    public static func outputDirectory() throws -> URL {
        if let outputEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_OUTPUT"] {
            let url = URL(fileURLWithPath: NSString(string: outputEnv).expandingTildeInPath)
            return url.deletingLastPathComponent()
        }
        return try baseDirectory()
            .appendingPathComponent("results", isDirectory: true)
    }

    /// Resolve output path for a specific model.
    public static func outputPath(for modelID: String) throws -> String {
        if let outputEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_OUTPUT"] {
            return NSString(string: outputEnv).expandingTildeInPath
        }
        return try outputDirectory()
            .appendingPathComponent("\(modelID).json", isDirectory: false)
            .path
    }

    /// Optional JSONL output path for per-result streaming.
    /// Controlled by VOICEDOCK_BENCHMARK_JSONL_OUTPUT environment variable.
    /// If set, each BenchmarkResult is written as one JSON line during the run.
    public static func jsonlOutputPath(for modelID: String) throws -> String? {
        if let jsonlEnv = ProcessInfo.processInfo.environment["VOICEDOCK_BENCHMARK_JSONL_OUTPUT"] {
            return NSString(string: jsonlEnv).expandingTildeInPath
        }
        return nil
    }
}

// MARK: - Benchmark Result Types

public struct BenchmarkResult: Codable {
    public let modelIdentifier: String
    public let fixtureIdentifier: String
    public let audioDuration: Double?
    public let sampleCount: Int
    public let waveformRMS: Double?
    public let modelLoadTime: Double
    public let warmupTime: Double
    public let inferenceTime: Double
    public let realTimeFactor: Double?
    public let processMemoryBeforeLoad: Int64?
    public let processMemoryAfterLoad: Int64?
    public let peakMemory: Int64?
    public let transcript: String
    public let normalizedCharacterErrorRate: Double?
    /// Word Error Rate - only for pure English cases (expectedScriptRuns == ["en"])
    /// Per 0.3.4a §7: nil for mixed/Chinese cases
    public let wordErrorRate: Double?
    public let keywordRecall: Double?
    public let criticalTokenRecall: Double?
    public let negationPreserved: Bool?
    /// Expected script-run sequence from manifest (e.g. ["zh","en","zh"])
    public let expectedScriptRuns: [String]
    /// Observed script-run sequence from transcript
    public let observedScriptRuns: [String]
    /// Language fidelity: true iff observed exactly matches expected
    public let languageFidelity: Bool
    public let timestamp: String

    public init(
        modelIdentifier: String,
        fixtureIdentifier: String,
        audioDuration: Double?,
        sampleCount: Int,
        waveformRMS: Double?,
        modelLoadTime: Double,
        warmupTime: Double,
        inferenceTime: Double,
        realTimeFactor: Double?,
        processMemoryBeforeLoad: Int64?,
        processMemoryAfterLoad: Int64?,
        peakMemory: Int64?,
        transcript: String,
        normalizedCharacterErrorRate: Double?,
        wordErrorRate: Double?,
        keywordRecall: Double?,
        criticalTokenRecall: Double?,
        negationPreserved: Bool?,
        expectedScriptRuns: [String],
        observedScriptRuns: [String],
        languageFidelity: Bool,
        timestamp: String
    ) {
        self.modelIdentifier = modelIdentifier
        self.fixtureIdentifier = fixtureIdentifier
        self.audioDuration = audioDuration
        self.sampleCount = sampleCount
        self.waveformRMS = waveformRMS
        self.modelLoadTime = modelLoadTime
        self.warmupTime = warmupTime
        self.inferenceTime = inferenceTime
        self.realTimeFactor = realTimeFactor
        self.processMemoryBeforeLoad = processMemoryBeforeLoad
        self.processMemoryAfterLoad = processMemoryAfterLoad
        self.peakMemory = peakMemory
        self.transcript = transcript
        self.normalizedCharacterErrorRate = normalizedCharacterErrorRate
        self.wordErrorRate = wordErrorRate
        self.keywordRecall = keywordRecall
        self.criticalTokenRecall = criticalTokenRecall
        self.negationPreserved = negationPreserved
        self.expectedScriptRuns = expectedScriptRuns
        self.observedScriptRuns = observedScriptRuns
        self.languageFidelity = languageFidelity
        self.timestamp = timestamp
    }
}

public struct BenchmarkReport: Codable {
    public let modelIdentifier: String
    public let modelDisplayName: String
    public let totalFixtures: Int
    public let completedFixtures: Int
    public let failedFixtures: Int
    public let avgInferenceTime: Double
    public let avgRealTimeFactor: Double?
    public let totalMemoryDelta: Int64?
    public let avgCharacterErrorRate: Double?
    public let avgKeywordRecall: Double?
    public let avgCriticalTokenRecall: Double?
    public let results: [BenchmarkResult]
    public let runTimestamp: String
    public let runDuration: Double

    public init(
        modelIdentifier: String,
        modelDisplayName: String,
        totalFixtures: Int,
        completedFixtures: Int,
        failedFixtures: Int,
        avgInferenceTime: Double,
        avgRealTimeFactor: Double?,
        totalMemoryDelta: Int64?,
        avgCharacterErrorRate: Double?,
        avgKeywordRecall: Double?,
        avgCriticalTokenRecall: Double?,
        results: [BenchmarkResult],
        runTimestamp: String,
        runDuration: Double
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
        self.totalFixtures = totalFixtures
        self.completedFixtures = completedFixtures
        self.failedFixtures = failedFixtures
        self.avgInferenceTime = avgInferenceTime
        self.avgRealTimeFactor = avgRealTimeFactor
        self.totalMemoryDelta = totalMemoryDelta
        self.avgCharacterErrorRate = avgCharacterErrorRate
        self.avgKeywordRecall = avgKeywordRecall
        self.avgCriticalTokenRecall = avgCriticalTokenRecall
        self.results = results
        self.runTimestamp = runTimestamp
        self.runDuration = runDuration
    }
}

// MARK: - Manifest Types

public struct BenchmarkManifest: Codable {
    public let version: String
    public let description: String
    public let fixtures: [Fixture]
    public let scoring: Scoring
    public let hardFailures: [String]

    public init(version: String, description: String, fixtures: [Fixture], scoring: Scoring, hardFailures: [String]) {
        self.version = version
        self.description = description
        self.fixtures = fixtures
        self.scoring = scoring
        self.hardFailures = hardFailures
    }
}

/// One evaluation case.
///
/// 0.3.4a: the corpus-V0 schema (`case_id` / `reference_transcript` /
/// `audio_file` / `expected_script_runs` / `critical_tokens` /
/// `negation_present` / `numeric_present` / `category`) is decoded alongside
/// the legacy smoke-manifest schema (`id` / `reference` / `keywords` /
/// `criticalTokens` / `name` / `language`). Both shapes decode into this one
/// type, so the existing smoke manifest keeps working unchanged.
public struct Fixture: Codable {
    /// Stable case identifier. Decoded from `case_id`, falling back to `id`.
    public let id: String
    /// Human-readable name. Defaults to `id` when absent.
    public let name: String
    /// Legacy free-form language tag ("en"/"zh"/"mixed"). Defaults to "".
    public let language: String
    /// Reference transcript. Decoded from `reference_transcript`, falling back
    /// to `reference`.
    public let reference: String
    /// Legacy soft keyword list (substring recall). Defaults to [].
    public let keywords: [String]
    /// Tokens whose exact preservation is scored. Decoded from
    /// `critical_tokens`, falling back to `criticalTokens`. Defaults to [].
    public let criticalTokens: [String]
    /// Relative WAV filename inside the fixtures directory. Defaults to
    /// "<id>.wav" so the legacy smoke manifest resolves as before.
    public let audioFile: String
    /// Expected script-run sequence (e.g. ["zh","en","zh"]). Empty means the
    /// case does not participate in script-run fidelity scoring.
    public let expectedScriptRuns: [String]
    /// True when the reference contains a negation that must survive.
    public let negationPresent: Bool
    /// True when the reference contains numerics that must survive.
    public let numericPresent: Bool
    /// Coarse corpus category. Defaults to "".
    public let category: String

    /// True only for cases whose expected script-run sequence is exactly
    /// `["en"]`. WER is reported for these cases and nowhere else (0.3.4a §7).
    public var isPureEnglish: Bool {
        expectedScriptRuns == ["en"]
    }

    public init(
        id: String,
        name: String = "",
        language: String = "",
        reference: String,
        keywords: [String] = [],
        criticalTokens: [String] = [],
        audioFile: String? = nil,
        expectedScriptRuns: [String] = [],
        negationPresent: Bool = false,
        numericPresent: Bool = false,
        category: String = ""
    ) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.language = language
        self.reference = reference
        self.keywords = keywords
        self.criticalTokens = criticalTokens
        self.audioFile = audioFile ?? "\(id).wav"
        self.expectedScriptRuns = expectedScriptRuns
        self.negationPresent = negationPresent
        self.numericPresent = numericPresent
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        // corpus-V0 keys
        case caseID = "case_id"
        case referenceTranscript = "reference_transcript"
        case audioFileKey = "audio_file"
        case expectedScriptRunsKey = "expected_script_runs"
        case criticalTokensSnake = "critical_tokens"
        case negationPresentKey = "negation_present"
        case numericPresentKey = "numeric_present"
        case category
        // legacy smoke-manifest keys
        case id, name, language, reference, keywords
        case criticalTokensCamel = "criticalTokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Identifier: case_id (V0) or id (legacy). One must be present.
        if let caseID = try c.decodeIfPresent(String.self, forKey: .caseID) {
            self.id = caseID
        } else if let legacyID = try c.decodeIfPresent(String.self, forKey: .id) {
            self.id = legacyID
        } else {
            throw DecodingError.keyNotFound(CodingKeys.caseID, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Fixture requires either \"case_id\" or \"id\""
            ))
        }

        // Reference: reference_transcript (V0) or reference (legacy).
        if let ref = try c.decodeIfPresent(String.self, forKey: .referenceTranscript) {
            self.reference = ref
        } else if let legacyRef = try c.decodeIfPresent(String.self, forKey: .reference) {
            self.reference = legacyRef
        } else {
            throw DecodingError.keyNotFound(CodingKeys.referenceTranscript, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Fixture requires either \"reference_transcript\" or \"reference\""
            ))
        }

        let decodedName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = decodedName.isEmpty ? self.id : decodedName
        self.language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        self.keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.criticalTokens =
            try c.decodeIfPresent([String].self, forKey: .criticalTokensSnake)
            ?? c.decodeIfPresent([String].self, forKey: .criticalTokensCamel)
            ?? []
        self.audioFile =
            try c.decodeIfPresent(String.self, forKey: .audioFileKey)
            ?? "\(self.id).wav"
        self.expectedScriptRuns =
            try c.decodeIfPresent([String].self, forKey: .expectedScriptRunsKey) ?? []
        self.negationPresent =
            try c.decodeIfPresent(Bool.self, forKey: .negationPresentKey) ?? false
        self.numericPresent =
            try c.decodeIfPresent(Bool.self, forKey: .numericPresentKey) ?? false
        self.category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
    }

    /// Encodes the corpus-V0 shape (round-trips through `init(from:)`).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .caseID)
        try c.encode(category, forKey: .category)
        try c.encode(reference, forKey: .referenceTranscript)
        try c.encode(audioFile, forKey: .audioFileKey)
        try c.encode(expectedScriptRuns, forKey: .expectedScriptRunsKey)
        try c.encode(criticalTokens, forKey: .criticalTokensSnake)
        try c.encode(negationPresent, forKey: .negationPresentKey)
        try c.encode(numericPresent, forKey: .numericPresentKey)
        if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
        if !language.isEmpty { try c.encode(language, forKey: .language) }
    }
}

public struct Scoring: Codable {
    public let normalizedTextAccuracy: Int
    public let technicalKeywordRecall: Int
    public let negationNumberLogicalPreservation: Int
    public let manualSemanticPreservation: Int
    public let inferenceSpeedRTF: Int
    public let loadWarmupPerformance: Int
    public let memoryEfficiency: Int
    public let total: Int

    public init(
        normalizedTextAccuracy: Int,
        technicalKeywordRecall: Int,
        negationNumberLogicalPreservation: Int,
        manualSemanticPreservation: Int,
        inferenceSpeedRTF: Int,
        loadWarmupPerformance: Int,
        memoryEfficiency: Int,
        total: Int
    ) {
        self.normalizedTextAccuracy = normalizedTextAccuracy
        self.technicalKeywordRecall = technicalKeywordRecall
        self.negationNumberLogicalPreservation = negationNumberLogicalPreservation
        self.manualSemanticPreservation = manualSemanticPreservation
        self.inferenceSpeedRTF = inferenceSpeedRTF
        self.loadWarmupPerformance = loadWarmupPerformance
        self.memoryEfficiency = memoryEfficiency
        self.total = total
    }
}

// MARK: - Scoring Functions

public func calculateCharacterErrorRate(_ reference: String, _ hypothesis: String) -> Double {
    let refChars = Array(reference.lowercased())
    let hypChars = Array(hypothesis.lowercased())

    let rows = refChars.count + 1
    let cols = hypChars.count + 1

    var matrix = Array(repeating: Array(repeating: 0, count: cols), count: rows)

    for i in 0..<rows { matrix[i][0] = i }
    for j in 0..<cols { matrix[0][j] = j }

    for i in 1..<rows {
        for j in 1..<cols {
            let cost = (refChars[i-1] == hypChars[j-1]) ? 0 : 1
            matrix[i][j] = min(
                matrix[i-1][j] + 1,
                matrix[i][j-1] + 1,
                matrix[i-1][j-1] + cost
            )
        }
    }

    let distance = matrix[rows-1][cols-1]
    return refChars.isEmpty ? 0 : Double(distance) / Double(refChars.count)
}

/// Normalize text for WER calculation per 0.3.4a §7:
/// - Lowercase
/// - Remove punctuation (keep apostrophes as word-internal)
/// - Collapse multiple whitespace to single space
/// - Trim
private func normalizeForWER(_ text: String) -> [String] {
    var result = text.lowercased()
    // Keep apostrophes within words, remove other punctuation
    let punctuationToRemove = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))
    result = result.unicodeScalars.map { punctuationToRemove.contains($0) ? " " : String($0) }.joined()
    // Collapse whitespace
    result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? [] : result.split(separator: " ").map(String.init)
}

/// Calculate Word Error Rate (WER) using word-level Levenshtein distance.
/// Per 0.3.4a §7: WER applies ONLY to pure-English cases (expectedScriptRuns == ["en"]).
/// Returns nil for non-pure-English cases.
public func calculateWordErrorRate(_ reference: String, _ hypothesis: String, isPureEnglish: Bool) -> Double? {
    guard isPureEnglish else { return nil }

    let refWords = normalizeForWER(reference)
    let hypWords = normalizeForWER(hypothesis)

    if refWords.isEmpty && hypWords.isEmpty { return 0 }
    if refWords.isEmpty { return 1.0 }

    let rows = refWords.count + 1
    let cols = hypWords.count + 1

    var matrix = Array(repeating: Array(repeating: 0, count: cols), count: rows)

    for i in 0..<rows { matrix[i][0] = i }
    for j in 0..<cols { matrix[0][j] = j }

    for i in 1..<rows {
        for j in 1..<cols {
            let cost = (refWords[i-1] == hypWords[j-1]) ? 0 : 1
            matrix[i][j] = min(
                matrix[i-1][j] + 1,      // deletion
                matrix[i][j-1] + 1,      // insertion
                matrix[i-1][j-1] + cost  // substitution
            )
        }
    }

    let distance = matrix[rows-1][cols-1]
    return Double(distance) / Double(refWords.count)
}

/// Script classification per 0.3.4a §8:
/// - Han characters (CJK Unified Ideographs) => "zh"
/// - Latin alphabetic characters => "en"
/// - Numbers, punctuation, whitespace => neutral (ignored)
/// Collapse adjacent identical classes.
public func extractScriptRuns(_ text: String) -> [String] {
    var runs: [String] = []

    for scalar in text.unicodeScalars {
        let script: String?
        if scalar.properties.isAlphabetic {
            // Check if Latin script
            if (0x0041...0x007A).contains(scalar.value) || // A-Z, a-z
               (0x00C0...0x024F).contains(scalar.value) || // Latin-1 Supplement, Latin Extended-A/B
               (0x1E00...0x1EFF).contains(scalar.value) {   // Latin Extended Additional
                script = "en"
            } else if (0x4E00...0x9FFF).contains(scalar.value) || // CJK Unified Ideographs
                      (0x3400...0x4DBF).contains(scalar.value) || // CJK Extension A
                      (0x20000...0x2A6DF).contains(scalar.value) || // CJK Extension B
                      (0x2A700...0x2B73F).contains(scalar.value) || // CJK Extension C
                      (0x2B740...0x2B81F).contains(scalar.value) || // CJK Extension D
                      (0x2B820...0x2CEAF).contains(scalar.value) || // CJK Extension E
                      (0x2CEB0...0x2EBEF).contains(scalar.value) || // CJK Extension F
                      (0x3000...0x303F).contains(scalar.value) || // CJK Symbols and Punctuation (treat as zh context)
                      (0xFF00...0xFFEF).contains(scalar.value) {   // Halfwidth and Fullwidth Forms
                script = "zh"
            } else {
                script = nil // Other alphabets -> neutral
            }
        } else {
            script = nil // Numbers, punctuation, whitespace -> neutral
        }

        if let script = script {
            if runs.last != script {
                runs.append(script)
            }
        }
    }

    return runs
}

/// Calculate language fidelity: true iff observed script runs exactly match expected.
public func calculateLanguageFidelity(expected: [String], observed: [String]) -> Bool {
    return expected == observed
}

public func calculateKeywordRecall(reference: String, hypothesis: String, keywords: [String]) -> Double {
    let hypLower = hypothesis.lowercased()
    var matched = 0

    for keyword in keywords {
        if hypLower.contains(keyword.lowercased()) {
            matched += 1
        }
    }

    return keywords.isEmpty ? 0 : Double(matched) / Double(keywords.count)
}

public func checkNegationPreservation(reference: String, hypothesis: String) -> Bool {
    let negationPatterns = ["不", "没有", "不", "not", "no ", "never", "cannot", "don't", "doesn't", "won't", "can't"]
    let hypLower = hypothesis.lowercased()

    for pattern in negationPatterns {
        if reference.contains(pattern) && !hypLower.contains(pattern) {
            return false
        }
    }

    return true
}

public func calculateCriticalTokenRecall(reference: String, hypothesis: String, criticalTokens: [String]) -> Double {
    let hypLower = hypothesis.lowercased()
    var matched = 0

    for token in criticalTokens {
        if hypLower.contains(token.lowercased()) {
            matched += 1
        }
    }

    return criticalTokens.isEmpty ? 0 : Double(matched) / Double(criticalTokens.count)
}

// MARK: - Memory Utilities

public func getProcessMemory() -> Int64? {
    return nil
}

// MARK: - WAV File Loading

public struct WAVAUDIO {
    public let samples: [Float]
    public let sampleRate: Double
    public let channels: Int

    public init(samples: [Float], sampleRate: Double, channels: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public func loadWAV(at url: URL) throws -> WAVAUDIO {
    let fileHandle = try FileHandle(forReadingFrom: url)
    defer { try? fileHandle.close() }

    let data = fileHandle.readDataToEndOfFile()

    // Parse WAV header
    guard data.count >= 44 else {
        throw WAVError.invalidFile("File too small for WAV header")
    }

    // Check RIFF header
    let riffTag = data.subdata(in: 0..<4).withUnsafeBytes { String(bytes: $0, encoding: .ascii) }
    guard riffTag == "RIFF" else {
        throw WAVError.invalidFile("Missing RIFF header")
    }

    // Check WAVE format
    let waveTag = data.subdata(in: 8..<12).withUnsafeBytes { String(bytes: $0, encoding: .ascii) }
    guard waveTag == "WAVE" else {
        throw WAVError.invalidFile("Missing WAVE format")
    }

    // Find fmt chunk
    var fmtOffset = 12
    while fmtOffset < data.count - 8 {
        let chunkTag = data.subdata(in: fmtOffset..<fmtOffset+4).withUnsafeBytes { String(bytes: $0, encoding: .ascii) }
        let chunkSize = data.subdata(in: fmtOffset+4..<fmtOffset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        if chunkTag == "fmt " {
            break
        }
        fmtOffset += 8 + Int(chunkSize)
    }

    guard fmtOffset < data.count - 8 else {
        throw WAVError.invalidFile("Missing fmt chunk")
    }

    // Parse fmt chunk
    let _ = data.subdata(in: fmtOffset+8..<fmtOffset+10).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    let numChannels = data.subdata(in: fmtOffset+10..<fmtOffset+12).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    let sampleRate = data.subdata(in: fmtOffset+12..<fmtOffset+16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let bitsPerSample = data.subdata(in: fmtOffset+22..<fmtOffset+24).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }

    // Find data chunk
    var dataOffset = fmtOffset + 8 + Int(data.subdata(in: fmtOffset+4..<fmtOffset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
    while dataOffset < data.count - 8 {
        let chunkTag = data.subdata(in: dataOffset..<dataOffset+4).withUnsafeBytes { String(bytes: $0, encoding: .ascii) }
        let chunkSize = data.subdata(in: dataOffset+4..<dataOffset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        if chunkTag == "data" {
            break
        }
        dataOffset += 8 + Int(chunkSize)
    }

    guard dataOffset < data.count - 8 else {
        throw WAVError.invalidFile("Missing data chunk")
    }

    let dataChunkSize = data.subdata(in: dataOffset+4..<dataOffset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let dataStart = dataOffset + 8

    // Read samples
    var samples: [Float] = []
    let numSamples = Int(dataChunkSize) / (Int(bitsPerSample) / 8) / Int(numChannels)

    for i in 0..<numSamples {
        let sampleOffset = dataStart + (i * Int(numChannels) * Int(bitsPerSample) / 8)

        if bitsPerSample == 32 {
            // Float32 - read as bytes and convert
            let sampleBytes = data.subdata(in: sampleOffset..<sampleOffset+4)
            let sample = sampleBytes.withUnsafeBytes { $0.load(as: Float32.self) }
            samples.append(Float(sample))
        } else if bitsPerSample == 16 {
            // Int16, convert to Float32 [-1, 1]
            let sample = data.subdata(in: sampleOffset..<sampleOffset+2).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            samples.append(Float(sample) / 32768.0)
        } else {
            throw WAVError.invalidFile("Unsupported bits per sample: \(bitsPerSample)")
        }
    }

    return WAVAUDIO(
        samples: samples,
        sampleRate: Double(sampleRate),
        channels: Int(numChannels)
    )
}

public enum WAVError: LocalizedError {
    case invalidFile(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let reason):
            return "Invalid WAV file: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

// MARK: - Benchmark Runner

public struct BenchmarkCore {
    public init() {}

    public func runBenchmark(
        modelID: String,
        fixturesPath: String,
        manifestPath: String,
        outputPath: String
    ) async throws -> BenchmarkReport {
        print("🎯 VoiceDock ASR Benchmark")
        print("=" .replicated(50))
        print("Model: \(modelID)")
        print("Fixtures: \(fixturesPath)")
        print("Manifest: \(manifestPath)")
        print("Output: \(outputPath)")

        // Load manifest
        let manifestURL = URL(fileURLWithPath: manifestPath)
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BenchmarkManifest.self, from: manifestData)

        print("\n📋 Loaded \(manifest.fixtures.count) fixtures")

        // Resolve model descriptor
        let descriptor: QwenModelDescriptor
        switch modelID {
        case "qwen3-0.6b-8bit":
            descriptor = .qwen3_0_6B_8bit
        case "qwen3-1.7b-4bit":
            descriptor = .qwen3_1_7B_4bit
        default:
            print("❌ Unknown model ID: \(modelID)")
            throw BenchmarkError.unknownModel(modelID)
        }

        print("📦 Model descriptor: \(descriptor.displayName)")
        print("   Repo: \(descriptor.repoID)")

        // Check if model is installed
        let storage = ModelStorage()
        let isValid = await storage.isModelValid(descriptor)
        if !isValid {
            print("❌ Model not installed or invalid at canonical path")
            print("   Expected: \(await storage.modelDirectory(for: descriptor).path)")
            throw BenchmarkError.modelNotFound(descriptor.repoID)
        }
        print("✅ Model validated at canonical path")

        // Create provider
        let provider = Qwen3ASRProvider(descriptor: descriptor)

        // Initialize result collector
        var results: [BenchmarkResult] = []
        let memoryBefore = getProcessMemory()

        // Open JSONL output if requested
        let jsonlPath = try BenchmarkPaths.jsonlOutputPath(for: modelID)
        var jsonlHandle: FileHandle?
        if let jsonlPath = jsonlPath {
            let jsonlURL = URL(fileURLWithPath: jsonlPath)
            try FileManager.default.createDirectory(at: jsonlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: jsonlPath) {
                FileManager.default.createFile(atPath: jsonlPath, contents: nil)
            }
            jsonlHandle = try FileHandle(forWritingTo: jsonlURL)
            try jsonlHandle?.seekToEnd()
            print("📝 JSONL streaming enabled: \(jsonlPath)")
        }

        // Load model
        print("\n📥 Loading model...")
        let loadStart = Date()
        try await provider.load()
        let loadTime = Date().timeIntervalSince(loadStart)
        print("✅ Model loaded in \(String(format: "%.3f", loadTime))s")

        let memoryAfterLoad = getProcessMemory()

        // Warmup
        print("🔥 Warming up...")
        let warmupStart = Date()
        try await provider.warmup()
        let warmupTime = Date().timeIntervalSince(warmupStart)
        print("✅ Warmup completed in \(String(format: "%.3f", warmupTime))s")

        // Process fixtures
        print("\n🎤 Processing fixtures...")
        print("-" .replicated(50))

        let fixturesDir = URL(fileURLWithPath: fixturesPath)
        let runStart = Date()

        for fixture in manifest.fixtures {
            print("\nFixture: \(fixture.name)")

            // Check for WAV file (resolution honors the manifest's audio_file field)
            let wavPath = fixturesDir.appendingPathComponent(fixture.audioFile)
            if !FileManager.default.fileExists(atPath: wavPath.path) {
                print("⚠️  WAV file not found: \(wavPath.path)")
                print("   Skipping - owner needs to record this fixture")
                continue
            }

            print("   Processing \(wavPath.lastPathComponent)...")

            // Load WAV file
            let wavAudio = try loadWAV(at: wavPath)
            print("   Loaded \(wavAudio.samples.count) samples at \(wavAudio.sampleRate) Hz")

            // Resample to 16 kHz if needed
            let audioSamples: [Float]
            if abs(wavAudio.sampleRate - 16_000) > 1 {
                print("   Resampling from \(wavAudio.sampleRate) Hz to 16000 Hz...")
                let normalizer = AudioNormalizer()
                audioSamples = normalizer.normalize(samples: wavAudio.samples)
            } else {
                audioSamples = wavAudio.samples
            }

            // Calculate waveform statistics
            var minVal: Float = .infinity
            var maxVal: Float = -.infinity
            var sumSquares: Float = 0
            for sample in audioSamples {
                if sample < minVal { minVal = sample }
                if sample > maxVal { maxVal = sample }
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(audioSamples.count))

            // Transcribe
            print("   Transcribing...")
            let inferenceStart = Date()
            let transcript = try await provider.transcribe(audio: audioSamples)
            let inferenceTime = Date().timeIntervalSince(inferenceStart)

            print("   Transcript: \(transcript.prefix(80))...")

            // Calculate metrics
            let audioDuration = Double(audioSamples.count) / 16_000
            let realTimeFactor = inferenceTime / audioDuration
            let cer = calculateCharacterErrorRate(fixture.reference, transcript)
            let wer = calculateWordErrorRate(fixture.reference, transcript, isPureEnglish: fixture.isPureEnglish)
            let keywordRecall = calculateKeywordRecall(reference: fixture.reference, hypothesis: transcript, keywords: fixture.keywords)
            let criticalTokenRecall = calculateCriticalTokenRecall(reference: fixture.reference, hypothesis: transcript, criticalTokens: fixture.criticalTokens)
            let negationPreserved = checkNegationPreservation(reference: fixture.reference, hypothesis: transcript)
            let observedScriptRuns = extractScriptRuns(transcript)
            let languageFidelity = calculateLanguageFidelity(expected: fixture.expectedScriptRuns, observed: observedScriptRuns)

            print("   CER: \(String(format: "%.2f", cer * 100))%, Keyword Recall: \(String(format: "%.2f", keywordRecall * 100))%")
            print("   Critical Token Recall: \(String(format: "%.2f", criticalTokenRecall * 100))%, Negation Preserved: \(negationPreserved)")
            if let wer = wer {
                print("   WER: \(String(format: "%.2f", wer * 100))%")
            }
            print("   Expected Script Runs: \(fixture.expectedScriptRuns), Observed: \(observedScriptRuns), Fidelity: \(languageFidelity)")

            let result = BenchmarkResult(
                modelIdentifier: modelID,
                fixtureIdentifier: fixture.id,
                audioDuration: audioDuration,
                sampleCount: audioSamples.count,
                waveformRMS: Double(rms),
                modelLoadTime: loadTime,
                warmupTime: warmupTime,
                inferenceTime: inferenceTime,
                realTimeFactor: realTimeFactor,
                processMemoryBeforeLoad: memoryBefore,
                processMemoryAfterLoad: memoryAfterLoad,
                peakMemory: nil,
                transcript: transcript,
                normalizedCharacterErrorRate: cer,
                wordErrorRate: wer,
                keywordRecall: keywordRecall,
                criticalTokenRecall: criticalTokenRecall,
                negationPreserved: negationPreserved,
                expectedScriptRuns: fixture.expectedScriptRuns,
                observedScriptRuns: observedScriptRuns,
                languageFidelity: languageFidelity,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            results.append(result)

            // Write JSONL line if enabled
            if let jsonlHandle = jsonlHandle {
                let jsonlEncoder = JSONEncoder()
                jsonlEncoder.outputFormatting = [.sortedKeys]
                let jsonlData = try jsonlEncoder.encode(result)
                try jsonlHandle.write(contentsOf: jsonlData)
                try jsonlHandle.write(contentsOf: "\n".data(using: .utf8)!)
            }
        }

        // Close JSONL handle
        try jsonlHandle?.close()

        let totalRunTime = Date().timeIntervalSince(runStart)

        // Calculate averages
        let completedCount = results.count
        let avgInferenceTime = results.isEmpty ? 0 : results.map { $0.inferenceTime }.reduce(0, +) / Double(results.count)
        let avgRTF = results.isEmpty ? nil : results.map { $0.realTimeFactor ?? 0 }.reduce(0, +) / Double(results.count)
        let avgCER = results.isEmpty ? nil : results.map { $0.normalizedCharacterErrorRate ?? 0 }.reduce(0, +) / Double(results.count)
        let avgKeywordRecall = results.isEmpty ? nil : results.map { $0.keywordRecall ?? 0 }.reduce(0, +) / Double(results.count)
        let avgCriticalTokenRecall = results.isEmpty ? nil : results.map { $0.criticalTokenRecall ?? 0 }.reduce(0, +) / Double(results.count)

        // Generate report
        let report = BenchmarkReport(
            modelIdentifier: modelID,
            modelDisplayName: descriptor.displayName,
            totalFixtures: manifest.fixtures.count,
            completedFixtures: completedCount,
            failedFixtures: 0,
            avgInferenceTime: avgInferenceTime,
            avgRealTimeFactor: avgRTF,
            totalMemoryDelta: memoryAfterLoad.flatMap { after in
                memoryBefore.map { before in after - before }
            },
            avgCharacterErrorRate: avgCER,
            avgKeywordRecall: avgKeywordRecall,
            avgCriticalTokenRecall: avgCriticalTokenRecall,
            results: results,
            runTimestamp: ISO8601DateFormatter().string(from: Date()),
            runDuration: totalRunTime
        )

        // Write output
        let outputURL = URL(fileURLWithPath: outputPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputData = try encoder.encode(report)
        try outputData.write(to: outputURL)

        print("\n📊 Results written to: \(outputPath)")
        print("\n✅ Benchmark complete: \(completedCount)/\(manifest.fixtures.count) fixtures processed")

        return report
    }
}

public enum BenchmarkError: LocalizedError {
    case unknownModel(String)
    case modelNotFound(String)
    case fixtureNotFound(String)
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "Unknown model ID: \(id)"
        case .modelNotFound(let repo):
            return "Model not found: \(repo)"
        case .fixtureNotFound(let id):
            return "Fixture not found: \(id)"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        }
    }
}

// MARK: - String Extension

public extension String {
    func replicated(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}