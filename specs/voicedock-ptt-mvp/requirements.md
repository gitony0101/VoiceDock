# VoiceDock Push-to-Talk MVP Requirements

## Overview

VoiceDock is a native macOS menu bar application that delivers push-to-talk speech-to-text input for Apple Silicon Macs. Users press a global hotkey, speak, and receive transcribed text pasted directly into their focused application. All processing runs locally using the Nemotron 3.5 ASR model—no cloud, no telemetry, no transcript storage.

## User Stories

### US-1: Launch and Status Visibility

**As a** user
**I want to** launch VoiceDock and see its status in the menu bar at all times
**So that** I know the application is running and ready to transcribe

**Acceptance Criteria:**
- [ ] AC-1.1: Application launches without error on macOS 14+ arm64
- [ ] AC-1.2: Menu bar icon displays immediately after launch
- [ ] AC-1.3: Menu bar status indicator reflects current application state (idle, loading, listening, transcribing, delivering, error)
- [ ] AC-1.4: Application runs in background without requiring foreground focus

### US-2: Microphone Permission

**As a** user
**I want to** grant microphone permission with a clear explanation of why it's needed
**So that** I understand how my audio is being used and can trust the application

**Acceptance Criteria:**
- [ ] AC-2.1: Application requests microphone permission on first launch
- [ ] AC-2.2: Info.plist contains `NSMicrophoneUsageDescription` explaining audio is processed locally for transcription
- [ ] AC-2.3: User is shown a pre-permission explanation before the system dialog appears
- [ ] AC-2.4: Application handles permission denial gracefully with instructions to enable in System Settings
- [ ] AC-2.5: No audio is captured before permission is granted

### US-3: Accessibility Permission for Paste

**As a** user
**I want to** grant Accessibility permission so VoiceDock can paste transcribed text into other applications
**So that** I don't have to manually copy and paste transcripts

**Acceptance Criteria:**
- [ ] AC-3.1: Application requests Accessibility permission on first launch
- [ ] AC-3.2: Info.plist contains `NSAppleEventsUsageDescription` explaining permission is used to paste text
- [ ] AC-3.3: User is shown a pre-permission explanation before the system dialog appears
- [ ] AC-3.4: Application detects permission denial via `AXIsProcessTrusted()`
- [ ] AC-3.5: Application provides a deep link to System Settings → Privacy → Accessibility
- [ ] AC-3.6: Application degrades gracefully to clipboard-only mode if permission is denied

### US-4: Global Push-to-Talk Trigger

**As a** user
**I want to** press a global hotkey to start recording from anywhere on my Mac
**So that** I can capture speech without switching to the VoiceDock app

**Acceptance Criteria:**
- [ ] AC-4.1: Configurable hotkey triggers recording start (default: Command+Space)
- [ ] AC-4.2: Hotkey works when VoiceDock is not the frontmost application
- [ ] AC-4.3: Hotkey is released to stop recording (push-to-talk behavior)
- [ ] AC-4.4: Visual feedback indicates recording is active
- [ ] AC-4.5: Hotkey cannot be triggered while a previous transcription is in progress (or cancels current session)

### US-5: Real Microphone Capture

**As a** user speaking into my Mac's microphone
**I want to** have my speech captured in real-time
**So that** the transcription reflects what I actually said

**Acceptance Criteria:**
- [ ] AC-5.1: Application captures audio from the system default microphone
- [ ] AC-5.2: Audio capture starts within 100ms of hotkey press
- [ ] AC-5.3: Audio capture stops within 100ms of hotkey release
- [ ] AC-5.4: No audio is persisted to disk during or after capture
- [ ] AC-5.5: Audio buffer is cleared after transcription completes or fails
- [ ] AC-5.6: Application handles microphone disconnection with a clear error message
- [ ] AC-5.7: Audio capture uses AVAudioEngine with non-blocking tap callback

### US-6: Audio Format Normalization

**As a** user
**I want to** have my audio converted to the correct format for the ASR model
**So that** transcription works regardless of microphone hardware settings

**Acceptance Criteria:**
- [ ] AC-6.1: Audio is converted to 16,000 Hz sample rate
- [ ] AC-6.2: Audio is converted to mono (single channel)
- [ ] AC-6.3: Audio samples are Float32 format
- [ ] AC-6.4: Normalization is deterministic (same input produces same output)
- [ ] AC-6.5: Empty audio input returns nil or empty result, does not crash
- [ ] AC-6.6: Audio conversion completes before ASR invocation

### US-7: Local ASR Transcription

**As a** user
**I want to** have my speech transcribed locally using the Nemotron ASR model
**So that** I get accurate English, Mandarin, and mixed-language transcripts without cloud processing

**Acceptance Criteria:**
- [ ] AC-7.1: Application loads Nemotron 3.5 ASR 0.6B 8-bit model on first transcription
- [ ] AC-7.2: Model download from Hugging Face is automatic (via mlx-audio-swift)
- [ ] AC-7.3: Model loading shows progress indicator to user
- [ ] AC-7.4: Model warmup completes before first transcription
- [ ] AC-7.5: English speech produces accurate English transcript
- [ ] AC-7.6: Mandarin Chinese speech produces accurate Chinese transcript
- [ ] AC-7.7: Mixed Chinese-English speech produces coherent mixed-language transcript
- [ ] AC-7.8: Model inference runs on local GPU/Neural Engine (no external process)
- [ ] AC-7.9: ASR interface accepts raw `[Float]` audio array as input
- [ ] AC-7.10: ASR model lifecycle (load, warmup, transcribe, unload) is serialized through actor isolation

### US-8: Clipboard Output

**As a** user
**I want to** have my transcript copied to the clipboard
**So that** I can paste it anywhere if automatic paste fails

**Acceptance Criteria:**
- [ ] AC-8.1: Transcript is copied to system clipboard after successful transcription
- [ ] AC-8.2: Clipboard contains only the transcript text, no metadata or formatting
- [ ] AC-8.3: Clipboard operation completes before paste simulation begins
- [ ] AC-8.4: Failed clipboard copy returns error state with user feedback

### US-9: Automatic Paste and Return

**As a** user
**I want to** have my transcript pasted into my focused application automatically
**So that** I can continue working without manual intervention

**Acceptance Criteria:**
- [ ] AC-9.1: Transcript is pasted into the application holding keyboard focus
- [ ] AC-9.2: Paste is simulated via Command+V CGEvent
- [ ] AC-9.3: Optional Return key press is configurable (default: enabled)
- [ ] AC-9.4: Return key is simulated via CGEvent after paste
- [ ] AC-9.5: Paste and Return require Accessibility permission
- [ ] AC-9.6: Paste fails gracefully if Accessibility permission is denied (clipboard-only mode)
- [ ] AC-9.7: TranscriptDestination does not capture or process audio

### US-10: State Feedback and Error Handling

**As a** user
**I want to** see clear feedback about what VoiceDock is doing at all times
**So that** I know whether to wait, retry, or troubleshoot

**Acceptance Criteria:**
- [ ] AC-10.1: UI displays "Loading" state while model downloads/initializes
- [ ] AC-10.2: UI displays "Listening" state during audio capture
- [ ] AC-10.3: UI displays "Transcribing" state during model inference
- [ ] AC-10.4: UI displays "Delivering" state during paste operation
- [ ] AC-10.5: UI displays "Idle" state when ready for new input
- [ ] AC-10.6: UI displays "Error" state with actionable message on failure
- [ ] AC-10.7: Error states include retry action where applicable
- [ ] AC-10.8: Model download failure provides retry option and fallback instructions
- [ ] AC-10.9: Permission denial provides deep link to System Settings

## Functional Requirements

### Application Lifecycle

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1.1 | Application is a native Xcode macOS App target | High | Builds via `xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' build` |
| FR-1.2 | Application runs as menu bar agent (no main window) | High | Menu bar icon displays; no dock icon unless explicitly shown |
| FR-1.3 | Application uses SwiftUI for views, AppKit for menu bar integration | High | `@main` SwiftUI app with `NSStatusItem` and `NSPopover` |
| FR-1.4 | SessionCoordinator owns application workflow state | High | Single source of truth for state machine transitions |
| FR-1.5 | SwiftUI views observe state via `@MainActor` published properties | High | Views do not instantiate models or infrastructure services |
| FR-1.6 | Release build succeeds without errors | High | Build completes with zero warnings (or warnings treated as errors if configured) |

### Permissions

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-2.1 | Microphone permission is requested with usage description | High | `NSMicrophoneUsageDescription` present in Info.plist |
| FR-2.2 | Accessibility permission is requested with usage description | High | `NSAppleEventsUsageDescription` present in Info.plist |
| FR-2.3 | Permission status is checked before each operation requiring it | High | `AXIsProcessTrusted()` returns false triggers permission prompt |
| FR-2.4 | Permission denial is handled gracefully with settings deep link | Medium | User can navigate to System Settings to enable permission |

### Push-to-Talk

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-3.1 | Global hotkey detection works when app is backgrounded | High | Carbon `RegisterEventHotKey` or tested alternative |
| FR-3.2 | Hotkey press starts audio capture | High | Latency from keypress to capture start < 100ms |
| FR-3.3 | Hotkey release stops audio capture | High | Latency from key release to capture stop < 100ms |
| FR-3.4 | Push-to-talk cannot be triggered during ongoing transcription | High | State machine prevents re-entrant recording |
| FR-3.5 | Hotkey is configurable (stored in user defaults) | Medium | User can change hotkey combination |

### Audio Capture

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-4.1 | Audio input uses AVAudioEngine with input node tap | High | `engine.inputNode.installTap(onBus: 0, ...)` |
| FR-4.2 | Audio session category is `.playAndRecord` with `.measurement` mode | High | Minimal audio processing, low latency |
| FR-4.3 | Audio callback dispatches work to background serial queue | High | Tap block returns immediately; no blocking work on audio thread |
| FR-4.4 | Audio callback performs no inference, file I/O, networking, or logging | High | Code review verification; static analysis if available |
| FR-4.5 | Audio buffers have explicit ownership when crossing concurrency boundaries | High | No data races; actor isolation or explicit queue dispatch |
| FR-4.6 | Microphone disconnection is detected and reported | Medium | Error state shown if input device becomes unavailable |

### Audio Normalization

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-5.1 | Output format is 16 kHz sample rate | High | `AVAudioFormat(sampleRate: 16_000, ...)` |
| FR-5.2 | Output is mono (1 channel) | High | `AVAudioFormat(channels: 1, ...)` |
| FR-5.3 | Output sample type is Float32 | High | `AVAudioFormat(commonFormat: .pcmFormatFloat32, ...)` |
| FR-5.4 | Conversion is deterministic (same input → same output) | Medium | Unit test with fixed input produces identical output |
| FR-5.5 | Empty input returns nil or empty result without crash | Medium | Unit test with zero-length buffer |

### ASR Transcription

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-6.1 | ASRProvider protocol is model-agnostic | High | Protocol defined as `Actor` with `load`, `warmup`, `transcribe`, `unload` |
| FR-6.2 | ASRProvider implementation uses MLXAudioSTT with Nemotron 0.6B 8-bit | High | `GLMASRModel.fromPretrained("mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")` |
| FR-6.3 | Model download is automatic via `fromPretrained` | High | No manual download step required |
| FR-6.4 | Model warmup completes before first transcription | High | Warmup call after load, before first `transcribe` |
| FR-6.5 | Transcribe accepts `[Float]` audio array | High | Method signature `transcribe(audio: [Float]) async throws -> ASRResult` |
| FR-6.6 | Model lifecycle is serialized through actor isolation | High | Concurrent calls to transcribe are queued, not interleaved |
| FR-6.7 | English speech transcription works | High | Manual verification with English speech sample |
| FR-6.8 | Mandarin Chinese speech transcription works | High | Manual verification with Mandarin speech sample |
| FR-6.9 | Mixed Chinese-English speech transcription works | High | Manual verification with code-switched speech sample |
| FR-6.10 | ASRProvider does not paste text | High | Single responsibility; paste is TranscriptDestination concern |

### Text Delivery

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-7.1 | Transcript is copied to system clipboard | High | `NSPasteboard.general.setString(_:forType:)` |
| FR-7.2 | Paste is simulated via CGEvent Command+V | High | `CGEvent(keyboardEventSource:..., virtualKey: kVK_ANSI_V, ...)` with `.maskCommand` |
| FR-7.3 | Optional Return key is simulated after paste | Medium | `CGEvent(keyboardEventSource: ..., virtualKey: kVK_Return, ...)` |
| FR-7.4 | Return key behavior is configurable | Medium | User setting enables/disables auto-Return |
| FR-7.5 | TranscriptDestination does not capture audio | High | No audio input dependencies in transcript delivery code |
| FR-7.6 | Paste fails gracefully without Accessibility permission | Medium | Degrades to clipboard-only with user notification |

## Non-Functional Requirements

### Performance Targets

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1.1 | Hotkey-to-capture latency | Time from keypress to audio tap start | < 100 ms |
| NFR-1.2 | Capture-to-transcribe latency | Time from key release to `transcribe()` call | < 500 ms |
| NFR-1.3 | Transcription duration | Time for 10 seconds of speech to transcribe on M1 | < 5 seconds |
| NFR-1.4 | Total flow time | Time from key release to paste complete | < 10 seconds for 10s speech |
| NFR-1.5 | Memory footprint | Peak RAM usage during transcription on M1 16 GB | < 2 GB (model + runtime) |
| NFR-1.6 | Audio callback execution | Time spent in tap callback | < 5 ms per 10 ms buffer |
| NFR-1.7 | Model size on disk | Downloaded Nemotron 0.6B 8-bit | ~756 MB |

### Privacy Constraints

| ID | Requirement | Verification |
|----|-------------|--------------|
| NFR-2.1 | No telemetry | Code review confirms no network calls except model download |
| NFR-2.2 | No transcript history | No persistent storage of transcripts |
| NFR-2.3 | No cloud upload | All inference runs locally; no HTTP calls during transcription |
| NFR-2.4 | No private audio persistence | Audio buffers cleared after transcription; no file writes |
| NFR-2.5 | Audio processed locally | Model inference via MLXAudioSTT on local GPU/Neural Engine |
| NFR-2.6 | Permission explanation provided | Info.plist and UI explain what data is used and why |

### Reliability Requirements

| ID | Requirement | Verification |
|----|-------------|--------------|
| NFR-3.1 | No crashes on empty audio input | Unit test with zero-length buffer |
| NFR-3.2 | No crashes on model load failure | Mock ASR load failure; graceful error handling |
| NFR-3.3 | No crashes on microphone disconnection | Simulate device unplugging during capture |
| NFR-3.4 | No data races across concurrency boundaries | Actor isolation review; Swift Concurrency analyzer |
| NFR-3.5 | No memory leaks | Instruments Leaks profile on full recording-transcribe-paste cycle |
| NFR-3.6 | Graceful degradation without Accessibility permission | Clipboard-only mode functions correctly |
| NFR-3.7 | No blocking work on audio thread | Code review of tap callback; stack trace analysis |

### Compatibility Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-4.1 | Minimum macOS version | 14.0+ |
| NFR-4.2 | CPU architecture | arm64 (Apple Silicon) only |
| NFR-4.3 | Swift language version | Swift 6 (or Swift 5.9+ if mlx-audio-swift compatibility requires) |
| NFR-4.4 | Xcode version | 15+ |
| NFR-4.5 | Baseline hardware | Apple M1, 16 GB unified memory |

## Interface Requirements

### Menu Bar UI States

| State | Description | Visual Indicator |
|-------|-------------|------------------|
| Idle | Ready to record | Menu bar icon in default state |
| Loading | Model downloading or initializing | Spinner or progress indicator |
| Listening | Audio capture in progress | Animated "listening" indicator (e.g., waveform or pulse) |
| Transcribing | Model inference running | Spinner with "Transcribing..." label |
| Delivering | Pasting transcript | Brief "Delivering..." indicator |
| Error | Operation failed | Red icon with tooltip explaining error |

### Status Indicator Behavior

| ID | Requirement | Verification |
|----|-------------|--------------|
| IF-1.1 | State transitions are visible in menu bar | Manual observation during full workflow |
| IF-1.2 | State text is human-readable (no codes) | Copy review |
| IF-1.3 | Loading state shows progress if model download | Progress spinner or percentage |
| IF-1.4 | Error state includes actionable message | Error tooltips tested for clarity |
| IF-1.5 | Listening state has distinct animated indicator | Visual verification |

### Error Presentation

| ID | Requirement | Example Message |
|----|-------------|-----------------|
| IF-2.1 | Microphone permission denied | "VoiceDock needs microphone access. Open System Settings → Privacy → Microphone." |
| IF-2.2 | Accessibility permission denied | "VoiceDock needs Accessibility access to paste text. Open System Settings → Privacy → Accessibility." |
| IF-2.3 | Model download failed | "Could not download ASR model. Check internet connection and retry." |
| IF-2.4 | No microphone available | "No microphone detected. Connect a microphone and try again." |
| IF-2.5 | Transcription failed | "Transcription failed. Try speaking more clearly or retry." |
| IF-2.6 | Paste failed | "Could not paste text. Transcript copied to clipboard instead." |

## Dependencies

### External Packages

| Package | Pin | Product | Purpose |
|---------|-----|---------|---------|
| `https://github.com/Blaizzy/mlx-audio-swift.git` | `branch: "main"` (pin to verified commit during implementation) | `MLXAudioSTT` | ASR model loading and inference |

### Model Requirements

| Model | Source | Size | Purpose |
|-------|--------|------|---------|
| Nemotron 3.5 ASR 0.6B 8-bit | `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit` (Hugging Face) | ~756 MB | Speech-to-text inference |

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 14.0 | 14.0+ |
| CPU | Apple M1 | M1 Pro/Max/Ultra or later |
| Memory | 16 GB unified | 16 GB+ unified |
| Storage | 1 GB free (model + app) | 5 GB+ free |
| Xcode | 15 | 16 |
| Swift | 6 (or 5.9+ if compatibility requires) | 6 |

### Framework Dependencies

| Framework | Purpose |
|-----------|---------|
| SwiftUI | User interface |
| AppKit | Menu bar integration, popover, hotkey handling |
| AVFoundation | Audio capture (AVAudioEngine, AVAudioSession) |
| Carbon.HIToolbox | Global hotkey registration (optional, if used) |
| ApplicationServices | Accessibility permission check (`AXIsProcessTrusted`) |
| Quartz | CGEvent posting for paste/Return simulation |

## Out of Scope

The following capabilities are explicitly excluded from this MVP:

| Category | Excluded Items |
|----------|----------------|
| **Voice Activity Detection** | VAD, automatic speech detection, pre-roll capture |
| **Endpointing** | Automatic silence detection, automatic session end |
| **Streaming** | Partial transcripts during speech, real-time streaming output |
| **Model Management** | Model selection UI, model switching, model registry, managed downloads, external model folders |
| **AI Features** | AI assistant, chat providers, conversation history, LLM integration |
| **Audio Output** | Text-to-speech (TTS), audio playback, voice feedback |
| **Transcript Management** | Transcript history, saved transcripts, export, sharing |
| **Release Engineering** | Code signing and notarization (unless credentials provided by owner) |
| **Platform Support** | Intel Mac support, iOS/iPadOS version, Windows/Linux versions |
| **Cloud Features** | Cloud sync, backup, cross-device features, account system |

## Risks and Assumptions

### Technical Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | mlx-audio-swift Swift 6 incompatibility | HIGH | Verify during Package.swift setup; pin to known-good commit; fall back to Swift 5 mode if required |
| 2 | MLXAudioSTT API does not accept raw `[Float]` arrays (only file URLs) | MEDIUM | Wrap audio buffer in temporary file managed by AudioCapture; delete after transcription |
| 3 | Nemotron model exceeds memory budget on M1 16 GB baseline | MEDIUM | Measure with Instruments; optimize or document limitation |
| 4 | Audio callback blocking causes dropouts or glitches | HIGH | Strict non-blocking discipline; code review; profiling under load |
| 5 | Global hotkey unreliable when app backgrounded | MEDIUM | Prefer Carbon `RegisterEventHotKey` over NSEvent global monitor; test extensively |
| 6 | Mixed Chinese-English transcription quality inadequate | MEDIUM | Validate with real bilingual samples; document limitation if word error rate unacceptable |
| 7 | Model download fails or corrupts | LOW | Retry logic; SHA verification; manual download fallback with documented steps |
| 8 | Accessibility permission workflow confusing to users | MEDIUM | Clear pre-permission explanation; deep link to Settings; test UX with fresh install |

### Assumptions

| # | Assumption | Validation Plan |
|---|------------|-----------------|
| 1 | User has macOS 14+ on Apple Silicon | Document in requirements; no Intel support planned |
| 2 | User has stable internet for initial model download (~756 MB) | Document in setup instructions; provide manual download fallback |
| 3 | User has at least one working microphone | Test with built-in Mac microphone and common USB mics |
| 4 | mlx-audio-swift main branch is actively maintained | Monitor repository activity; pin to stable commit |
| 5 | Nemotron 0.6B 8-bit provides acceptable quality for short dictation | Manual M1 verification with real speech samples |
| 6 | User is comfortable granting Accessibility permission after explanation | Clear UX copy;Settings deep link |
| 7 | Target workflow is short-form dictation (messages, notes, commands), not long-form transcription | Keep MVP scope focused; document limitation |

### Open Questions

| # | Question | Resolution Needed By |
|---|----------|----------------------|
| 1 | Does `GLMASRModel.generate(audio:)` accept raw `[Float]` or require file URL? | Task implementation (ASRProvider) |
| 2 | What is exact memory footprint of Nemotron 0.6B 8-bit on M1 with MLX runtime? | Performance profiling task |
| 3 | Does mlx-audio-swift compile with Swift 6 in Xcode 15+/16? | Package.swift setup task |
| 4 | What is optimal audio tap buffer size for latency vs. CPU tradeoff? | Audio profiling task |
| 5 | Does model require explicit language hint for mixed Chinese-English, or auto-detect reliably? | Manual M1 verification task |

---

## Glossary

| Term | Definition |
|------|------------|
| **ASR** | Automatic Speech Recognition |
| **Nemotron** | NVIDIA's open ASR model family; MVP uses 0.6B 8-bit quantized variant |
| **MLXAudioSTT** | Swift product from Blaizzy/mlx-audio-swift providing ASR inference |
| **Push-to-Talk (PTT)** | User interaction model: hold hotkey to record, release to stop |
| **SessionCoordinator** | Central actor managing application state and workflow |
| **TranscriptDestination** | Component responsible for clipboard and paste operations |
| **Accessibility Permission** | macOS permission required for CGEvent posting (paste simulation) |
| **arm64** | CPU architecture for Apple Silicon Macs (M1, M2, M3, etc.) |

---

*Generated from research findings in research.md, product scope in VOICEDOCK_MASTER_PROMPT.md, and engineering constitution in AGENTS.md*