# VoiceDock

**Native macOS menu bar push-to-talk speech-to-text**

VoiceDock is a native macOS application that provides global push-to-talk speech transcription. Press a keyboard shortcut, speak, and your speech is transcribed locally and pasted into the focused application.

## Features

- **Global Push-to-Talk**: Control+Option+Space triggers transcription from any app
- **Local Processing**: All speech recognition runs on-device — no cloud upload
- **Multilingual**: Supports English, Mandarin Chinese, and code-switched speech
- **Privacy First**: No telemetry, no transcript history, no background network activity
- **Menu Bar Design**: Lives in your menu bar, ready when you need it

## How It Works

```text
1. Press Control+Option+Space (global hotkey)
2. Speak into your microphone
3. Release hotkey to stop
4. Nemotron ASR transcribes locally
5. Transcript copies to clipboard
6. Automatic paste into focused app
7. Optional Return key sent
```

## Current Status

**Candidate 6** — Physically verified development baseline

| Gate | Status |
|------|--------|
| Debug Build | ✅ PASS |
| Release Build | ✅ PASS |
| Unit Tests | ✅ 58 tests PASS |
| Gate B (Hotkey Stability) | ✅ PASS |
| Gate C (Mandarin) | ✅ PASS |
| Gate C (English) | ⏳ PENDING |
| Gate C (Mixed) | ⏳ PENDING |
| Gate C (Paste) | ⏳ PENDING |
| Gate C (Stability) | ⏳ PENDING |

**Note**: Candidate 6 is not the final release. Final UI cleanup and complete Gate C verification pending.

## Architecture

```text
VoiceDockApp/ (UI Layer)
├── VoiceDockApp.swift      @main entry point
├── AppDelegate.swift       NSApplicationDelegate
├── MenuBarView.swift       SwiftUI view
├── HotKeyManager.swift     Carbon + NSEvent hybrid
└── PermissionManager.swift TCC permission prompts

VoiceDockCore/ (Business Logic Framework)
├── ASRProvider.swift       Protocol
├── MLXAudioSTTProvider.swift Nemotron implementation
├── AudioCapture.swift      AVAudioEngine, 16 kHz mono Float32
├── AudioNormalizer.swift   Format conversion
├── TranscriptDestination.swift Clipboard + CGEvent paste
├── SessionCoordinator.swift  State machine
└── VoiceDockError.swift    Error types
```

## System Requirements

- macOS 14.0 or later
- Apple Silicon (M1/M2/M3) — arm64 only
- Microphone access
- Accessibility permission (for paste simulation)

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| mlx-audio-swift | 3f6b055 | MLXAudioSTT, MLXAudioCore |
| mlx-swift | 0.31.4 | MLX runtime |
| ASR Model | nemotron-3.5-asr-streaming-0.6b-8bit | Local transcription |

## Build Instructions

### Prerequisites

```bash
# Install XcodeGen (if not installed)
brew install xcodegen

# Ensure Xcode command line tools are installed
xcode-select --install
```

### Generate Xcode Project

```bash
xcodegen generate
```

### Build Debug

```bash
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

### Build Release

```bash
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

### Run Tests

```bash
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -destination 'platform=macOS' \
  test
```

### Swift Package Manager (Tests Only)

```bash
swift package describe
swift build
swift test
```

## Permissions

VoiceDock requires two macOS permissions:

### Microphone Permission

**Purpose**: Capture audio for transcription

**XML Key**: `NSMicrophoneUsageDescription`

**User Prompt**: "VoiceDock needs microphone access to transcribe your speech locally. No audio is sent to the cloud or stored."

### Accessibility Permission

**Purpose**: Simulate paste (Cmd+V) into focused applications using CGEvents

**API**: `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions()`

**Note**: This is **Accessibility** permission — not Apple Events. The app will guide you to System Settings → Privacy & Security → Accessibility.

## Privacy

VoiceDock defaults to:

- ✅ Local microphone processing only
- ✅ No telemetry
- ✅ No transcript history
- ✅ No cloud upload
- ✅ No background network activity (except explicit model download)

## Known Limitations

### Current MVP Scope

**Included**:
- Global push-to-talk (Control+Option+Space)
- English transcription
- Mandarin transcription
- Mixed Chinese-English transcription
- Clipboard output + automatic paste
- Optional Return key

**Excluded** (future releases):
- Voice Activity Detection (VAD)
- Automatic endpointing
- Partial streaming transcripts
- Model selection/switching
- Model registry/management
- AI assistant / chat
- Conversation history
- Text-to-speech (TTS)
- Signing/notarization

### Technical Limitations

- Carbon hotkey registration may fall back to NSEvent (app-local only) on some systems
- Accessibility permission required for paste simulation
- Model download required on first launch (~500MB)
- arm64 only — no Intel Mac support

## Verification Evidence

Full verification evidence is maintained in `.loop/evidence/candidates/`.

### Candidate 6 Identity

```text
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
```

### Verified Tests (Candidate 6)

```text
swift package describe: PASS
swift build: PASS
swift test: PASS (20 XCTest)
xcodegen generate: PASS
xcodebuild Debug build: PASS
xcodebuild Debug test: PASS (58 tests)
xcodebuild Release build: PASS
codesign verify: PASS
Info.plist lint: PASS
Gate B (hotkey stability): PASS
Gate C (Mandarin): PASS ("好了，好，你能听到吗？")
```

## Project Governance

This project follows structured engineering practices:

- `AGENTS.md` — Engineering constitution
- `CLAUDE.md` — Build system and project instructions
- `PLANS.md` — Roadmap and milestones
- `.loop/DECISIONS.md` — Technical decisions
- `.loop/NOW.md` — Current execution state
- `.loop/HANDOFF.md` — Session handoff notes

## License

MIT License — see LICENSE file (if present)

## Trademark Notice

VoiceDock is a development project name. All trademarks belong to their respective owners.