

# VoiceDock Qwen3-ASR Phase 2B Runtime Validation

Read this specification completely at the beginning of every iteration.

Before editing, read:

* AGENTS.md
* docs/QWEN3_ASR_06B_6BIT_INVESTIGATION.md
* docs/QWEN3_ASR_PHASE2A_IMPLEMENTATION_REPORT.md
* ASRProvider.swift
* MLXAudioSTTProvider.swift
* Qwen3ASRProvider.swift
* QwenModelDescriptor.swift
* ModelStorage.swift
* ModelInstaller.swift
* SessionCoordinator.swift
* AppDelegate.swift
* Package.swift
* project.yml
* all newly added Qwen tests

Treat AGENTS.md as authoritative.

## Current Ground Truth

The Qwen model is installed at:

~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/

Model installation and static validation passed.

The following real inference operations have not yet been verified:

* Qwen3ASRModel loading
* Qwen warmup
* Qwen speech transcription
* Qwen operation inside VoiceDock.app

The production default currently remains Nemotron.

Do not claim that Qwen inference is verified until it runs successfully inside VoiceDock.app.

## Objective

Add a minimal, reversible runtime selection mechanism that allows the real VoiceDock.app process to launch with Qwen3-ASR 0.6B 6-bit for physical testing.

Do not change the production default model during this phase.

The application must continue using Nemotron when no explicit override is supplied.

## Required Runtime Selection

Support this environment variable:

VOICEDOCK_ASR_MODEL=qwen3-0.6b-6bit

Selection behavior:

* Environment variable absent:
  use the existing Nemotron provider
* Value equals qwen3-0.6b-6bit:
  use Qwen3ASRProvider with the canonical Application Support model directory
* Unknown value:
  fail safely or fall back to Nemotron with a clear diagnostic message

Use a small provider factory or runtime configuration type.

Do not place model-selection logic inside SessionCoordinator.

Do not modify the ASRProvider protocol unless compilation proves it necessary.

## Runtime Wiring

Find the exact production location where MLXAudioSTTProvider is currently instantiated.

Replace direct construction with the smallest possible factory or configuration boundary.

The factory must return:

* MLXAudioSTTProvider for the existing default path
* Qwen3ASRProvider for the explicit Qwen environment override

Requirements:

1. SessionCoordinator must continue receiving an injected ASRProvider.
2. Existing Nemotron behavior must remain unchanged.
3. The selected model must be recorded in diagnostics.
4. Do not log audio or transcript text.
5. A missing or invalid Qwen model must produce a clear recoverable error.
6. The app must not silently download a model during startup.
7. The app must use the already installed canonical Qwen directory.
8. No model selection UI is required.

## Runtime Metrics

Add lightweight timing measurements around:

* model load
* warmup
* transcription
* delivery

Record duration only.

Do not record:

* audio data
* transcript text
* user application contents

Use the existing diagnostics mechanism where appropriate.

The timing output must identify the selected model.

## Metal Runtime Investigation

Investigate the previous:

Failed to load the default metallib

Do not automatically classify it as an unavoidable XCTest limitation.

Determine:

1. Whether the error occurs only in swift test.
2. Whether it occurs in xcodebuild test.
3. Whether it occurs in the real VoiceDock.app process.
4. Whether required MLX resource bundles exist in the built application.
5. Whether the application contains or can resolve the required metallib resources.
6. Whether a standalone Swift test executable would provide additional useful evidence.

Do not upgrade MLX dependencies.

Do not copy private package resources manually unless source evidence proves that this is required.

The real VoiceDock.app process is the authoritative runtime test for this phase.

## Automated Tests

Add deterministic tests for:

1. No environment variable selects Nemotron.
2. Qwen environment value selects Qwen3ASRProvider.
3. Unknown environment value follows the documented safe behavior.
4. Qwen provider receives the canonical model path.
5. Existing provider injection remains functional.
6. SessionCoordinator tests remain unchanged and passing.

Tests must not load the real model unless explicitly opt-in.

## Build Verification

Run:

* swift build
* swift test
* xcodegen generate
* xcodebuild Debug build
* xcodebuild Debug test
* xcodebuild Release build
* git diff --check

Also run any existing:

* Info.plist lint
* codesign verification

Record exact commands and results.

## Real Application Launch

Locate the built VoiceDock.app executable.

Provide an exact command that launches the application process with Qwen selected, following this form:

VOICEDOCK_ASR_MODEL=qwen3-0.6b-6bit "/absolute/path/to/VoiceDock.app/Contents/MacOS/VoiceDock"

Do not assume the build path. Find and report the actual path.

Before launch:

1. Ensure no previous VoiceDock instance is running.
2. Confirm the canonical Qwen model validates successfully.
3. Confirm the environment override is visible to the process.
4. Confirm diagnostics identify Qwen as the selected provider.

Launch the app and inspect startup diagnostics.

Automated runtime success requires:

1. Application launches without crashing.
2. Qwen provider is selected.
3. Model load completes.
4. Warmup completes.
5. Menu bar interface remains responsive.
6. No metallib error occurs in the application process.

Real microphone transcription remains an owner-operated physical test.

## Owner Physical Test Checklist

Prepare a concise checklist for the owner:

1. English:
   "Today I am testing VoiceDock with a local speech recognition model."

2. Mandarin:
   "今天我正在测试本地语音识别模型的速度和准确性。"

3. Mixed:
   "今天我们测试 VoiceDock 的 local ASR model，看一下 response time。"

4. Technical:
   "The Qwen model runs locally on Apple Silicon using MLX."

5. Short command:
   "Open the settings and start recording."

For each phrase, record:

* recognized text
* obvious recognition errors
* recording duration
* transcription duration
* release-to-paste duration
* whether the UI remained responsive

Transcript text may be manually recorded in the owner test report. Production diagnostic logs must not store transcript contents.

## Documentation

Create:

docs/QWEN3_ASR_PHASE2B_RUNTIME_REPORT.md

Include:

1. Files changed
2. Provider selection architecture
3. Environment variable behavior
4. Exact real application launch command
5. MLX resource and metallib findings
6. Automated gate results
7. Whether the app loaded Qwen successfully
8. Whether warmup completed
9. Timing results available before microphone testing
10. Owner physical test checklist
11. Remaining conditions before switching the default model

Correct any inaccurate Phase 2A statement that says complete Qwen inference passed.

Do not rewrite historical evidence. Clearly distinguish:

* installation validation passed
* real inference pending or passed

## Restrictions

* Do not change the default model to Qwen.
* Do not delete Nemotron.
* Do not move Nemotron.
* Do not upgrade dependencies.
* Do not modify the app icon.
* Do not add model selection UI.
* Do not redesign SessionCoordinator.
* Do not log transcripts.
* Do not commit.
* Do not push.
* Do not create a pull request.
* Do not output VOICEDOCK_COMPLETE.
* Do not claim physical microphone testing passed without owner evidence.

## Completion Promise

Output exactly:

QWEN3_ASR_PHASE2B_RUNTIME_READY

Only when:

1. The app can be launched with the Qwen environment override.
2. VoiceDock.app selects Qwen.
3. Qwen model loading succeeds inside VoiceDock.app.
4. Qwen warmup succeeds inside VoiceDock.app.
5. No metallib error occurs in the real app process.
6. All automated gates pass.
7. Nemotron remains the no-override default.
8. The owner physical test checklist and exact launch command are documented.

Owner microphone transcription is not part of this completion promise.

If app loading or warmup fails, continue investigating and repairing within scope. Do not emit the completion promise.

