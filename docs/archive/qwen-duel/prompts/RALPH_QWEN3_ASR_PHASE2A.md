# VoiceDock Qwen3-ASR Phase 2A Implementation

Read this file completely at the beginning of every iteration.

Also read these files completely before modifying code:

* AGENTS.md
* Package.swift
* project.yml
* docs/QWEN3_ASR_06B_6BIT_INVESTIGATION.md
* the existing ASRProvider implementation
* the existing MLXAudioSTTProvider implementation
* the existing SessionCoordinator implementation
* relevant existing tests
* DELIVERY_REPORT.md

Treat AGENTS.md as authoritative.

## Objective

Implement the first production-safe integration stage for:

mlx-community/Qwen3-ASR-0.6B-6bit

The canonical model directory must be:

~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/

Resolve this directory with FileManager's applicationSupportDirectory API. Do not construct it by manually expanding a tilde string.

The existing Nemotron provider and current runtime default must remain unchanged during this phase.

## Required Result

At completion, VoiceDock must have:

1. A deterministic application-support model storage abstraction.
2. A Qwen3ASRProvider conforming to the existing ASRProvider protocol.
3. A safe Qwen model installation and validation workflow.
4. Automated tests for model storage and provider behavior.
5. An opt-in real integration test capable of downloading, loading, warming up, and transcribing with the Qwen model.
6. All existing automated build and test gates passing.
7. No regression to the existing Nemotron implementation.
8. No app icon or branding modifications.
9. No switch of the production default model.

## Phase 2A.1: Inspect Before Editing

Before editing:

1. Confirm the actual source directory layout.
2. Confirm exact public APIs and signatures for:

   * Qwen3ASRModel.fromModelDirectory
   * Qwen3ASRModel.generate
   * Qwen3ASRModel.generateStream
   * HubClient or HubCache download APIs
3. Confirm the required files for the target Hugging Face model.
4. Inspect current VoiceDockError cases.
5. Inspect how production dependencies are injected.
6. Inspect Package.swift exclusions and Xcode target membership.

Do not assume paths proposed in the investigation report are identical to the repository layout. Use the actual repository structure.

## Phase 2A.2: Model Descriptor

Add a small model descriptor type for the target model.

It must include at least:

* stable identifier
* display name
* Hugging Face repository ID
* canonical directory name
* model family
* expected required files

For this phase, support:

* Qwen3-ASR-0.6B-6bit
* the existing Nemotron model as metadata only if useful

Avoid building a large generic plugin framework.

## Phase 2A.3: Model Storage

Implement a model storage abstraction.

Required responsibilities:

1. Resolve:

   FileManager applicationSupportDirectory
   / VoiceDock
   / Models
   / Qwen3-ASR-0.6B-6bit

2. Create the directory hierarchy when needed.

3. Determine whether the model is validly installed.

4. Validate at least:

   * config.json exists and parses as JSON
   * one or more non-empty safetensors files exist
   * tokenizer_config.json exists
   * merges.txt exists
   * vocab.json exists
   * preprocessor_config.json exists
   * generation_config.json exists
   * model.safetensors.index.json is validated when present

5. Reject zero-byte files.

6. Reject incomplete installation directories.

7. Expose the canonical model URL.

8. Support deleting the installed Qwen model.

9. Support returning the URL that the UI can later reveal in Finder.

Do not implement the Finder UI in this phase.

Make the base Application Support directory injectable in tests so tests do not write to the user's real Library directory.

## Phase 2A.4: Safe Model Installation

Implement a safe installer using the already resolved Swift package dependencies.

Restrictions:

* Do not use Python.
* Do not use Conda.
* Do not use Node.
* Do not use curl shell commands from production code.
* Do not add an HTTP subprocess.
* Do not use the default global Hugging Face cache as the final model location.
* Do not leave a second complete Qwen model copy in ~/.cache/huggingface.
* Do not write model files into the repository.
* Do not write model files into DerivedData.
* Do not write model files into the .app bundle.

Installation process:

1. Create a unique staging directory under:

   ~/Library/Application Support/VoiceDock/Temporary/

2. Download the complete Hugging Face repository snapshot into a temporary custom cache or staging location.

3. Resolve regular model files from the downloaded snapshot.

4. Copy or move all required model files into a staging model directory.

5. Ensure the final staging directory does not depend on symlinks pointing outside the staging directory.

6. Validate the staging model directory.

7. Atomically move or replace it at:

   ~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/

8. Delete the temporary Hugging Face cache and staging artifacts after success.

9. Delete incomplete staging artifacts after failure or cancellation.

10. Never remove an already valid installed model because a new download failed.

11. Prevent two simultaneous installations of the same model.

Use actor isolation or another concurrency-safe single-flight design.

Do not log credentials, audio, transcripts, or model file contents.

## Phase 2A.5: Qwen3ASRProvider

Add Qwen3ASRProvider as an actor conforming to the existing ASRProvider protocol.

Required behavior:

### load()

* Validate the canonical model directory.

* Load using:

  Qwen3ASRModel.fromModelDirectory(modelDirectory)

* Avoid loading twice.

* Return a clear VoiceDockError when the model is missing or invalid.

### warmup()

* Require a loaded model.
* Perform a short deterministic 16 kHz silence warmup.
* Avoid recording or persisting generated text.
* Handle warmup failure with a clear recoverable error.

### transcribe(audio:)

* Require a loaded model.
* Reject empty input with an appropriate error or safe empty response consistent with existing project behavior.
* Use the non-streaming generate(audio:) API for this Push-to-Talk phase.
* Leave language unspecified so Qwen can perform automatic language handling.
* Return trimmed transcript text.
* Do not log the transcript.

### unload()

* Release the model reference.
* Release relevant MLX resources when supported safely.
* Remain safe when called more than once.

Do not modify ASRProvider unless the existing protocol genuinely prevents implementation.

Do not modify SessionCoordinator.

## Phase 2A.6: Testability

Do not make unit tests load the real 862 MB model.

Introduce the minimum abstraction needed to test provider lifecycle behavior without loading real MLX weights.

Tests must cover at least:

1. Canonical directory construction.
2. Custom test Application Support directory injection.
3. Valid model directory detection.
4. Missing required file detection.
5. Zero-byte safetensors rejection.
6. Invalid config.json rejection.
7. Incomplete staging directory cleanup.
8. Failed installation preserving an existing valid model.
9. Concurrent installation requests do not create two active downloads.
10. Qwen provider load lifecycle.
11. Qwen provider warmup lifecycle.
12. Qwen provider transcription lifecycle.
13. Qwen provider unload lifecycle.
14. Loading failure when the model directory is missing.
15. Existing Nemotron tests remain unchanged and passing.

Use deterministic temporary fixtures.

## Phase 2A.7: Opt-in Real Integration Test

Add an integration test or dedicated validation entry point that is skipped by default.

It may run only when an explicit environment variable is set, for example:

VOICEDOCK_RUN_QWEN_INTEGRATION=1

The real integration flow must:

1. Install or reuse the Qwen model at the canonical Application Support location.
2. Validate the installed model.
3. Load Qwen3ASRProvider.
4. Warm up the model.
5. Transcribe a deterministic local fixture or generated valid audio fixture.
6. Assert the operation completes without crashing.
7. Assert the returned result is structurally valid.
8. Record timing information without recording transcript contents.
9. Unload the model.

The ordinary swift test and xcodebuild test commands must not download a model.

## Phase 2A.8: Runtime Wiring

Do not switch the application default provider.

Do not modify SessionCoordinator.

If a small provider factory or candidate configuration is required for later integration, add it without changing the current production selection.

The app must continue to launch with the existing Nemotron provider after this phase.

## Phase 2A.9: Documentation

Create or update:

docs/QWEN3_ASR_PHASE2A_IMPLEMENTATION_REPORT.md

Include:

1. Files added and modified.
2. Canonical model path.
3. Download architecture.
4. Validation rules.
5. How duplicate storage was prevented.
6. How to run ordinary tests.
7. How to run the opt-in real integration test.
8. Real model download result.
9. Real model directory size.
10. Model loading and warmup result.
11. Known limitations.
12. Exact next step for physical speech testing and default switching.

Update architecture documentation only where necessary to prevent it from becoming inaccurate.

Do not declare VoiceDock complete.

## Required Verification

Run all applicable commands from the repository root.

At minimum:

* swift build
* swift test
* xcodegen generate
* xcodebuild Debug build
* xcodebuild Debug test
* xcodebuild Release build
* Info.plist validation if already part of the project workflow
* codesign verification if already part of the project workflow

Then run the opt-in Qwen integration test once.

Confirm:

1. The Qwen model exists at the canonical Application Support path.
2. The final canonical directory is valid.
3. Temporary download directories are removed.
4. No complete Qwen copy remains in the default ~/.cache/huggingface location as a result of this implementation.
5. Existing Nemotron files remain untouched.
6. The production default remains Nemotron.
7. git status contains only intended source, test, and documentation changes.
8. No model files are tracked by Git.

## Hard Restrictions

* Do not delete or move the existing Nemotron model.
* Do not modify the current production default model.
* Do not modify SessionCoordinator.
* Do not upgrade mlx-audio-swift.
* Do not upgrade mlx-swift.
* Do not modify the app icon.
* Do not modify branding.
* Do not add model selection UI.
* Do not add Python, Node, Docker, Conda, Rosetta, HTTP subprocesses, or local servers.
* Do not commit.
* Do not push.
* Do not create a pull request.
* Do not output VOICEDOCK_COMPLETE.

## Completion Promise

Output exactly:

QWEN3_ASR_PHASE2A_VERIFIED

Only when:

1. All required code is implemented.
2. All ordinary automated gates pass.
3. The opt-in real Qwen integration test passes.
4. The model is installed at the canonical Application Support path.
5. Temporary files and duplicate Qwen cache copies are cleaned.
6. Nemotron remains operational and unchanged.
7. The production default remains Nemotron.
8. The implementation report contains current evidence.

If any condition remains incomplete, do not output the completion promise. Continue investigating and repairing within the allowed scope.

