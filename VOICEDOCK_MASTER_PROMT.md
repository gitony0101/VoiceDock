# VoiceDock Product Specification

## Active Release

```text
VoiceDock Push-to-Talk MVP
```

This document defines the current product scope and acceptance criteria.

The active Smart Ralph specification controls task decomposition and implementation state.

## Product Vision

VoiceDock is a native macOS menu bar application that converts speech into text locally and inserts the result into the currently focused application.

The initial target is an Apple M1 Mac with 16 GB unified memory.

## Target User

A macOS user who frequently types in:

* ChatGPT
* Claude
* browsers
* editors
* terminals
* messaging applications
* productivity tools

The user wants fast local speech input without sending microphone audio to a cloud transcription service.

## Core User Problem

Typing long Chinese, English, or mixed technical content is slower and less natural than speaking.

Existing solutions may:

* upload audio to the cloud
* have weak mixed-language recognition
* require switching applications
* lack system-wide text insertion
* consume excessive resources

## MVP Decision Supported

VoiceDock helps the user decide and act on one question:

```text
Can I replace routine keyboard input with reliable local speech input on macOS?
```

## MVP User Flow

```text
launch VoiceDock
→ grant microphone permission
→ grant Accessibility permission
→ focus a text field in another application
→ press and hold or toggle the global push-to-talk shortcut
→ speak
→ stop recording
→ wait for local transcription
→ receive pasted text
→ optionally send Return
```

## Fixed Technology

```text
Platform: native macOS
Language: Swift 6
UI: SwiftUI with AppKit integration
Audio: AVFoundation and AVAudioEngine
Concurrency: Swift structured concurrency
Inference: native MLX
Package: Blaizzy/mlx-audio-swift
Swift product: MLXAudioSTT
Model: mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
Minimum OS: macOS 14
Architecture: arm64
```

The production application must not use Python, NeMo, Electron, Tauri, a subprocess, or a local inference server.

## MVP Functional Requirements

### Application

* Native macOS `.app`
* Menu bar presence
* No unnecessary primary window
* Clear quit action
* Clear status presentation

### Permissions

* Explain microphone permission before requesting it
* Explain Accessibility permission before requesting it
* Detect denied permission
* Provide understandable recovery guidance

### Push-to-Talk

* Provide one configurable or fixed global shortcut
* Start microphone capture reliably
* Stop microphone capture reliably
* Prevent overlapping recording sessions
* Support cancellation

### Audio

* Capture real microphone input
* Normalize to 16 kHz mono Float32
* Avoid blocking the audio callback
* Keep temporary audio bounded
* Do not persist audio by default

### ASR

* Load the Nemotron 3.5 ASR 0.6B 8-bit model
* Warm up without blocking the main actor
* Transcribe finalized utterances locally
* Handle load and inference failure
* Prevent concurrent model lifecycle races
* Test English
* Test Mandarin Chinese
* Test mixed Chinese-English technical speech

### Output

* Copy recognized text to the clipboard
* Paste recognized text into the focused application
* Optionally send Return
* Preserve the focused destination when practical
* Report Accessibility failure clearly

### User States

At minimum:

```text
idle
loading model
ready
listening
transcribing
delivering
permission required
failed
```

## Non-Functional Requirements

### Performance

Measure on the M1 16 GB baseline:

```text
application idle memory
model load time
warm-up time
audio duration
inference duration
real-time factor
speech-end-to-text latency
peak memory where measurable
```

The UI must remain responsive during loading and transcription.

### Privacy

Defaults:

```text
local audio processing
no telemetry
no transcript history
no cloud upload
no persistent raw audio
```

Network activity is allowed only for an explicit model download.

### Reliability

The application must handle:

* repeated push-to-talk sessions
* cancellation
* microphone access failure
* model load failure
* transcription failure
* Accessibility denial
* application quit during work
* invalid or empty recordings

## Explicitly Out of Scope

The active MVP does not include:

```text
VAD
automatic endpointing
pre-roll
partial streaming transcripts
continuous listening
model selection
model switching
model registry
managed model deletion
external model folders
AI assistant
LLM providers
conversation history
TTS
barge-in
cloud synchronization
App Store release
notarization without credentials
```

Do not implement these items in the current Smart Ralph specification.

## Architecture Boundary

```text
Menu Bar UI
→ SessionCoordinator
→ AudioCapture
→ AudioNormalizer
→ ASRProvider
→ TranscriptDestination
```

The UI owns presentation only.

The coordinator owns workflow and state.

Audio capture owns microphone lifecycle only.

The ASR provider owns model lifecycle and inference only.

Transcript destinations own clipboard and active-application delivery only.

## Automated Verification

Automated tests should cover:

```text
state transitions
push-to-talk lifecycle
audio normalization
empty-audio handling
cancellation
ASR provider lifecycle with mocks
clipboard delivery
paste command construction
permission state projection
failure recovery
```

Automated tests must not download the production model.

## Manual M1 Verification

Record evidence for:

```text
application launch
menu bar behavior
microphone permission
Accessibility permission
real microphone recording
English speech
Mandarin Chinese speech
mixed Chinese-English speech
clipboard output
paste into focused application
optional Return
rapid repeated utterances
model load time
inference latency
memory usage
```

## MVP Acceptance Criteria

The MVP is accepted only when:

1. The native macOS application builds in Debug.
2. The native macOS application builds in Release.
3. Automated tests pass.
4. The menu bar application launches.
5. The user can grant required permissions.
6. Push-to-talk records real microphone input.
7. Audio reaches the required 16 kHz mono Float32 format.
8. Nemotron runs locally through `MLXAudioSTT`.
9. English speech is transcribed.
10. Mandarin Chinese speech is transcribed.
11. Mixed Chinese-English speech is transcribed.
12. Text is copied to the clipboard.
13. Text is pasted into the focused application.
14. Optional Return works.
15. The interface remains responsive.
16. Performance measurements are recorded.
17. Privacy behavior is documented.
18. Known limitations are documented.
19. A runnable local release artifact is produced.
20. `DELIVERY_REPORT.md` contains truthful verification evidence.

## Future Releases

### Release 0.2 — Automatic Speech Segmentation

```text
pre-roll
VAD
endpointing
continuous utterance handling
```

### Release 0.3 — Streaming and Productization

```text
partial transcription
model download management
model registry
model switching
settings expansion
```

### Release 1.0 — AI Assistant

```text
LLM providers
conversation workflow
streamed AI responses
optional TTS
```

