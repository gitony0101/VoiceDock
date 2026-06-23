# VoiceDock Delivery Report

**Report Date**: 2026-06-23  
**Current Candidate**: Candidate 6 (rollback baseline)  
**Candidate 7 Phase A**: OWNER_VERIFIED  
**Status**: CANDIDATE7_PHASE_A_OWNER_VERIFIED — REPOSITORY_SUBMISSION_IN_PROGRESS

---

## Executive Summary

VoiceDock is a native macOS menu bar application for push-to-talk speech-to-text.

**Candidate 6** remains the frozen, physically verified rollback baseline.

**Candidate 7 Phase A** is owner-verified and ready for repository submission. Phase B (branding/icon) follows.

---

## Product Overview

### What VoiceDock Does

```text
User presses Control+Option+Space (global hotkey)
    ↓
Microphone captures speech
    ↓
Nemotron ASR transcribes locally (on-device)
    ↓
Transcript copied to clipboard
    ↓
Automatic paste into focused application
    ↓
Optional Return key sent
```

### Key Features

- **Global hotkey**: Control+Option+Space from any application
- **Local processing**: No cloud upload, all on-device
- **Multilingual**: English, Mandarin Chinese, code-switched speech
- **Privacy**: No telemetry, no transcript history
- **Menu bar design**: Unobtrusive, always available

---

## Build Verification

### Automated Gates (All Pass)

| Build Gate | Result | Date |
|------------|--------|------|
| swift package describe | ✅ PASS | 2026-06-23 |
| swift build | ✅ PASS | 2026-06-23 |
| swift test | ✅ PASS (46 tests) | 2026-06-23 |
| xcodegen generate | ✅ PASS | 2026-06-23 |
| xcodebuild Debug build | ✅ PASS | 2026-06-23 |
| xcodebuild Debug test | ✅ PASS (24 tests) | 2026-06-23 |
| xcodebuild Release build | ✅ PASS | 2026-06-23 |
| codesign verify | ✅ PASS | 2026-06-23 |
| Info.plist lint | ✅ PASS | 2026-06-23 |

**Note**: All tests use `MockASRProvider` and `MockAudioCapture`. No test exercises the real ASR pipeline.

---

## Candidate 6 Identity (Frozen Rollback Baseline)

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle ID: com.voicedock.app
Architecture: arm64
Signing: Ad-hoc (Sign to Run Locally)
Status: Frozen, physically verified
```

---

## Candidate 7 Phase A.1 Identity (Owner Verified)

```text
Artifact: build/candidate-7-phase-a1-review/VoiceDock.app
SHA-256: eb442ac1bd26b0f3014e714e73aafa981a3cc5dd73100c9569c3ef359d5024f0
CDHash: 90a6083b2293c6fb0524fd2e7ae9ec2b100d0621
Bundle ID: com.voicedock.app
Architecture: arm64 (Apple Silicon only)
Signing: Ad-hoc
Status: Owner verified — NOT FROZEN
```

---

## Owner Physical Verification (Candidate 7 Phase A)

### UI Layout

| Test | Result |
|------|--------|
| Character counter absent | ✅ PASS |
| No empty character-counter gap | ✅ PASS |
| Retry Transcription fully visible | ✅ PASS |
| Refresh Status fully visible | ✅ PASS |
| More fully visible | ✅ PASS |
| No width-induced ellipsis | ✅ PASS |
| Two-row action layout readable | ✅ PASS |
| More menu actions available | ✅ PASS |

### Permissions

| Test | Result |
|------|--------|
| Microphone permission granted | ✅ PASS |
| Accessibility permission granted | ✅ PASS |

### Preferences and Delivery

| Test | Result |
|------|--------|
| Automatically paste transcript default ON | ✅ PASS |
| Press Return after paste default OFF | ✅ PASS |
| Preferences independent | ✅ PASS |
| Preferences persist after relaunch | ✅ PASS |
| TextEdit paste with Return OFF | ✅ PASS |
| TextEdit paste with Return ON (exactly one Return) | ✅ PASS |
| Paste OFF, clipboard still updates | ✅ PASS |
| No duplicate paste observed | ✅ PASS |
| No duplicate Return observed | ✅ PASS |

### Terminal Safety

| Test | Result |
|------|--------|
| Apple Terminal Return suppression | ✅ PASS |
| Transcript did not execute automatically | ✅ PASS |
| Return suppression happened before execution | ✅ PASS |
| VoiceDock remained alive | ✅ PASS |

*Note: iTerm2 and Warp physical tests were not performed in this session.*

### End-to-End and Stability

| Test | Result |
|------|--------|
| English session | ✅ PASS |
| Mandarin session | ✅ PASS |
| Mixed Chinese-English session | ✅ PASS |
| Ready → Listening → Transcribing → Delivering → Ready | ✅ PASS |
| Three-session stability | ✅ PASS |
| Process remained alive | ✅ PASS |
| New crash report | ✅ NONE |
| Real microphone-to-chat-input workflow | ✅ PASS |

---

## Recognition-Quality Limitations (Preserved)

| Aspect | Status | Notes |
|--------|--------|-------|
| English recognition accuracy | PARTIAL | Pipeline works; word accuracy varies |
| Mixed-language recognition accuracy | PARTIAL | Code-switching supported; accuracy varies |
| VoiceDock product-name recognition | NEEDS IMPROVEMENT | Model misrecognizes as "Voice Docks", "VoyStock", etc. |

---

## Architecture Overview

### Source Structure

```text
VoiceDockApp/ (UI Layer)
├── VoiceDockApp.swift      @main entry point
├── AppDelegate.swift       NSApplicationDelegate
├── MenuBarView.swift       SwiftUI view
├── HotKeyManager.swift     Carbon + NSEvent hybrid
└── PermissionManager.swift TCC permission prompts

VoiceDockCore/ (Business Logic)
├── ASRProvider.swift       Protocol
├── MLXAudioSTTProvider.swift Nemotron implementation
├── AudioCapture.swift      AVAudioEngine
├── AudioNormalizer.swift   Format conversion
├── TranscriptDestination.swift Clipboard + paste
├── SessionCoordinator.swift  State machine
└── VoiceDockError.swift    Error types

VoiceDockAppTests/
├── MockASRProvider.swift
├── MockAudioCapture.swift
├── AudioNormalizerTests.swift
├── TranscriptDestinationTests.swift
├── SessionCoordinatorTests.swift
└── AppDelegateIsolationTests.swift
```

### Dependencies

| Package | Revision | Purpose |
|---------|----------|---------|
| mlx-audio-swift | 3f6b0553188a921f635df54b5e20442001037336 | MLXAudioSTT, MLXAudioCore |
| mlx-swift | 0.31.4 | MLX runtime |

### ASR Model

```text
Model: mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
Format: 8-bit quantized
Languages: English, Mandarin Chinese, code-switched
```

---

## Privacy Behavior

VoiceDock defaults to:

- ✅ Local microphone processing only
- ✅ No telemetry
- ✅ No transcript history
- ✅ No cloud upload
- ✅ No background network activity (except explicit model download)

**XML Properties**:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceDock needs microphone access to transcribe your speech locally. No audio is sent to the cloud or stored.</string>
<key>LSUIElement</key>
<true/>
```

---

## Candidate Retention

| Candidate | Status | Retention |
|-----------|--------|-----------|
| 1-3 | Superseded | Summary only |
| 4 | Crashed | **KEEP** — Root cause evidence |
| 5 | Never tested | Summary only |
| 6 | Verified baseline | **KEEP** — Rollback candidate |
| 7 | Final release | Target |

After Candidate 7 verification:
- Keep: `dist/VoiceDock.app` (final), `dist/archive/candidate-6/` (rollback)
- Delete: Candidate 1-3, 5 `.app` bundles (retain summaries)
- Keep: Candidate 4 crash evidence

---

## Remaining Work

### Candidate 7 Phase B (PENDING)

1. VoiceDock icon integration
2. Updated README icon and screenshots
3. Recognition quality documentation improvements
4. Consider vocabulary/prompt-bias for "VoiceDock" product name

### Candidate 7 Freeze (PENDING — After Phase B)

1. Freeze Candidate 7
2. Perform Candidate 7 physical verification
3. Consider signing/notarization (requires credentials)
4. Consider v0.1.0 prerelease
5. Consider public repository visibility

---

## How to Build

```bash
# Generate Xcode project
xcodegen generate

# Debug build
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

# Release build
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Release \
  -destination 'platform=macOS' \
  build

# Tests
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -destination 'platform=macOS' \
  test
```

---

## Conclusion

**Candidate 6** is the frozen, physically verified rollback baseline.

**Candidate 7 Phase A** is owner-verified. Repository submission in progress.

**Candidate 7 Phase B** (branding/icon) follows repository submission.

---

**Report Status**: CANDIDATE7_PHASE_A_OWNER_VERIFIED  
**Next Milestone**: Phase B (branding/icon) → Candidate 7 freeze → Physical verification → v0.1.0 prerelease consideration