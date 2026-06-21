# VoiceDock Engineering Constitution

## Purpose

This file defines the durable engineering rules for VoiceDock.

It applies to every coding agent, Smart Ralph task, implementation change, test, and release operation.

## Source of Truth

Use this priority order:

1. Active Smart Ralph task and acceptance criteria under `specs/`
2. Active Smart Ralph progress and state
3. This file
4. `VOICEDOCK_MASTER_PROMPT.md`
5. Current verified code
6. Git history for reference only

Git history must not override the intentional clean reset.

Do not restore deleted generated code merely because it previously existed.

## Current Mission

Deliver a native macOS Push-to-Talk speech-input application for Apple Silicon.

Primary MVP flow:

```text
global push-to-talk
→ microphone capture
→ 16 kHz mono Float32 audio
→ local Nemotron ASR
→ transcript
→ clipboard
→ focused application paste
→ optional Return
```

Baseline hardware:

```text
Apple M1
16 GB unified memory
macOS 14 or later
arm64
```

## Fixed MVP Technology

Use:

```text
Swift 6
SwiftUI
AppKit
AVFoundation
AVAudioEngine
Swift structured concurrency
Xcode macOS App target
Blaizzy/mlx-audio-swift
MLXAudioSTT
mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
```

The distributed application must not require:

```text
Python
Conda
Node.js
Docker
Rosetta
local HTTP servers
ASR subprocesses
```

Python may be used only as a disposable model-validation tool. It must not become part of the application architecture or release artifact.

## Current MVP Scope

Required:

```text
native menu bar application
microphone permission handling
Accessibility permission handling
global push-to-talk
real microphone capture
16 kHz mono Float32 normalization
local Nemotron transcription
English transcription
Mandarin Chinese transcription
mixed Chinese-English transcription
clipboard output
paste into focused application
optional Return
loading, listening, transcribing, delivering, and failure states
Debug build
Release build
automated tests
manual M1 verification
delivery documentation
```

Explicitly excluded from this Smart Ralph specification:

```text
VAD
automatic endpointing
pre-roll
partial streaming transcripts
model selection
model switching
model registry
managed model downloads
external model folders
AI assistant
chat providers
conversation history
TTS
signing and notarization unless credentials are available
```

Do not widen scope until the Push-to-Talk MVP is verified.

## Architecture

Use this dependency direction:

```text
Menu Bar UI
→ SessionCoordinator
→ AudioCapture
→ AudioNormalizer
→ ASRProvider
→ TranscriptDestination
```

Rules:

1. SwiftUI views send intents and observe state.
2. Views do not instantiate models or infrastructure services.
3. `SessionCoordinator` owns application workflow and state transitions.
4. Core Audio callbacks remain non-blocking.
5. Audio callbacks do not perform inference, file I/O, networking, logging, or blocking synchronization.
6. Audio buffers crossing concurrency boundaries must have explicit ownership.
7. ASR model loading, warm-up, transcription, cancellation, and unloading must be serialized.
8. ASR providers do not paste text.
9. Transcript destinations do not capture audio.
10. Use initializer injection.
11. Avoid mutable global service locators.
12. Do not create speculative abstractions for future releases.
13. Do not create duplicate physical source trees.
14. Keep one large ASR model resident on the M1 baseline.

## ASR Boundary

Keep the shared interface model-agnostic.

A suitable initial shape is:

```swift
protocol ASRProvider: Actor {
    func load() async throws
    func warmup() async throws
    func transcribe(audio: [Float]) async throws -> ASRResult
    func unload() async
}
```

The implementation may evolve from verified requirements, but shared interfaces must not expose unnecessary Nemotron internals.

## Audio Contract

Canonical ASR input:

```text
sample rate: 16,000 Hz
channels: mono
sample type: Float32
```

Requirements:

* no blocking work in the audio callback
* explicit start and stop lifecycle
* deterministic normalization
* cancellation on stop and quit
* clear microphone-device failure handling
* no private audio persistence by default

## Privacy and Security

Defaults:

```text
local microphone processing
no telemetry
no transcript history
no cloud upload
no background network activity except explicit model download
```

Requirements:

* explain permissions before requesting them
* never log private transcripts or raw audio
* never commit credentials or private audio
* never commit model weights
* never execute downloaded repository scripts or remote code
* validate model files and paths
* keep downloaded models outside the signed application bundle

## Loop Engineering Contract

Every task follows:

```text
observe
→ define one measurable task
→ implement
→ run focused verification
→ run applicable repository verification
→ review the diff
→ repair failures
→ commit verified work
→ update progress
→ continue
```

Rules:

1. Work on one active task only.
2. Define measurable acceptance criteria before editing.
3. Do not weaken acceptance criteria to make work pass.
4. Run all builds and tests in the foreground.
5. Preserve real command exit codes.
6. A failed verification blocks unrelated feature expansion.
7. Stay within the current task until it is green or coherently re-scoped.
8. Commit only verified work.
9. Keep commits focused and reviewable.
10. Continue automatically after each green task.
11. Do not ask for routine implementation approval.

## Hard Prohibitions

Never:

* restore the intentionally deleted implementation without a task-specific justification
* push to GitHub or another remote
* create a remote repository
* force-push
* run build or test commands with `&`, `nohup`, `disown`, or `bg`
* append `|| true`, `|| echo`, or equivalent failure-masking constructs
* manually link XCTest, Swift Testing, private frameworks, or CommandLineTools framework paths
* claim a build or test passed unless it ran successfully
* claim a manual test passed unless it was actually performed
* commit `DerivedData`, `.build`, downloaded models, private audio, credentials, logs containing transcripts, or personal absolute paths
* introduce VAD, streaming, model management, AI, or TTS into the active MVP
* spend delivery time debugging optional tooling such as Hookify

## Dependencies

Before adding a dependency:

1. Confirm the capability is required by the active task.
2. Confirm arm64 macOS support.
3. Review license and maintenance status.
4. Record why Apple frameworks are insufficient.
5. Pin the dependency to a verified tag or exact revision.
6. Add it only in the task that first uses it.

Do not depend on a floating branch for the release build.

## Build and Verification

The primary project is an Xcode macOS application.

Normal checks include:

```bash
xcodebuild -list -project VoiceDock.xcodeproj

xcodebuild \
  -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -destination 'platform=macOS' \
  test

git diff --check
```

Use Swift Package Manager commands only when a real reusable Swift package exists.

Unit tests must not download production models.

Use mocks and small deterministic fixtures for ordinary automated tests.

Production-model and microphone checks must be recorded as separate integration or manual evidence.

## Git Discipline

* Preserve local checkpoints before destructive changes.
* Commit each verified coherent task.
* Do not push.
* Do not create a remote.
* Do not rewrite unrelated history.
* Do not mass-format unrelated files.
* Keep the working tree understandable.

## Owner-Only Blockers

Pause only when the owner must personally:

* approve a macOS permission prompt
* provide signing or notarization credentials
* provide a required private credential
* resolve a licensing decision
* perform real microphone speech validation
* make a material product decision not covered by the specification

Before stopping:

1. Complete all unblocked work.
2. Record what was completed.
3. Explain the blocker.
4. State the exact owner action required.
5. State how to resume.

## Completion

The MVP is complete only when verified evidence shows that a user can:

```text
launch the native menu bar application
grant required permissions
trigger push-to-talk
speak into a real microphone
run Nemotron locally through MLXAudioSTT
receive English, Mandarin, and mixed-language transcripts
copy the transcript
paste it into the focused application
optionally send Return
```

Completion also requires:

```text
passing automated tests
successful Debug build
successful Release build
manual M1 test evidence
documented architecture
documented privacy behavior
documented setup and usage
documented limitations
runnable local release artifact
DELIVERY_REPORT.md
final local commit
```

