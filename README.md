# VoiceDock

**Native macOS menu bar push-to-talk speech-to-text**

VoiceDock is a native macOS application that provides global push-to-talk speech transcription. Press a keyboard shortcut, speak, and your speech is transcribed locally, copied to the clipboard, and pasted into the focused application.

## Features

- **Global Push-to-Talk**: `Control+Option+Space`
- **Local Processing**: Speech recognition runs on-device
- **Multilingual**: English, Mandarin Chinese, and code-switched speech
- **Clipboard Delivery**: Transcript is copied to the clipboard
- **Automatic Paste**: Transcript can be inserted into the focused application
- **Menu Bar App**: Lightweight macOS popover interface
- **Privacy First**: No telemetry and no transcript history

## How It Works

```text
1. Hold Control+Option+Space
2. Speak into the microphone
3. Release the shortcut
4. Nemotron ASR transcribes locally
5. Transcript is copied to the clipboard
6. Transcript is pasted into the focused app
7. Return may be sent after paste in the current MVP build
```

## Current Status

**Candidate 6** is the first physically verified development baseline and the current rollback candidate.

**Candidate 7 Phase A** is complete (automated gates pass) and awaiting owner physical review.

| Verification item | Candidate 6 | Candidate 7 Phase A |
|---|---|---|
| Debug build | PASS | PASS |
| Release build | PASS | PASS |
| Automated tests | PASS — 24 tests | PASS — 46 tests |
| Character counter | ⚠️ Visible | ✅ Removed |
| Bottom button labels | ⚠️ Truncated | ✅ Redesigned (More menu) |
| Automatic paste | Hardcoded ON | ✅ User toggle (default ON) |
| Return after paste | Hardcoded ON | ✅ User toggle (default OFF) |
| Terminal safety | ❌ No suppression | ✅ Return suppressed |
| Physical verification | ✅ COMPLETE | ⏳ PENDING |

### Recognition-quality notes

The complete workflow is operational, but transcription quality is not yet uniformly polished:

- Pure English can be accurate, but some phrases are misrecognized.
- Mixed Chinese-English speech is preserved, but English words and product names may drift.
- The product name `VoiceDock` has occasionally been recognized as variants such as `Voice Docks`, `VoyStock`, or similar text.

Candidate 6 is therefore an **MVP baseline**, not the final polished release. Candidate 7 Phase A addresses UI cleanup and safer Return behavior. Phase B will address branding assets.

## Architecture

```text
VoiceDockApp/                    UI and macOS integration
├── VoiceDockApp.swift           App entry point
├── AppDelegate.swift            NSApplicationDelegate
├── MenuBarView.swift            SwiftUI menu-bar popover
├── HotKeyManager.swift          Carbon/NSEvent hotkey handling
└── PermissionManager.swift      Microphone and Accessibility status

VoiceDockCore/                   Reusable business logic
├── ASRProvider.swift            ASR protocol
├── MLXAudioSTTProvider.swift    Nemotron/MLX implementation
├── AudioCapture.swift           AVAudioEngine capture
├── AudioNormalizer.swift        Hardware format to 16 kHz mono Float32
├── TranscriptDestination.swift  Clipboard and CGEvent paste
├── SessionCoordinator.swift     Session state machine
└── VoiceDockError.swift         Error definitions
```

## System Requirements

- macOS 14.0 or later
- Apple Silicon Mac (`arm64`)
- Microphone permission
- Accessibility permission for simulated paste

## Dependencies

| Dependency | Version | Purpose |
|---|---|---|
| `mlx-audio-swift` | revision `3f6b055` | MLX audio and ASR integration |
| `mlx-swift` | `0.31.4` | MLX runtime |
| Nemotron ASR | `nemotron-3.5-asr-streaming-0.6b-8bit` | Local speech recognition |

## Build Instructions

### Prerequisites

```bash
brew install xcodegen
xcode-select --install
```

### Generate the Xcode project

```bash
xcodegen generate
```

### Build

```bash
xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

### Test

```bash
swift package describe
swift build
swift test

xcodebuild -project VoiceDock.xcodeproj \
  -scheme VoiceDock \
  -destination 'platform=macOS' \
  test
```

## Permissions

### Microphone

Used to capture audio for local transcription.

### Accessibility

Used to simulate paste with CGEvents. VoiceDock does not use Accessibility as a substitute for Apple Events; the required permission is explicitly macOS Accessibility permission.

## Privacy

VoiceDock is designed around local processing:

- Local microphone processing
- No telemetry
- No transcript history
- No cloud transcription
- No background upload of audio or transcripts

The first model download may require network access.

## Known Limitations

**Candidate 7 Phase A addresses issues 1-3 below:**

- ~~Candidate 6 still displays a diagnostic character counter in the popover.~~ **→ FIXED in Candidate 7 Phase A**
- ~~Some bottom-button labels are truncated in the current UI.~~ **→ FIXED in Candidate 7 Phase A**
- ~~Return-after-paste is active in the current MVP and can execute text when Terminal is focused.~~ **→ FIXED in Candidate 7 Phase A (default OFF, terminal suppression)**
- Recognition quality varies by phrase, accent, and code-switching.
- Product-name recognition is not yet vocabulary-adapted.
- The first model download is large.
- Intel Macs are not supported.
- Signing and notarization are not yet part of this checkpoint.

## Candidate 6 Identity

```text
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
```

The `.app` bundle, models, crash reports, raw logs, and local build products are intentionally excluded from the repository.

## Next Milestone: Candidate 7

### Phase A (Complete — Automated Gates Pass)

- ✅ Remove the visible character counter
- ✅ Improve popover layout and button labels (Retry, Refresh, More menu)
- ✅ Add explicit automatic paste control (default ON)
- ✅ Add explicit Return-after-paste control (default OFF)
- ✅ Add terminal safety (Return suppression for Terminal, iTerm2, Warp)
- ✅ Add 26 new automated tests

**Status**: Awaiting owner physical review. See `.loop/evidence/candidates/candidate-7-phase-a/OWNER_UI_REVIEW_REQUIRED.md`.

### Phase B (Pending — After Phase A Verification)

- Add the VoiceDock icon and updated screenshots
- Improve recognition documentation
- Consider vocabulary/prompt-bias for "VoiceDock" product name

### Candidate 7 Freeze (Pending — After Phase B)

- Freeze Candidate 7
- Perform Candidate 7 physical verification
- Consider signing/notarization (requires credentials)
- Consider v0.1.0 prerelease and public repository visibility

## Project Governance

- `AGENTS.md` — engineering rules
- `CLAUDE.md` — project-specific build instructions
- `PLANS.md` — roadmap
- `.loop/DECISIONS.md` — durable technical decisions
- `.loop/NOW.md` — current execution state
- `.loop/HANDOFF.md` — session handoff

## License

MIT License.
