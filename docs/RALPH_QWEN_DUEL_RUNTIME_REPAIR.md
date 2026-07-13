# VoiceDock Qwen Duel Runtime Repair

Read this specification completely before editing.

Read:

* AGENTS.md
* docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md
* Benchmarks/VoiceDockASRBench/main.swift
* Benchmarks/VoiceDockASRBench/BenchmarkRunner.swift
* Benchmarks/VoiceDockASRBench/FixtureRecorder.swift
* VoiceDockApp/AppDelegate.swift
* VoiceDockCore/Sources/Qwen3ASRProvider.swift
* VoiceDockCore/Sources/QwenModelDescriptor.swift
* VoiceDockCore/Sources/AudioNormalizer.swift
* Package.swift
* project.yml

Treat AGENTS.md as authoritative.

## Ground Truth

The current implementation is incomplete.

The fixture recorder builds, but the current benchmark run command is still a placeholder and does not perform inference.

The standalone VoiceDockASRBench executable encounters:

Failed to load the default metallib

The real VoiceDock.app process has already demonstrated that MLX and Qwen can run successfully.

Do not claim QWEN_DUEL_OWNER_READY until both Qwen models actually load, warm up and process WAV audio through a working benchmark host.

## Objective

Complete a real, Metal-capable benchmark flow for:

* qwen3-0.6b-8bit
* qwen3-1.7b-4bit

Use the real VoiceDock.app execution environment for model inference when the standalone SwiftPM executable cannot resolve MLX Metal resources.

The same six WAV files must be processed by both models.

Nemotron remains available and the normal production default remains unchanged.

## Part 1: Preserve and Repair Fixture Recording

Keep the developer-only record command.

Repair the following issues:

1. Enforce the --duration maximum.
2. Do not overwrite an existing WAV by default.
3. Add an explicit --force flag for replacement.
4. Ensure output directories are created safely.
5. Print sample count, duration, minimum amplitude, maximum amplitude and RMS.
6. Confirm the WAV is valid mono 16 kHz PCM or Float32 WAV.
7. Clearly document whether recording uses VoiceDock AudioCapture directly or an equivalent AVAudioEngine path.
8. Do not make inaccurate claims that it uses AudioCapture when it does not.

The owner records each fixture exactly once.

## Part 2: Implement a Debug-Only App Benchmark Mode

Add a debug-only benchmark mode to VoiceDock.app.

Activate only when:

VOICEDOCK_BENCHMARK_MODE=1

Required environment variables:

VOICEDOCK_ASR_MODEL

VOICEDOCK_BENCHMARK_FIXTURES

VOICEDOCK_BENCHMARK_MANIFEST

VOICEDOCK_BENCHMARK_OUTPUT

Supported models:

qwen3-0.6b-8bit

qwen3-1.7b-4bit

Behavior:

1. Do not initialize normal push-to-talk UI workflows.
2. Do not register the global hotkey.
3. Do not paste to the clipboard.
4. Do not request microphone access.
5. Load the selected model from its canonical Application Support path.
6. Measure model load time.
7. Warm up the model and measure warmup time.
8. Read every fixture WAV from the fixture directory.
9. Decode and normalize through the production AudioNormalizer.
10. Run Qwen transcription using the same generation settings for both candidates.
11. Measure inference time and real-time factor.
12. Calculate waveform statistics.
13. Calculate normalized CER.
14. Calculate keyword recall.
15. Calculate critical-token recall.
16. Evaluate critical negation preservation.
17. Serialize all results to the requested JSON output path.
18. Exit with status zero after successful completion.
19. Exit nonzero with a clear error if any fixture or model operation fails.

Compile this behavior only in Debug builds when practical.

Normal VoiceDock startup must remain unchanged when benchmark mode is absent.

## Part 3: Shared Benchmark Core

Move reusable benchmark logic into a small shared type accessible by the Debug app benchmark mode.

Do not keep a placeholder runBenchmark implementation.

The benchmark implementation must genuinely:

* parse manifest JSON
* locate WAV fixtures
* load the selected Qwen descriptor
* run inference
* compute scores
* write result JSON

The standalone VoiceDockASRBench run command may either:

1. use the working shared benchmark core if the metallib issue is repaired, or
2. print an exact command that invokes the Debug VoiceDock.app benchmark mode.

Do not claim the standalone command performs inference when it does not.

## Part 4: Exact Runtime Commands

Determine the actual Debug VoiceDock.app executable path.

Document exact commands for both models.

Example structure:

VOICEDOCK_BENCHMARK_MODE=1 
VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit 
VOICEDOCK_BENCHMARK_FIXTURES="$HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/fixtures" 
VOICEDOCK_BENCHMARK_MANIFEST="$HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/manifest.json" 
VOICEDOCK_BENCHMARK_OUTPUT="$HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/results/qwen3-0.6b-8bit.json" 
"/absolute/path/to/VoiceDock.app/Contents/MacOS/VoiceDock"

Provide the equivalent command for qwen3-1.7b-4bit.

Do not use quoted tilde paths.

## Part 5: Model Runtime Proof

Before completion, prove in the benchmark host that both models:

1. resolve their canonical directory
2. load successfully
3. complete warmup
4. process at least one valid WAV fixture
5. produce a transcript
6. write a structurally valid JSON result
7. unload or terminate cleanly
8. produce no metallib error

Do not infer load or warmup success from the process merely remaining alive.

Capture exact load and warmup durations.

If owner speech fixtures are not yet available, use one temporary local untracked WAV only to prove runtime execution. Do not use that temporary fixture to declare a quality winner.

## Part 6: Tests and Verification

Run and record:

* swift build
* swift test
* xcodegen generate
* xcodebuild Debug build
* xcodebuild Debug test
* xcodebuild Release build
* git diff --check

Report exact SwiftPM and Xcode test totals.

Test:

* benchmark environment parsing
* missing variable errors
* model selection
* manifest parsing
* WAV lookup
* score calculation
* result serialization
* overwrite protection
* recording duration limit

Tests must not load full MLX models unless explicitly running the app benchmark smoke test.

## Part 7: Documentation Accuracy

Update:

docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md

Correct all claims so the document distinguishes:

* code builds
* model files validate
* model loads
* warmup completes
* fixture transcription completes
* owner quality comparison remains pending

Remove any placeholder output presented as a real benchmark result.

Document:

1. six exact recording commands
2. two exact app benchmark commands
3. corrected test counts
4. actual model load durations
5. actual warmup durations
6. metallib findings supported by evidence
7. output JSON locations
8. remaining owner actions

## Restrictions

* Do not change the production default model.
* Do not delete or redownload any model.
* Do not delete Nemotron.
* Do not upgrade dependencies.
* Do not change the app icon.
* Do not add public model selection UI.
* Do not commit.
* Do not push.
* Do not declare a winner.
* Do not output VOICEDOCK_COMPLETE.

## Completion Promise

Output exactly:

QWEN_DUEL_OWNER_READY

Only when:

1. the recorder works with duration and overwrite protection
2. the same WAV set can be processed by both models
3. both models load and warm up in the actual benchmark host
4. at least one WAV has completed inference through each model
5. real JSON output has been generated for each model
6. no metallib error occurs in the working benchmark host
7. all automated gates pass
8. documentation accurately matches the implementation

Owner recording of the complete six-fixture corpus and final quality judgment are outside this completion promise.

