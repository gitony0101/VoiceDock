@main enum BenchmarkEntryPoint {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        let subcommandArgs = Array(args.dropFirst())

        switch command {
        case "run":
            try await VoiceDockASRBench.runBenchmark(args: subcommandArgs)
        case "record":
            try await VoiceDockASRBench.runRecording(args: subcommandArgs)
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        VoiceDockASRBench - ASR Model Benchmark & Fixture Recording

        Commands:
          run     Run ASR benchmark on recorded fixtures
          record  Record a new fixture

        Usage:
          VoiceDockASRBench run \\
            --model <model-id> \\
            [--fixtures <path-to-fixtures-dir>] \\
            [--manifest <path-to-manifest.json>] \\
            [--output <path-to-output-file.json>] \\
            [--language <en|zh|mixed>]

          VoiceDockASRBench record \\
            --output <path-to-output.wav> \\
            [--duration <max-seconds>] \\
            [--force]

        Required (run command):
          --model     Model ID: qwen3-0.6b-8bit, qwen3-1.7b-4bit, qwen3-0.6b-6bit
                      Or set VOICEDOCK_ASR_MODEL environment variable

        Optional (canonical defaults used if omitted):
          --fixtures  Fixtures directory
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/fixtures
          --manifest  Manifest file path
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/manifest.json
          --output    Output JSON file path (always a complete file path)
                      Default: $HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/results/<model-id>.json

        Environment Variable Overrides:
          VOICEDOCK_BENCHMARK_BASE      Base directory
          VOICEDOCK_BENCHMARK_FIXTURES  Fixtures directory
          VOICEDOCK_BENCHMARK_MANIFEST  Manifest file path
          VOICEDOCK_BENCHMARK_OUTPUT    Output file path (always a complete file path)
          VOICEDOCK_ASR_MODEL           Model selection (if --model not provided)

        Recording:
          After starting, speak your phrase. Press Enter to stop or wait for auto-stop.
          Use --force to overwrite existing files.
        """)
    }
}
