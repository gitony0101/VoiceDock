# VoiceDock Push-to-Talk MVP Research

## Executive Summary

The VoiceDock Push-to-Talk MVP is technically **feasible** with the selected technology stack. The Blaizzy/mlx-audio-swift package provides native Swift bindings for MLX-based ASR models, including the NVIDIA Nemotron 3.5 ASR 0.6B 8-bit model (~756 MB). macOS audio capture via AVAudioEngine supports real-time microphone input with on-the-fly conversion to 16 kHz mono Float32 format. Global push-to-touch requires Accessibility permission via `AXIsProcessTrusted` and `CGEventTap` for reliable system-wide hotkey detection. Primary risks include Swift 6 compatibility verification for mlx-audio-swift, memory footprint on 16 GB M1 baseline, and ensuring audio callback non-blocking behavior.

## Feasibility Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| **Overall** | HIGH | All required APIs and libraries exist and are documented |
| **Technical Risk** | MEDIUM | Swift 6 compatibility unconfirmed; memory/performance on baseline M1 requires validation |
| **Effort** | M | Focused MVP scope; 5-7 coherent implementation tasks expected |

## Key Findings

### MLXAudioSTT and mlx-audio-swift

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/Blaizzy/mlx-audio-swift |
| **SPM Dependency** | `.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")` |
| **Product** | `.product(name: "MLXAudioSTT", package: "mlx-audio-swift")` |
| **Swift Version** | Swift 5.9+ listed; Swift 6 compatibility requires verification |
| **Platform** | macOS 14+, iOS 17+, Apple Silicon, Xcode 15+ |
| **Model Loading** | `try await GLMASRModel.fromPretrained("mlx-community/...")` |
| **Transcription** | `model.generate(audio: audioData) -> String` |

**API Pattern (from README):**

```swift
import MLXAudioSTT
import MLXAudioCore

let (sampleRate, audioData) = try loadAudioArray(from: audioURL)

let model = try await GLMASRModel.fromPretrained(
    "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")

let output = model.generate(audio: audioData)
print(output.text)
```

**Note:** The package automatically downloads models from Hugging Face Hub via the `fromPretrained` async initializer.

### Nemotron 3.5 ASR 0.6B 8-bit Model

| Property | Value |
|----------|-------|
| **Model URL** | https://huggingface.co/mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit |
| **Original (NVIDIA)** | https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b |
| **Size on Disk** | 756 MB (8-bit quantized MLX format) |
| **Parameter Count** | ~600M (0.6B) |
| **Architecture** | Cache-aware streaming FastConformer-RNNT |
| **Quantization** | 8-bit Linear/Embedding (group-size 64); conv/norm in bfloat16 |
| **Language Support** | 35-40 languages including en-US (English), zh-CN (Mandarin Chinese) |
| **Audio Input** | WAV file (PCM implied); sample rate, channels, dtype not explicitly documented on model card |
| **Performance Claim** | Matches bf16 quality at ~40% smaller size |

**Python API Reference:**

```python
from mlx_audio.stt import load
model = load("mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")
print(model.generate("speech.wav").text)        # auto-detect language
print(model.generate("speech.wav", language="en-US").text)  # force English
```

**Open Question:** The Swift wrapper API signature for raw audio buffer input (vs. file URL) requires verification during implementation.

### macOS Audio Capture

**AVAudioEngine Setup:**

```swift
import AVFoundation

class MicEngine {
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let processingQueue = DispatchQueue(label: "mic.processing")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    init() {
        configureSession()
        installTap()
        try? engine.start()
    }

    private func configureSession() {
        try? session.setCategory(.playAndRecord,
                                 mode: .measurement,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(targetFormat.sampleRate)
        try? session.setPreferredIOBufferDuration(0.010)
        try? session.setActive(true)
    }

    private func installTap() {
        let input = engine.inputNode
        input.installTap(onBus: 0,
                         bufferSize: 1024,
                         format: targetFormat) { [weak self] buffer, time in
            self?.handle(buffer: buffer, time: time)
        }
    }

    private func handle(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        processingQueue.async {
            let samples = buffer.floatChannelData![0]
            let count = Int(buffer.frameLength)
            // Forward to ASR pipeline
        }
    }
}
```

**Key Points:**

- **Format:** `.pcmFormatFloat32`, 16 kHz, mono, non-interleaved
- **Session Category:** `.playAndRecord`, `.measurement` mode for minimal processing
- **Non-blocking:** Audio callback dispatches heavy work to background queue; tap block returns immediately
- **Buffer Duration:** 10 ms preferred for low latency

**Permissions Required:**

- **Microphone:** Usage description in `Info.plist` (`NSMicrophoneUsageDescription`)
- **用户对麦克风权限的系统提示需解释用途**

### Menu Bar Application

**SwiftUI + AppKit Pattern:**

```swift
import SwiftUI
import AppKit

@main
struct VoiceDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = SessionCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "VoiceDock"
        statusItem?.button?.action = #selector(togglePopover)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 200)
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
```

**Global Push-to-Talk Hotkey:**

Two approaches for system-wide hotkey detection:

**Option 1: Carbon RegisterEventHotKey (traditional, most reliable)**

```swift
import Carbon.HIToolbox

class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?

    func register() {
        let hotKeyID = EventHotKeyID(signature: 'vdpt', id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef)
    }
}
```

**Option 2: NSEvent.addGlobalMonitorForEvents (simpler, limitation: only fires when app not frontmost)**

```swift
let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 49 && event.modifierFlags.contains(.command) {
        // Space bar with Command
        startRecording()
    }
}
```

**Accessibility Permission:**

```swift
import AppKit

func checkAccessibility() -> Bool {
    AXIsProcessTrusted()
}

func requestAccessibility() {
    let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
}
```

**Info.plist Requirement:**

```xml
<key>NSAppleEventsUsageDescription</key>
<string>VoiceDock needs Accessibility access to paste transcribed text into other applications.</string>
```

**Simulating Paste and Return:**

```swift
func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

// Command-V (Paste)
postKeyDown(keyCode: 0x09, flags: .maskCommand)  // kVK_ANSI_V

// Return key
postKeyDown(keyCode: 0x24)  // kVK_Return
```

### Testing Approach

**Framework:** XCTest (bundled with Xcode, mature macOS support)

**Test Categories:**

| Category | Strategy |
|----------|----------|
| **Unit Tests** | Protocol-based mocking for ASRProvider, AudioCapture; XCTest async/await |
| **Integration Tests** | SessionCoordinator state transitions; clipboard operations |
| **Manual Verification** | Real microphone capture; Nemotron ASR with actual speech |

**Async Test Pattern:**

```swift
class AudioNormalizerTests: XCTestCase {
    var sut: AudioNormalizer!

    override func setUp() {
        super.setUp()
        sut = AudioNormalizer(targetSampleRate: 16000)
    }

    func testNormalize_to16kHzMonoFloat32() async throws {
        // Arrange: mock input buffer
        // Act: normalize
        // Assert: output format matches 16 kHz mono Float32
    }

    func testEmptyHandling() async {
        // Empty input returns nil or empty result
    }
}
```

**Mocking Pattern:**

```swift
protocol ASRProvider {
    func load() async throws
    func warmup() async throws
    func transcribe(audio: [Float]) async throws -> String
    func unload() async
}

class MockASRProvider: ASRProvider {
    var stubbedResult: String = "test transcript"
    var shouldFail: Bool = false

    func load() async throws {
        if shouldFail { throw ASError.loadFailed }
    }

    func warmup() async throws {}
    func transcribe(audio: [Float]) async throws -> String {
        if shouldFail { throw ASError.inferenceFailed }
        return stubbedResult
    }

    func unload() async {}
}
```

**Swift Testing (new framework):** Available in Xcode 15+ but XCTest retained for broader CI/tooling compatibility in initial MVP.

## Architecture Recommendations

**Component Diagram (text):**

```
MenuBarView (SwiftUI)
    ↓ observes/injects
SessionCoordinator (Actor)
    ↓ owns
├── AudioCapture (AVAudioEngine)
├── AudioNormalizer (format conversion)
├── ASRProvider (MLXAudioSTT + Nemotron)
└── TranscriptDestination (Clipboard + CGEvent paste)
```

**Data Flow:**

```
1. User presses PTT hotkey → SessionCoordinator.startRecording()
2. AudioCapture starts microphone tap → buffers stream to AudioNormalizer
3. User releases PTT → AudioCapture.stop() → finalize audio buffer
4. SessionCoordinator.transcribe() → ASRProvider.transcribe(audio:)
5. ASRProvider returns transcript string
6. SessionCoordinator.deliver() → TranscriptDestination.paste(text:)
7. TranscriptDestination copies to clipboard, simulates Cmd-V, optionally Return
```

**Concurrency Model:**

- `SessionCoordinator` as isolated `actor` owns workflow state
- Audio callback dispatches to dedicated serial processing queue (non-blocking)
- ASR model lifecycle (load/warmup/transcribe/unload) serialized through actor isolation
- UI observes `@Published` state via `@MainActor`
- No global mutable state; initializer injection for all dependencies

## Technology Decisions

| Component | Decision | Details |
|-----------|----------|---------|
| **Language** | Swift 6 | Pending mlx-audio-swift compatibility verification |
| **UI Framework** | SwiftUI + AppKit | NSStatusItem for menu bar; NSPopover for status UI |
| **Audio Engine** | AVFoundation.AVAudioEngine | Microphone capture with format conversion |
| **Audio Format** | 16 kHz mono Float32 | `.pcmFormatFloat32`, 1 channel, 16000 Hz |
| **ASR Package** | Blaizzy/mlx-audio-swift | `branch: "main"` (no pinned tag yet) |
| **ASR Model** | Nemotron 3.5 ASR 0.6B 8-bit | 756 MB; https://huggingface.co/mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit |
| **Testing** | XCTest | Native Xcode integration; async/await test methods |
| **Minimum OS** | macOS 14 | Matches MLX runtime requirements |
| **Architecture** | arm64 | Apple Silicon only (M1 baseline) |
| **Hotkey** | Carbon RegisterEventHotKey OR NSEvent global monitor | Accessibility permission required for both |

## Risks and Mitigations

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | mlx-audio-swift Swift 6 incompatibility | HIGH | Verify during Package.swift setup; pin to known-good commit if needed |
| 2 | MLXAudioSTT API does not accept raw audio arrays (only file URLs) | MEDIUM | Wrap audio buffer in temporary file for transcription; managed by AudioCapture |
| 3 | Nemotron model exceeds 756 MB RAM footprint on M1 16 GB baseline | MEDIUM | Measure with Instruments; consider 4-bit variant if needed |
| 4 | Audio callback blocking causes glitches or dropped frames | HIGH | Strict non-blocking discipline; dispatch all work to background queue |
| 5 | Accessibility permission denied blocks paste/Return simulation | MEDIUM | Clear pre-request explanation; settings deep-link; degrade gracefully to clipboard-only |
| 6 | Global hotkey detection unreliable when app is backgrounded | MEDIUM | Prefer Carbon RegisterEventHotKey over NSEvent global monitor |
| 7 | Mixed Chinese-English transcription quality inadequate | MEDIUM | Validate with real bilingual speech samples; document limitation if WER unacceptable |
| 8 | Model download fails or corrupts | LOW | Retry logic; SHA verification; manual download fallback with documented path |

## Open Questions

1. Does `GLMASRModel.generate(audio:)` accept raw `[Float]` / `AVAudioPCMBuffer` or require file URL?
2. What is the exact memory footprint of Nemotron 0.6B 8-bit on M1 with MLX runtime?
3. Does mlx-audio-swift main branch compile with Swift 6 in Xcode 15+/16?
4. What is the optimal buffer size for audio tap to balance latency vs. CPU overhead?
5. Does the model require explicit language hinting for mixed Chinese-English, or auto-detect reliably?

## References

1. **mlx-audio-swift Repository** – https://github.com/Blaizzy/mlx-audio-swift
2. **Nemotron 3.5 ASR 0.6B 8-bit (Hugging Face)** – https://huggingface.co/mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
3. **NVIDIA Nemotron Original** – https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
4. **AVAudioEngine Documentation** – https://developer.apple.com/documentation/avfaudio/avaudioengine
5. **NSEvent Documentation** – https://developer.apple.com/documentation/appkit/nsevent
6. **XCTest Framework** – https://developer.apple.com/documentation/xctest
7. **AXIsProcessTrusted / Accessibility** – ApplicationServices Framework Reference
8. **VoiceDock Master Prompt** – `VOICEDOCK_MASTER_PROMPT.md`
9. **AGENTS.md** – Engineering constitution for VoiceDock