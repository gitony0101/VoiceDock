# Design: VoiceDock Push-to-Talk MVP

## Overview

VoiceDock is a native macOS menu bar application that captures speech via global push-to-talk, transcribes locally using Nemotron ASR, and pastes the result into the focused application. The architecture follows a unidirectional flow: UI observes state, SessionCoordinator owns workflow, and infrastructure services handle audio/ASR/delivery with clear boundaries and actor isolation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VoiceDock Application                         │
│                                                                  │
│  ┌──────────────┐                                               │
│  │  MenuBarView │ (SwiftUI + AppKit)                            │
│  │  - status    │                                               │
│  │  - controls  │───┐                                           │
│  └──────────────┘   │ @MainActor state observation              │
│                     │ intent dispatch                           │
│                     ▼                                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              SessionCoordinator (Actor)                  │    │
│  │  - owns state machine                                    │    │
│  │  - serializes workflow                                   │    │
│  │  - owns AudioCapture, ASRProvider, TranscriptDestination │    │
│  └─────────────────────────────────────────────────────────┘    │
│                     │                                             │
│      ┌──────────────┼──────────────┬──────────────┐              │
│      ▼              ▼              ▼              ▼              │
│  ┌──────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────┐   │
│  │Audio     │  │Audio      │  │ASR        │  │Transcript    │   │
│  │Capture   │  │Normalizer │  │Provider   │  │Destination   │   │
│  │(AVAudio) │  │(converter)│  │(MLXAudio) │  │(paste/cmd-v) │   │
│  └──────────┘  └───────────┘  └───────────┘  └──────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                          ▲
                          │ Accessibility Permission
                          │ Microphone Permission
                          ▼
                    ┌──────────────┐
                    │  macOS System│
                    │  - CGEvent   │
                    │  - Pasteboard│
                    └──────────────┘
```

## Components

### SessionCoordinator

**Purpose**: Central actor owning application workflow, state machine, and coordination of all subsystems.

**Responsibilities**:
- Manage state transitions (idle → loading → ready → listening → transcribing → delivering → idle/error)
- Serialize ASR model lifecycle (load, warmup, transcribe, unload)
- Coordinate audio capture with ASR transcription
- Handle cancellation and error recovery
- Inject dependencies into UI layer

**State Machine**:

```swift
enum AppState: Equatable {
    case idle
    case loading(String)           // progress message
    case ready
    case listening
    case transcribing
    case delivering
    case error(String)             // user-facing message
    case permissionRequired(PermissionType)
    
    enum PermissionType {
        case microphone
        case accessibility
    }
}
```

**Implementation**:

```swift
actor SessionCoordinator: ObservableObject {
    // MARK: - Published State
    @Published private(set) var state: AppState = .idle
    @Published private(set) var isRecording: Bool = false
    
    // MARK: - Dependencies
    private let audioCapture: AudioCapture
    private let audioNormalizer: AudioNormalizer
    private let asrProvider: ASRProvider
    private let transcriptDestination: TranscriptDestination
    
    // MARK: - Internal State
    private var audioBuffer: [Float] = []
    private var isModelLoaded: Bool = false
    
    // MARK: - Initialization
    init(
        audioCapture: AudioCapture,
        audioNormalizer: AudioNormalizer,
        asrProvider: ASRProvider = MLXAudioSTTProvider(),
        transcriptDestination: TranscriptDestination = TranscriptDestination()
    ) {
        self.audioCapture = audioCapture
        self.audioNormalizer = audioNormalizer
        self.asrProvider = asrProvider
        self.transcriptDestination = transcriptDestination
        
        Task { @MainActor [self] in
            await self.setupAudioCaptureCallback()
        }
    }
    
    // MARK: - Public Interface
    func startRecording() async throws
    func stopRecording() async throws
    func cancelRecording() async
    func ensureModelLoaded() async throws
    func checkPermissions() async -> PermissionStatus
    func requestMicrophonePermission() async -> Bool
    func requestAccessibilityPermission()
    func quit() async
}
```

**Actor Isolation Boundaries**:
- All mutable state is actor-isolated
- `@Published` properties are annotated `@MainActor` for UI observation
- Audio callback dispatches to `SessionCoordinator` via `Task { await coordinator.handle(...) }`
- ASR lifecycle methods are `await`ed, ensuring serialization

---

### AudioCapture

**Purpose**: Manage microphone capture lifecycle using AVAudioEngine.

**Responsibilities**:
- Initialize and configure AVAudioEngine
- Install tap on input node for buffer stream
- Manage start/stop/cancel operations
- Ensure non-blocking callback discipline
- Detect microphone disconnection

**Implementation**:

```swift
final class AudioCapture: Sendable {
    // MARK: - Configuration
    private let targetFormat: AVAudioFormat
    private let callbackQueue: DispatchQueue
    
    // MARK: - AVAudioEngine
    private let engine = AVAudioEngine()
    private var isRunning: Bool = false
    
    // MARK: - Buffer Accumulation
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()  // simple lock for C callback interop
    
    // MARK: - Callback (injected by coordinator)
    private var onBufferAvailable: (([Float]) -> Void)?
    
    // MARK: - Initialization
    init(
        sampleRate: Double = 16_000,
        channels: AVAudioChannelCount = 1
    ) {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        self.callbackQueue = DispatchQueue(label: "voicedock.audio.callback", qos: .userInteractive)
    }
    
    // MARK: - Public Interface
    func setBufferCallback(_ callback: @escaping ([Float]) -> Void) {
        self.onBufferAvailable = callback
    }
    
    func start() throws {
        guard !isRunning else { return }
        
        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0,
                             bufferSize: 1024,
                             format: targetFormat) { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer, time: time)
        }
        
        try engine.start()
        isRunning = true
    }
    
    func stop() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
        
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let final = audioBuffer
        audioBuffer = []
        return final
    }
    
    func cancel() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
        bufferLock.lock()
        audioBuffer = []
        bufferLock.unlock()
    }
    
    // MARK: - Non-Blocking Callback
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // CRITICAL: This block must return immediately.
        // All heavy work happens on callbackQueue.
        
        let samples = Array(UnsafeBufferPointer(
            start: buffer.floatChannelData![0],
            count: Int(buffer.frameLength)
        ))
        
        callbackQueue.async { [weak self] in
            self?.accumulate(samples)
        }
    }
    
    private func accumulate(_ samples: [Float]) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        audioBuffer.append(contentsOf: samples)
    }
    
    func isMicrophoneAvailable() -> Bool {
        engine.inputNode.inputAudioUnit != nil
    }
}
```

**Key Constraints** (from AGENTS.md):
- No inference, file I/O, networking, or logging in callback
- Callback must return in < 5ms per 10ms buffer
- Explicit ownership: `bufferLock` protects shared `[Float]` array
- Cancellation clears buffer immediately

---

### AudioNormalizer

**Purpose**: Convert audio buffers to canonical ASR input format.

**Responsibilities**:
- Validate input format
- Resample to 16 kHz if needed
- Convert to mono if needed
- Ensure Float32 sample type
- Handle empty input gracefully

**Implementation**:

```swift
struct AudioNormalizer: Sendable {
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1
    private let targetFormat: AVAudioFormat
    
    init() {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        )!
    }
    
    /// Normalize audio buffer to 16 kHz mono Float32.
    /// Returns nil for empty input (no crash).
    func normalize(_ samples: [Float]) async -> [Float]? {
        guard !samples.isEmpty else { return nil }
        
        // If already in target format, return as-is
        // (In practice, AudioCapture already provides this format)
        // This is a safety layer for future flexibility.
        
        return samples
    }
    
    /// Normalize from AVAudioPCMBuffer (for future format flexibility)
    func normalize(_ buffer: AVAudioPCMBuffer) async -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        
        guard let floatData = buffer.floatChannelData else {
            // Handle integer PCM by converting
            return normalizeIntPCM(buffer)
        }
        
        let sampleCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Interleaved to deinterleaved conversion if needed
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: floatData.pointee, count: sampleCount))
        } else {
            // Downmix to mono: average all channels
            var mono = [Float](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += floatData[ch][i]
                }
                mono[i] = sum / Float(channelCount)
            }
            return mono
        }
    }
    
    private func normalizeIntPCM(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let int16Data = buffer.int16ChannelData else { return nil }
        
        let sampleCount = Int(buffer.frameLength)
        return (0..<sampleCount).map { i in
            Float(int16Data.pointee[i]) / 32768.0
        }
    }
}
```

**API Contract**:
- Input: `[Float]` or `AVAudioPCMBuffer`
- Output: `[Float]?` (nil for empty input)
- Format: 16 kHz, mono, Float32
- Deterministic: same input → same output

---

### ASRProvider

**Purpose**: Model-agnostic protocol for speech-to-text inference.

**Protocol Definition** (from AGENTS.md):

```swift
actor ASRProvider {
    func load() async throws
    func warmup() async throws
    func transcribe(audio: [Float]) async throws -> String
    func unload() async
}
```

**Error Type**:

```swift
enum ASError: LocalizedError {
    case loadFailed(String)
    case warmupFailed(String)
    case inferenceFailed(String)
    case modelNotLoaded
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "Model load failed: \(msg)"
        case .warmupFailed(let msg): return "Model warmup failed: \(msg)"
        case .inferenceFailed(let msg): return "Transcription failed: \(msg)"
        case .modelNotLoaded: return "Model not loaded"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .loadFailed, .modelNotLoaded:
            return "Check internet connection and retry. Model downloads (~756 MB) on first use."
        case .inferenceFailed:
            return "Try speaking more clearly or retry."
        default:
            return nil
        }
    }
}
```

**MLXAudioSTT Implementation**:

```swift
actor MLXAudioSTTProvider: ASRProvider {
    private var model: GLMASRModel?
    private let modelPath: String = "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
    
    // MARK: - ASRProvider
    func load() async throws {
        guard model == nil else { return }
        
        do {
            model = try await GLMASRModel.fromPretrained(modelPath)
        } catch {
            throw ASError.loadFailed(error.localizedDescription)
        }
    }
    
    func warmup() async throws {
        guard let model = model else {
            throw ASError.modelNotLoaded
        }
        
        // Warmup with short silent buffer
        let silent = [Float](repeating: 0, count: 160)  // 10ms of silence
        _ = model.generate(audio: silent, language: nil)
    }
    
    func transcribe(audio: [Float]) async throws -> String {
        guard let model = model else {
            throw ASError.modelNotLoaded
        }
        
        guard !audio.isEmpty else {
            return ""
        }
        
        do {
            // Note: mlx-audio-swift API may require AVAudioPCMBuffer or file URL.
            // If raw [Float] not supported, wrap in temporary buffer.
            let result = model.generate(audio: audio, language: nil)
            return result.text
        } catch {
            throw ASError.inferenceFailed(error.localizedDescription)
        }
    }
    
    func unload() async {
        model = nil
    }
}
```

**Lifecycle Serialization**:
- Actor isolation ensures `load() → warmup() → transcribe() → unload()` cannot interleave
- Concurrent `transcribe()` calls are queued automatically by actor

---

### TranscriptDestination

**Purpose**: Deliver transcript text to focused application via clipboard and simulated paste.

**Responsibilities**:
- Copy text to system clipboard
- Simulate Command-V paste via CGEvent
- Optionally simulate Return key
- Handle Accessibility permission gracefully

**Implementation**:

```swift
struct TranscriptDestination: Sendable {
    
    // MARK: - Public Interface
    func deliver(_ transcript: String, sendReturn: Bool = true) async throws -> DeliveryResult {
        guard !transcript.isEmpty else {
            throw DeliveryError.emptyTranscript
        }
        
        // Step 1: Copy to clipboard
        try copyToClipboard(transcript)
        
        // Step 2: Check Accessibility permission
        let hasAccessibility = AXIsProcessTrusted()
        
        if !hasAccessibility {
            return .clipboardOnly(reason: "Accessibility permission denied")
        }
        
        // Step 3: Simulate paste
        try simulatePaste()
        
        // Step 4: Optionally send Return
        if sendReturn {
            try simulateReturn()
        }
        
        return .success
    }
    
    // MARK: - Clipboard
    private func copyToClipboard(_ text: String) throws {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(text, forType: .string)
        guard success else {
            throw DeliveryError.clipboardFailed
        }
    }
    
    // MARK: - CGEvent Simulation
    private func simulatePaste() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DeliveryError.eventSourceFailed
        }
        
        // Command-V
        let commandKey = CGEvent(keyboardEventSource: source,
                                  virtualKey: 0x09,  // kVK_ANSI_V
                                  keyDown: true)
        commandKey?.flags = .maskCommand
        
        let commandKeyUp = CGEvent(keyboardEventSource: source,
                                    virtualKey: 0x09,
                                    keyDown: false)
        commandKeyUp?.flags = .maskCommand
        
        commandKey?.post(tap: .cghidEventTap)
        commandKeyUp?.post(tap: .cghidEventTap)
        
        // Brief delay for system to process
        Thread.sleep(forTimeInterval: 0.05)
    }
    
    private func simulateReturn() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DeliveryError.eventSourceFailed
        }
        
        let returnKeyDown = CGEvent(keyboardEventSource: source,
                                     virtualKey: 0x24,  // kVK_Return
                                     keyDown: true)
        let returnKeyUp = CGEvent(keyboardEventSource: source,
                                   virtualKey: 0x24,
                                   keyDown: false)
        
        returnKeyDown?.post(tap: .cghidEventTap)
        returnKeyUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Result Types
    enum DeliveryResult: Equatable {
        case success
        case clipboardOnly(reason: String)
    }
    
    enum DeliveryError: LocalizedError {
        case emptyTranscript
        case clipboardFailed
        case eventSourceFailed
        
        var errorDescription: String? {
            switch self {
            case .emptyTranscript: return "No transcript to deliver"
            case .clipboardFailed: return "Failed to copy to clipboard"
            case .eventSourceFailed: return "Failed to create event source"
            }
        }
    }
}
```

**Permission Handling**:
- `AXIsProcessTrusted()` checked before paste
- Degrades to `.clipboardOnly` if denied
- UI shows actionable message with Settings deep link

---

### MenuBarView

**Purpose**: SwiftUI view for menu bar presence and status display.

**Structure**:

```swift
struct MenuBarView: View {
    @StateObject private var coordinator: SessionCoordinator
    @State private var popoverShowing: Bool = false
    
    var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                MenuBarIcon(systemName: "waveform", color: .gray)
            case .loading(let message):
                MenuBarIcon(systemName: "arrow.clockwise", color: .orange)
                    .help(message)
            case .ready:
                MenuBarIcon(systemName: "checkmark.circle", color: .green)
            case .listening:
                MenuBarIcon(systemName: "mic.fill", color: .red)
                    .symbolEffect(.pulse)
            case .transcribing:
                MenuBarIcon(systemName: "waveform.2.right", color: .blue)
            case .delivering:
                MenuBarIcon(systemName: "text.badge.checkmark", color: .green)
            case .error(let message):
                MenuBarIcon(systemName: "exclamationmark.triangle", color: .red)
                    .help(message)
            case .permissionRequired(let type):
                MenuBarIcon(systemName: "lock.fill", color: .orange)
                    .help("Permission required: \(type)")
            }
        }
        .onTapGesture {
            togglePopover()
        }
        .popover(isPresented: $popoverShowing) {
            StatusPopover(coordinator: coordinator)
        }
    }
}
```

**StatusPopover**:

```swift
struct StatusPopover: View {
    @ObservedObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            // Current state
            Text(stateDescription)
                .font(.headline)
            
            // Progress indicator if loading/transcribing
            if coordinator.state == .loading || coordinator.state == .transcribing {
                ProgressView()
            }
            
            // Permission buttons
            if case .permissionRequired(let type) = coordinator.state {
                Button(requestPermissionAction) {
                    Text(for: type)
                }
            }
            
            // Quit action
            Button("Quit") {
                Task { await coordinator.quit() }
            }
        }
        .padding()
    }
    
    private var stateDescription: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .loading(let msg): return msg
        case .ready: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .delivering: return "Delivering..."
        case .error(let msg): return msg
        case .permissionRequired(let type): return "Permission Required: \(type)"
        }
    }
}
```

**State Observation Rule**:
- Views only observe `@Published` state from coordinator
- Views send intents (`Task { await coordinator.startRecording() }`)
- Views never instantiate models or infrastructure services

---

## Data Flow

```
┌─────────┐      ┌──────────────────┐      ┌──────────────┐      ┌─────────────┐
│   User  │      │ SessionCoordinator│      │  AudioCapture│      │ ASRProvider │
└────┬────┘      └─────────┬────────┘      └──────┬───────┘      └──────┬──────┘
     │                      │                       │                    │
     │ 1. Press PTT Hotkey  │                       │                    │
     │─────────────────────>│                       │                    │
     │                      │ 2. startRecording()   │                    │
     │                      │──────────────────────>│                    │
     │                      │                       │ 3. engine.start()  │
     │                      │                       │ 4. installTap()    │
     │ 5. Visual: Listening │                       │                    │
     │<─────────────────────│                       │                    │
     │                      │                       │ [Audio buffers...] │
     │                      │                       │                    │
     │ 6. Release PTT       │                       │                    │
     │─────────────────────>│                       │                    │
     │                      │ 7. stopRecording()    │                    │
     │                      │──────────────────────>│                    │
     │                      │                       │ 8. stop(), return  │
     │                      │<──────────────────────│   [Float] array    │
     │                      │                       │                    │
     │                      │ 9. normalize()        │                    │
     │                      │───────────────────────>                    │
     │                      │<──────────────────────│   normalized       │
     │                      │                       │                    │
     │                      │ 10. transcribe(audio) │                    │
     │                      │───────────────────────────────────────────>│
     │ 11. Visual:          │                       │                    │
     │     Transcribing...  │                       │                    │
     │<─────────────────────│                       │                    │
     │                      │                       │ 12. generate()     │
     │                      │<───────────────────────────────────────────│
     │                      │   "text transcript"   │                    │
     │                      │                       │                    │
     │                      │ 13. deliver(text)     │
     │                      │───────────────────────>│
     │                      │                       │ 14. copy to clipboard
     │                      │                       │ 15. CGEvent Cmd-V  │
     │                      │<───────────────────────│   (if permitted) │
     │ 16. Visual: Done     │                       │                    │
     │<─────────────────────│                       │                    │
```

**Step-by-Step**:

1. User presses global PTT hotkey (e.g., Command+Space)
2. `SessionCoordinator.startRecording()` called
3. `AudioCapture.start()` initializes engine, starts tap
4. Tap callback begins accumulating `[Float]` samples
5. UI updates to `.listening` state (animated mic icon)
6. User releases hotkey
7. `SessionCoordinator.stopRecording()` called
8. `AudioCapture.stop()` returns accumulated buffer
9. `AudioNormalizer.normalize()` converts format (if needed)
10. `ASRProvider.transcribe(audio:)` called
11. UI updates to `.transcribing` state
12. MLX model runs inference, returns transcript string
13. `TranscriptDestination.deliver(text:)` called
14. Transcript copied to `NSPasteboard.general`
15. Command-V simulated via `CGEvent` (if Accessibility granted)
16. UI briefly shows `.delivering`, returns to `.ready`

---

## Concurrency Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     Concurrency Boundaries                       │
│                                                                   │
│  ┌─────────────────┐                                             │
│  │   Main Actor    │  ← UI updates, state observation            │
│  │  MenuBarView    │  ← SwiftUI views                            │
│  │  StatusPopover  │                                             │
│  └────────┬────────┘                                             │
│           │ @MainActor                                            │
│           ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │         SessionCoordinator (isolated actor)                 │ │
│  │  - Mutable state private to actor                           │ │
│  │  - Serializes workflow                                      │ │
│  │  - Receives audio callback via Task { await ... }           │ │
│  └────────┬────────────────────────────────────────────────────┘ │
│           │ Task { await ... }                                    │
│           ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │         AudioCapture.callbackQueue (serial DispatchQueue)   │ │
│  │  - Non-blocking tap callback                                │ │
│  │  - Buffer accumulation with lock                            │ │
│  │  - No inference, I/O, networking, logging                   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │         ASRProvider (isolated actor)                        │ │
│  │  - Model lifecycle serialized                               │ │
│  │  - Inference runs in actor context                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Key Rules**:

| Boundary | Mechanism | Discipline |
|----------|-----------|------------|
| UI → Coordinator | `Task { await ... }` | Views send intents only |
| Coordinator → UI | `@Published @MainActor` | Automatic observation |
| Audio callback → Coordinator | `Task { await coordinator.handle() }` | Non-blocking dispatch |
| Coordinator → ASR | `await asrProvider.transcribe()` | Actor serialization |
| Buffer ownership | `NSLock` | Explicit lock for C callback interop |

**Non-Blocking Audio Callback**:
- Tap block returns in < 5ms
- Buffer copy dispatched to `callbackQueue.async`
- No `await`, no file I/O, no networking, no logging in callback

---

## Error Handling Strategy

**Error Types**:

```swift
enum VoiceDockError: LocalizedError {
    // Audio errors
    case microphoneNotFound
    case audioEngineFailed
    case audioFormatConversionFailed
    
    // ASR errors
    case modelLoadFailed(String)
    case modelWarmupFailed(String)
    case transcriptionFailed(String)
    
    // Delivery errors
    case clipboardFailed
    case pasteFailed
    case accessibilityDenied
    
    // Permission errors
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    
    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

**Recovery Actions**:

| Error Scenario | Handling Strategy | User Impact |
|----------------|-------------------|-------------|
| Model load failed | Retry download; offer manual fallback | "Could not download ASR model. Check internet and retry." |
| Microphone not found | Detect input node failure; show error | "No microphone detected. Connect a microphone and try again." |
| Permission denied | Show settings deep link | "Open System Settings → Privacy → [Microphone/Accessibility]" |
| Transcription failed | Clear audio buffer; return to idle | "Transcription failed. Try speaking more clearly or retry." |
| Clipboard failed | Return to idle; show error | "Could not copy transcript. Retry or restart VoiceDock." |
| Accessibility denied | Degrade to clipboard-only | "Transcript copied to clipboard. Enable Accessibility for auto-paste." |

**State Machine on Error**:
```
any state → .error(message) → (user action) → .idle
```

---

## Testing Strategy

### Unit Tests

| Component | Test Cases | Mock Requirements |
|-----------|------------|-------------------|
| `AudioNormalizer` | `testNormalize_to16kHzMonoFloat32`, `testEmptyHandling`, `testInterleavedToMono` | None (pure function) |
| `ASRProvider` (protocol) | N/A | Protocol mock for SessionCoordinator tests |
| `TranscriptDestination` | `testCopyToClipboard`, `testSimulatePaste`, `testEmptyTranscriptError` | None |
| `SessionCoordinator` | `testStateTransitions`, `testCancellation`, `testModelLoadFailure`, `testAspectRatio`, `testEmptyAudioHandling` | `MockASRProvider`, `MockAudioCapture` |

**MockASRProvider**:

```swift
actor MockASRProvider: ASRProvider {
    var stubbedResult: String = "test transcript"
    var shouldFailLoad: Bool = false
    var shouldFailWarmup: Bool = false
    var shouldFailTranscribe: Bool = false
    var loadCalled: Bool = false
    var warmupCalled: Bool = false
    var transcribeCalled: Bool = false
    var receivedAudio: [Float]?
    
    func load() async throws {
        loadCalled = true
        if shouldFailLoad { throw ASError.loadFailed("mock") }
    }
    
    func warmup() async throws {
        warmupCalled = true
        if shouldFailWarmup { throw ASError.warmupFailed("mock") }
    }
    
    func transcribe(audio: [Float]) async throws -> String {
        transcribeCalled = true
        receivedAudio = audio
        if shouldFailTranscribe { throw ASError.inferenceFailed("mock") }
        return stubbedResult
    }
    
    func unload() async {}
}
```

**MockAudioCapture**:

```swift
final class MockAudioCapture: AudioCapture {
    var stubbedBuffer: [Float] = []
    var startCalled: Bool = false
    var stopCalled: Bool = false
    var cancelCalled: Bool = false
    
    override func start() throws {
        startCalled = true
    }
    
    override func stop() -> [Float] {
        stopCalled = true
        return stubbedBuffer
    }
    
    override func cancel() {
        cancelCalled = true
    }
}
```

### Integration Tests

| Scenario | Verification |
|----------|--------------|
| Full PTT flow (mocked ASR) | State: idle → listening → transcribing → delivering → idle |
| Model load → warmup → transcribe | ASR lifecycle serialization |
| Clipboard → paste sequence | Text appears in focused app (manual or CI with accessibility) |
| Permission denial flow | Coordinator state → `.permissionRequired` |

### Manual Verification Checklist

| Test | Platform | Expected Result |
|------|----------|-----------------|
| English speech | M1 16 GB | Accurate English transcript |
| Mandarin speech | M1 16 GB | Accurate Chinese transcript |
| Mixed Chinese-English | M1 16 GB | Coherent mixed-language transcript |
| Hotkey-to-capture latency | M1 | < 100ms |
| Transcription duration (10s speech) | M1 | < 5 seconds |
| Total flow time | M1 | < 10 seconds |
| Memory footprint | M1 | < 2 GB peak |
| Rapid repeated sessions | M1 | No crashes, no state corruption |
| Microphone disconnect | M1 | Graceful error, actionable message |

---

## File Structure

```
VoiceDock/
├── VoiceDock.xcodeproj/
│   └── project.pbxproj
├── Package.swift
├── VoiceDockApp/
│   ├── VoiceDockApp.swift          # @main entry point
│   ├── AppDelegate.swift           # NSStatusItem, NSPopover hosting
│   ├── Info.plist                  # Permissions: Mic, Accessibility
│   │
│   ├── Views/
│   │   ├── MenuBarView.swift       # Main menu bar UI
│   │   ├── StatusPopover.swift     # Status panel
│   │   └── Icons/
│   │       └── MenuBarIcon.swift   # Reusable icon component
│   │
│   ├── Coordinator/
│   │   ├── SessionCoordinator.swift    # Central actor
│   │   └── AppState.swift              # State machine enum
│   │
│   ├── Audio/
│   │   ├── AudioCapture.swift      # AVAudioEngine wrapper
│   │   └── AudioNormalizer.swift   # Format conversion
│   │
│   ├── ASR/
│   │   ├── ASRProvider.swift       # Protocol definition
│   │   ├── MLXAudioSTTProvider.swift   # MLX implementation
│   │   └── ASError.swift           # Error types
│   │
│   ├── Delivery/
│   │   └── TranscriptDestination.swift # Clipboard + paste
│   │
│   ├── Permissions/
│   │   ├── PermissionManager.swift # Check + request
│   │   └── PermissionExplanation.swift # Pre-permission UI
│   │
│   ├── HotKey/
│   │   └── HotKeyManager.swift     # Carbon/NSEvent hotkey
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Localizable.strings
│
└── VoiceDockTests/
    ├── Audio/
    │   ├── AudioNormalizerTests.swift
    │   └── AudioCaptureTests.swift
    ├── ASR/
    │   ├── MockASRProvider.swift
    │   └── MLXAudioSTTProviderTests.swift
    ├── Delivery/
    │   └── TranscriptDestinationTests.swift
    ├── Coordinator/
    │   └── SessionCoordinatorTests.swift
    └── Helpers/
        └── TestHelpers.swift
```

---

## Technical Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Hotkey detection | Carbon `RegisterEventHotKey` vs NSEvent global monitor | Carbon | More reliable when app backgrounded; NSEvent only fires when app not frontmost |
| Testing framework | XCTest vs Swift Testing | XCTest | Mature Xcode integration; broader CI/tooling compatibility |
| ASR input format | Raw `[Float]` vs file URL | `[Float]` preferred | Matches research API shape; fallback to temp file if MLX requires |
| Audio buffer sync | Actor isolation vs DispatchQueue + lock | DispatchQueue + lock | C callback interop; explicit ownership clearer than `@Sendable` |
| State management | `@Published` actor properties vs separate ViewState | `@Published` on MainActor | Minimal boilerplate; SwiftUI integrates directly |
| Model lifecycle | Always resident vs load/unload per session | Always resident | M1 16 GB baseline can hold 756 MB; avoids repeated download latency |

---

## Performance Considerations

| Metric | Target | Approach |
|--------|--------|----------|
| Hotkey-to-capture | < 100 ms | Direct `engine.start()` on hotkey; no async overhead |
| Capture-to-transcribe | < 500 ms | Immediate `transcribe()` after `stop()` |
| Transcription (10s speech) | < 5 s | MLX GPU/Neural Engine; warmup on first load |
| Total flow | < 10 s | Parallel pipeline where possible |
| Memory | < 2 GB peak | Single model resident; no audio persistence |
| Audio callback | < 5 ms / 10 ms buffer | Non-blocking queue dispatch |

**Warmup Strategy**:
- Load model on first `transcribe()` call (lazy)
- Warmup with 10ms silence buffer before first real transcription
- Keep model resident until quit (no unload)

---

## Security Considerations

| Requirement | Implementation |
|-------------|----------------|
| No telemetry | No network calls except model download via MLXAudioSTT |
| No transcript storage | Transcript string exists only in memory; cleared after delivery |
| No audio persistence | `audioBuffer` cleared after `transcribe()` returns |
| No cloud upload | ASR runs 100% local; MLXAudioSTT does not phone home |
| Permission explanation | Info.plist + pre-permission UI copy |
| Model validation | MLXAudioSTT handles SHA; downloaded outside app bundle |

**Privacy Defaults**:
- Local microphone processing only
- No transcript history
- No raw audio logs
- No background network activity (except explicit model download)

---

## Edge Cases

| Edge Case | Handling |
|-----------|----------|
| Empty audio buffer | Return empty string; no crash; UI shows "No speech detected" |
| Microphone unplugged during recording | Detect input node failure; show "Microphone disconnected" error |
| Model download corrupted | MLXAudioSTT retry; manual fallback documented |
| Accessibility permission denied mid-flow | Graceful degrade to clipboard-only; user notified |
| Hotkey pressed during transcription | Cancel current session; clear buffer; start new recording |
| No focusable application | Paste fails silently; clipboard copy succeeds |
| Non-ASCII transcript (Chinese) | UTF-8 string; NSPasteboard handles natively |
| PTT pressed while already recording | Cancel current session; start fresh |

---

## Existing Patterns to Follow

From AGENTS.md and codebase conventions:

- SwiftUI views send intents and observe state; they do not instantiate models or services
- `SessionCoordinator` owns workflow; no workflow logic in views
- Initializer injection for all dependencies; no mutable service locators
- Actor isolation for concurrent access to shared state
- Non-blocking audio callback discipline (critical)
- No speculative abstractions for future releases
- No duplicate physical source trees
- English, Mandarin, and mixed Chinese-English transcription required

---

## Unresolved Questions

1. **MLXAudioSTT API shape**: Does `GLMASRModel.generate(audio:)` accept raw `[Float]` or require `AVAudioPCMBuffer` / file URL? → Requires implementation-time verification.

2. **Swift 6 compatibility**: Does `mlx-audio-swift` main branch compile cleanly with Swift 6 mode? → Requires Package.swift setup and build verification.

3. **Exact memory footprint**: What is peak RAM usage of Nemotron 0.6B 8-bit on M1 with MLX runtime? → Requires Instruments profiling.

4. **Mixed-language auto-detection**: Does Nemotron auto-detect Chinese-English code-switching, or require explicit language hint? → Requires manual M1 verification.

---

## Implementation Steps

1. **Project Setup**: Create Xcode macOS App target, `Package.swift` with mlx-audio-swift dependency, basic folder structure

2. **Permissions Foundation**: Implement `PermissionManager`, add Info.plist keys (`NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription`), pre-permission explanation UI

3. **AudioCapture**: Implement `AudioCapture` class with AVAudioEngine, tap installation, non-blocking callback, start/stop/cancel API

4. **AudioNormalizer**: Implement pure function for format conversion with unit tests

5. **ASRProvider Protocol**: Define `actor ASRProvider` protocol; implement `MLXAudioSTTProvider`

6. **SessionCoordinator**: Implement central actor with state machine, wire up audio capture and ASR provider

7. **TranscriptDestination**: Implement clipboard copy and CGEvent paste simulation

8. **HotKeyManager**: Implement Carbon `RegisterEventHotKey` for global PTT detection

9. **MenuBarView**: Implement SwiftUI menu bar view with state observation

10. **Wiring**: Connect all components in `VoiceDockApp.swift` and `AppDelegate`

11. **Unit Tests**: Add tests for `AudioNormalizer`, `TranscriptDestination`, `SessionCoordinator` (with mocks)

12. **Manual Verification**: Test English, Mandarin, mixed speech on M1; record performance metrics

13. **Build Verification**: Debug and Release builds; fix warnings