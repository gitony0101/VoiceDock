# VoiceDock Project Plan

## Project Status

```text
GATE_C_COMPLETE — CANDIDATE 6 VERIFIED BASELINE
```

## Current Release Candidate

**Candidate 6** — First physically verified development baseline (frozen)

**Note**: Candidate 6 is NOT the final release. It is the verified rollback candidate and first physically verified development baseline. Candidate 7 will be the final release.

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
```

## Completed Milestones

### Architecture (2026-06-22)
- ✅ Refactored to VoiceDockApp + VoiceDockCore split
- ✅ XcodeGen-based build system
- ✅ Swift Package Manager for testing
- ✅ 24 unit tests (Mock-based)

### Stability Fixes (2026-06-23)
- ✅ MainActor isolation safety (Candidate 4 crash fix)
- ✅ Permission state refresh on app activation
- ✅ Diagnostic log cleanup (crash recovery)
- ✅ Audio format handling (16 kHz mono Float32)
- ✅ Buffer timeout protection (60s max)

### Verification (2026-06-23)
- ✅ Debug build: PASS
- ✅ Release build: PASS
- ✅ Unit tests: 24 tests PASS (Mock-based)
- ✅ Codesign verification: PASS
- ✅ Info.plist validation: PASS
- ✅ Gate B (hotkey stability): PASS
- ✅ Gate C Mandarin: PASS
- ✅ Gate C English: PASS (pipeline)
- ✅ Gate C Mixed Chinese-English: PASS (pipeline)
- ✅ Gate C Clipboard: PASS
- ✅ Gate C Automatic paste: PASS
- ✅ Gate C Optional Return: PASS
- ✅ Gate C 3-session stability: PASS

## Remaining Milestones

### Candidate 7 (Final Release) — PENDING

1. Remove the visible `chars` counter from the public UI
2. Replace truncated bottom-button labels with clear accessible labels
3. Add separate automatic-paste and automatic-Return controls
4. Default automatic Return to OFF
5. Add terminal safety behavior for automatic Return
6. Add the approved VoiceDock icon
7. Add polished README icon and current screenshot
8. Improve recognition documentation and disclose model limitations
9. Investigate vocabulary or prompt-bias options for recognizing `VoiceDock`
10. Freeze Candidate 7 separately
11. Perform final physical Candidate 7 verification
12. Only after Candidate 7 verification consider public repository visibility and a `v0.1.0` prerelease

## Technology Stack

```text
Swift 6
SwiftUI + AppKit
AVFoundation / AVAudioEngine
MLX / MLXAudioSTT
Nemotron ASR (mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit)
```

## Architecture

```text
VoiceDockApp/ (UI Layer)
├── VoiceDockApp.swift      @main entry
├── AppDelegate.swift       NSApplicationDelegate
├── MenuBarView.swift       SwiftUI view
├── HotKeyManager.swift     Carbon + NSEvent
└── PermissionManager.swift TCC prompts

VoiceDockCore/ (Business Logic)
├── ASRProvider.swift       Protocol
├── MLXAudioSTTProvider.swift Implementation
├── AudioCapture.swift      AVAudioEngine
├── AudioNormalizer.swift   Format conversion
├── TranscriptDestination.swift Clipboard + paste
├── SessionCoordinator.swift  State machine
└── VoiceDockError.swift    Error types
```

## Build Commands

```bash
xcodegen generate
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Debug build
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Release build
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock test
```

## Candidate Retention

| Candidate | Status | Retention |
|-----------|--------|-----------|
| 1-3 | Superseded | Summary only |
| 4 | Crashed | Full evidence (root cause) |
| 5 | Never tested | Summary only |
| 6 | Verified baseline | Full artifact (rollback) |
| 7 | Final release | Target |