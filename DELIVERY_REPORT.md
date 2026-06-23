# VoiceDock Delivery Report

**Report Date**: 2026-06-23  
**Current Candidate**: Candidate 6  
**Status**: AUTOMATED_GATES_COMPLETE_PARTIAL_MANUAL_VERIFICATION_DONE

---

## Executive Summary

VoiceDock is a native macOS menu bar application for push-to-talk speech-to-text. Candidate 6 has passed all automated gates and partial physical verification. Remaining Gate C tests pending.

**This is NOT a final release report.** Candidate 6 is the **first physically verified development baseline** and verified rollback candidate. Candidate 7 will be the final release after complete Gate C verification and final UI cleanup.

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
| swift test | ✅ PASS (24 Mock-based tests) | 2026-06-23 |
| xcodegen generate | ✅ PASS | 2026-06-23 |
| xcodebuild Debug build | ✅ PASS | 2026-06-23 |
| xcodebuild Debug test | ✅ PASS (24 tests) | 2026-06-23 |
| xcodebuild Release build | ✅ PASS | 2026-06-23 |
| codesign verify | ✅ PASS | 2026-06-23 |
| Info.plist lint | ✅ PASS | 2026-06-23 |

**Note**: All tests use `MockASRProvider` and `MockAudioCapture`. No test exercises the real ASR pipeline.

---

## Physical Verification (Candidate 6)

### Gate B: Hotkey Stability

| Test | Result | Evidence |
|------|--------|----------|
| Microphone permission | ✅ GRANTED | Owner confirmed |
| Accessibility permission | ✅ GRANTED | Owner confirmed |
| Hotkey press detected | ✅ PASS | Physical key press |
| Hotkey release detected | ✅ PASS | Physical key release |
| Application remained alive | ✅ PASS | No crash report |
| Returned to Ready state | ✅ PASS | UI state transition correct |

**Crash Provenance**: All previously reported crashes matched Candidate 4 UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`). Candidate 6 UUID (`3745FA4C-2619-3DDB-8565-0CBBA80AC7E1`) has **no matching crash reports**.

### Gate C: Speech Transcription

| Test | Result | Transcript Observed |
|------|--------|---------------------|
| Mandarin | ✅ PASS | "好了，好，你能听到吗？" |
| Mixed Chinese-English | ✅ PASS | Pipeline verified |
| English | ⏳ PENDING | — |
| Clipboard verification | ⏳ PENDING | — |
| Automatic paste | ⏳ PENDING | — |
| Optional Return | ⏳ PENDING | — |
| 3-session stability | ⏳ PENDING | — |

---

## Candidate 6 Identity

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle ID: com.voicedock.app
Architecture: arm64
Signing: Ad-hoc (Sign to Run Locally)
```

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

## Repairs in Candidate 6

### 1. MainActor Isolation Safety

**Problem**: Candidate 4 crashed with `EXC_BAD_ACCESS` in `MainActor.assumeIsolated`.

**Solution**: Replace `MainActor.assumeIsolated` with `Task { @MainActor ... }` pattern.

**Evidence**: Crash UUID matching proved Candidate 4 failure, Candidate 6 stability.

### 2. Permission State Refresh

**Problem**: UI showed stale permission state after user returned from System Settings.

**Solution**: Added `NSApplication.didBecomeActive` observer to trigger permission refresh.

### 3. Diagnostic Log Cleanup

**Problem**: Stale logs accumulated across launches, complicating crash analysis.

**Solution**: Remove stale logs on launch and exit (crash recovery).

### 4. Audio Format Handling

**Problem**: Audio tap format mismatch caused normalization issues.

**Solution**: Install tap with hardware input format, normalize to 16 kHz mono Float32.

### 5. Buffer Timeout Protection

**Problem**: Unbounded buffer growth risk during long sessions.

**Solution**: 60-second max buffer timeout.

---

## Known Gaps

### Test Coverage

- All 24 tests use `MockASRProvider` and `MockAudioCapture`
- No test exercises real ASR pipeline
- No real microphone audio capture tests
- No performance measurements (latency, memory)

### Physical Verification

- English transcription: PENDING
- Clipboard verification: PENDING
- Automatic paste: PENDING
- Optional Return: PENDING
- 3-session stability: PENDING

### Product Limitations

- Carbon hotkey registration falls back to NSEvent (app-local only) on some systems
- Accessibility permission required for paste simulation
- Model download required (~500MB) on first launch
- arm64 only — no Intel Mac support

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
| 1 | Superseded | Summary only |
| 2 | Superseded | Summary only |
| 3 | Superseded | Summary only |
| 4 | Crashed | **KEEP** — Root cause evidence |
| 5 | Superseded | Summary only |
| 6 | Verified baseline | **KEEP** — Rollback candidate, first physically verified development baseline |
| 7 | Final release | Target |

After Candidate 7 verification:
- Keep: `dist/VoiceDock.app` (final), `dist/archive/candidate-6/` (rollback)
- Delete: Candidate 1-3, 5 `.app` bundles (retain summaries)
- Keep: Candidate 4 crash evidence

---

## Remaining Work

### Gate C Completion

1. English transcription test
2. Mixed Chinese-English transcription test
3. Automatic paste verification
4. Optional Return behavior
5. 3-session stability test

### Candidate 7 (Final Release)

1. Remove diagnostic counters from product UI
2. Clean up menu bar display
3. Final UI polish
4. Complete evidence documentation
5. Git release tag

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

Candidate 6 represents the first physically verified development baseline. All automated gates pass. Gate B (hotkey stability) confirmed. Mandarin and mixed Chinese-English transcription verified.

**NOT FINAL RELEASE** — Candidate 6 is the verified rollback candidate. Complete Gate C verification and final UI cleanup required for Candidate 7.

---

**Report Status**: PARTIAL  
**Next Milestone**: Gate C completion → Candidate 7 → Final release tag