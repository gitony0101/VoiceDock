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
    public let keywordRecall: Double?
    public let criticalTokenRecall: Double?
    public let negationPreserved: Bool?
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
        keywordRecall: Double?,
        criticalTokenRecall: Double?,
        negationPreserved: Bool?,
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
        self.keywordRecall = keywordRecall
        self.criticalTokenRecall = criticalTokenRecall
        self.negationPreserved = negationPreserved
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

public struct Fixture: Codable {
    public let id: String
    public let name: String
    public let language: String
    public let reference: String
    public let keywords: [String]
    public let criticalTokens: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, language, reference, keywords, criticalTokens
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

            // Check for WAV file
            let wavPath = fixturesDir.appendingPathComponent("\(fixture.id).wav")
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
            let keywordRecall = calculateKeywordRecall(reference: fixture.reference, hypothesis: transcript, keywords: fixture.keywords)
            let criticalTokenRecall = calculateCriticalTokenRecall(reference: fixture.reference, hypothesis: transcript, criticalTokens: fixture.criticalTokens)
            let negationPreserved = checkNegationPreservation(reference: fixture.reference, hypothesis: transcript)

            print("   CER: \(String(format: "%.2f", cer * 100))%, Keyword Recall: \(String(format: "%.2f", keywordRecall * 100))%")
            print("   Critical Token Recall: \(String(format: "%.2f", criticalTokenRecall * 100))%, Negation Preserved: \(negationPreserved)")

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
                keywordRecall: keywordRecall,
                criticalTokenRecall: criticalTokenRecall,
                negationPreserved: negationPreserved,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            results.append(result)
        }

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