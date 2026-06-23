# VoiceDock Project Plan

## Project Status

```text
CANDIDATE7_PHASE_A_AUTOMATED_COMPLETE — OWNER_PHYSICAL_REVIEW_REQUIRED
```

## Current Release Candidate

**Candidate 6** — First physically verified development baseline (frozen, rollback)

**Candidate 7 Phase A** — Development review build (NOT FROZEN)

```text
Candidate 6 Artifact: dist/candidate-6/VoiceDock.app
Candidate 6 SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
Candidate 6 CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4

Candidate 7 Phase A Artifact: build/candidate-7-phase-a-review/VoiceDock.app
Candidate 7 Phase A SHA-256: 29e5b609bb4f7d15c8d6ee7cdbb608cdd688500984129506170191fb87941763
Candidate 7 Phase A CDHash: e02c039216a37a4330bc547b145ea39cbb18ab86
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

### Gate C Verification (2026-06-23)
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

### Candidate 7 Phase A (2026-06-23) — AUTOMATED COMPLETE
- ✅ Character counter removed
- ✅ Bottom action area redesigned (Retry, Refresh, More menu)
- ✅ Independent paste and Return preferences
- ✅ Default paste: ON (migration-safe)
- ✅ Default Return: OFF (safer than Candidate 6)
- ✅ Terminal safety suppression (before event synthesis)
- ✅ 26 new automated tests (46 total SwiftPM, 24 total Xcode)
- ⏳ Owner physical review: PENDING

## Remaining Milestones

### Candidate 7 Phase A — Owner Physical Review (PENDING)

See `.loop/evidence/candidates/candidate-7-phase-a/OWNER_UI_REVIEW_REQUIRED.md`

- [ ] UI verification (char counter absent, action labels readable)
- [ ] Preference defaults (paste=ON, return=OFF)
- [ ] Preference persistence (relaunch test)
- [ ] Clipboard-only delivery (paste OFF)
- [ ] Paste without Return (default)
- [ ] Paste with Return (non-terminal)
- [ ] Terminal safety (Apple Terminal, iTerm2, Warp)
- [ ] Three-session stability (English, Mandarin, Mixed)

After owner verification:
- [ ] Commit and push to `origin/feat/candidate7-release-polish`

### Candidate 7 Phase B (PENDING — After Phase A Verification)

- [ ] VoiceDock icon integration
- [ ] Updated README icon and screenshots
- [ ] Recognition quality documentation improvements
- [ ] Consider vocabulary/prompt-bias for "VoiceDock" product name

### Candidate 7 Freeze (PENDING — After Phase B)

- [ ] Freeze Candidate 7
- [ ] Perform Candidate 7 physical verification
- [ ] Consider signing/notarization (requires credentials)
- [ ] Consider v0.1.0 prerelease
- [ ] Consider public repository visibility

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