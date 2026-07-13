import Foundation
import VoiceDockCore
import MLX
import MLXAudioSTT
import MLXAudioCore

// MARK: - Command Line Arguments

struct BenchmarkArgs {
    var modelID: String
    var fixturesPath: String
    var manifestPath: String
    var outputPath: String
    var languageMode: String?

    static func parse(from args: [String]) throws -> BenchmarkArgs {
        var iterator = args.makeIterator()
        var modelID: String?
        var fixturesPath: String?
        var manifestPath: String?
        var outputPath: String?
        var languageMode: String?

        while let arg = iterator.next() {
            switch arg {
            case "--model":
                modelID = iterator.next()
            case "--fixtures":
                fixturesPath = iterator.next()
            case "--manifest":
                manifestPath = iterator.next()
            case "--output":
                outputPath = iterator.next()
            case "--language":
                languageMode = iterator.next()
            default:
                print("Unknown argument: \(arg)")
                throw BenchmarkArgError.unknownArgument(arg)
            }
        }

        // Model selection is required - check command-line first, then environment
        let resolvedModelID: String
        if let model = modelID {
            resolvedModelID = model
        } else if let envModel = ProcessInfo.processInfo.environment["VOICEDOCK_ASR_MODEL"] {
            resolvedModelID = envModel
        } else {
            print("❌ Model selection is required.")
            print("   Use --model <model-id> or set VOICEDOCK_ASR_MODEL environment variable.")
            print("")
            printUsage()
            throw BenchmarkArgError.missingModelSelection
        }

        // Use canonical BenchmarkPaths for defaults if not provided
        let resolvedFixturesPath: String
        let resolvedManifestPath: String
        let resolvedOutputPath: String

        do {
            if let fixturesPath = fixturesPath {
                resolvedFixturesPath = fixturesPath
            } else {
                resolvedFixturesPath = try BenchmarkPaths.fixturesDirectory().path
            }

            if let manifestPath = manifestPath {
                resolvedManifestPath = manifestPath
            } else {
                resolvedManifestPath = try BenchmarkPaths.manifestPath()
            }

            if let outputPath = outputPath {
                resolvedOutputPath = outputPath
            } else {
                resolvedOutputPath = try BenchmarkPaths.outputPath(for: resolvedModelID)
            }
        } catch {
            print("❌ Failed to resolve benchmark paths: \(error.localizedDescription)")
            throw BenchmarkArgError.pathResolutionFailed(error.localizedDescription)
        }

        return BenchmarkArgs(
            modelID: resolvedModelID,
            fixturesPath: resolvedFixturesPath,
            manifestPath: resolvedManifestPath,
            outputPath: resolvedOutputPath,
            languageMode: languageMode
        )
    }

    static func printUsage() {
        print("""
        VoiceDockASRBench - ASR Model Benchmark Runner

        Usage:
          VoiceDockASRBench run \\
            --model <model-id> \\
            [--fixtures <path-to-fixtures-dir>] \\
            [--manifest <path-to-manifest.json>] \\
            [--output <path-to-output.json>] \\
            [--language <en|zh|mixed>]

        Required:
          --model     Model ID: qwen3-0.6b-8bit, qwen3-1.7b-4bit, qwen3-0.6b-6bit
                      Or set VOICEDOCK_ASR_MODEL environment variable

        Optional (canonical defaults used if omitted):
          --fixtures  Directory containing WAV fixture files
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/fixtures
          --manifest  JSON manifest with reference transcripts
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/manifest.json
          --output    Output JSON file path for results
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/results/<model-id>.json
          --language  Optional language mode filter

        Environment Variable Overrides:
          VOICEDOCK_BENCHMARK_BASE      Base directory (default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel)
          VOICEDOCK_BENCHMARK_FIXTURES  Fixtures directory
          VOICEDOCK_BENCHMARK_MANIFEST  Manifest file path
          VOICEDOCK_BENCHMARK_OUTPUT    Output file path (always a complete file path)
          VOICEDOCK_ASR_MODEL           Model selection (if --model not provided)
        """)
    }
}

public enum BenchmarkArgError: LocalizedError {
    case unknownArgument(String)
    case missingModelSelection
    case pathResolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownArgument(let arg):
            return "Unknown argument: \(arg)"
        case .missingModelSelection:
            return "Model selection is required. Use --model <model-id> or set VOICEDOCK_ASR_MODEL."
        case .pathResolutionFailed(let reason):
            return "Failed to resolve benchmark paths: \(reason)"
        }
    }
}

// MARK: - Recording Arguments

struct RecordArgs {
    var outputPath: String
    var maxDuration: Double
    var force: Bool

    static func parse(from args: [String]) -> RecordArgs? {
        var outputPath: String?
        var maxDuration: Double = 30.0
        var force: Bool = false

        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--output":
                outputPath = iterator.next()
            case "--duration":
                if let durationStr = iterator.next(),
                   let duration = Double(durationStr) {
                    maxDuration = duration
                }
            case "--force":
                force = true
            default:
                // Skip unknown arguments
                break
            }
        }

        guard let outputPath = outputPath else {
            print("""
            Usage: VoiceDockASRBench record --output <path-to-output.wav> [--duration <seconds>] [--force]

            Options:
              --output    Output WAV file path (required)
              --duration  Maximum recording duration in seconds (default: 30)
              --force     Overwrite existing file without asking

            Recording:
              Press Enter to start recording, speak your phrase, then press Enter to stop.
              Recording will auto-stop after --duration seconds.
            """)
            return nil
        }

        return RecordArgs(outputPath: outputPath, maxDuration: maxDuration, force: force)
    }
}

// MARK: - Main Entry Point

struct VoiceDockASRBench {
    static func runBenchmark(args: [String]) async throws {
        let benchmarkArgs: BenchmarkArgs
        do {
            benchmarkArgs = try BenchmarkArgs.parse(from: args)
        } catch {
            // Error message already printed by parse()
            throw error
        }

        // Use shared BenchmarkCore for real inference
        let core = BenchmarkCore()
        _ = try await core.runBenchmark(
            modelID: benchmarkArgs.modelID,
            fixturesPath: benchmarkArgs.fixturesPath,
            manifestPath: benchmarkArgs.manifestPath,
            outputPath: benchmarkArgs.outputPath
        )
    }

    static func runRecording(args: [String]) async throws {
        guard let recordArgs = RecordArgs.parse(from: args) else {
            return
        }

        print("🎤 VoiceDock Fixture Recorder")
        print("=" .replicated(50))
        print("Output: \(recordArgs.outputPath)")
        print("Max duration: \(recordArgs.maxDuration)s")
        print("Overwrite protection: \(recordArgs.force ? "disabled (--force)" : "enabled")")
        print("")
        print("Audio path: AVAudioEngine → AudioNormalizer → PCM WAV (16 kHz mono Float32)")
        print("Note: Uses AVAudioEngine directly, not VoiceDock AudioCapture class.")
        print("")
        print("Instructions:")
        print("  1. Press Enter to start recording")
        print("  2. Speak your phrase clearly")
        print("  3. Press Enter to stop (or wait for auto-stop at max duration)")
        print("")

        // Wait for user to press Enter to start
        print("Press Enter to start recording...")
        _ = FileHandle.standardInput.availableData

        let recorder = FixtureRecorder(maxDuration: recordArgs.maxDuration)

        print("🔴 Recording... (speak now, max \(recordArgs.maxDuration)s)")
        print("Press Enter to stop, or wait for auto-stop.")

        do {
            try recorder.start()

            // Wait for user to press Enter to stop
            _ = FileHandle.standardInput.availableData

            let (samples, duration) = try recorder.stop()

            print("")
            print("📊 Recording Statistics:")
            print("   Sample count: \(samples.count)")
            print("   Duration: \(String(format: "%.2f", duration))s")

            let stats = recorder.calculateStatistics(for: samples)
            print("   Min amplitude: \(String(format: "%.4f", stats.min))")
            print("   Max amplitude: \(String(format: "%.4f", stats.max))")
            print("   RMS level: \(String(format: "%.4f", stats.rms))")

            // Save as WAV
            let outputURL = URL(fileURLWithPath: recordArgs.outputPath)
            try recorder.saveAsWAV(samples, to: outputURL, force: recordArgs.force)

            print("")
            print("✅ Fixture saved: \(recordArgs.outputPath)")
            print("")
            print("Next step:")
            print("  Move this file to:")
            print("  $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/fixtures/")
            print("")
            print("  Or rename to match fixture ID:")
            print("  fixture_1_drl_web_coding.wav")
            print("  fixture_2_voicedock_model_decision.wav")
            print("  fixture_3_replay_buffer.wav")
            print("  fixture_4_gymnasium_termination.wav")
            print("  fixture_5_swift_mlx.wav")
            print("  fixture_6_typed_web_api.wav")

        } catch RecordingError.fileExists(let path) {
            print("")
            print("⚠️  File already exists: \(path)")
            print("   Use --force to overwrite, or choose a different output path.")
        } catch {
            print("❌ Recording failed: \(error.localizedDescription)")
            recorder.cancel()
            throw error
        }
    }
}