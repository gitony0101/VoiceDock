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
4. The active Qwen3-ASR model transcribes locally
5. Transcript is copied to the clipboard
6. Transcript is pasted into the focused app (Accessibility-gated)
7. Return may be sent after paste — separately controlled, default OFF
```

## Current Status

**VoiceDock 0.2 RC1** is the current release candidate line.

```text
AUTOMATED ENGINEERING GATES COMPLETE
FINAL OWNER ACCEPTANCE PENDING
```

Live operational status is maintained in `.loop/NOW.md`. Earlier baselines
(Candidate 6, Candidate 7 Phase A/B) are historical; their verification tables
and artifact identities are preserved in their own stage documents and are not
repeated here as current claims.

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
├── UI/MenuBarView.swift         SwiftUI menu-bar popover
├── Services/HotKeyManager.swift Carbon/NSEvent hotkey handling
├── Services/PermissionManager.swift Microphone and Accessibility status
└── RestartHelper/               Packaged restart helper (Apply & Restart)

VoiceDockCore/                   Reusable business logic
├── ASRProvider.swift            Model-agnostic ASR protocol (actor)
├── Qwen3ASRProvider.swift       Active Qwen3-ASR implementation
├── ASRProviderFactory.swift     Quality/Fast model routing (one active provider)
├── ASRModelPreferences.swift    Persistent model preference
├── ModelStatus.swift            Selected-vs-active model state tracking
├── ModelStorage.swift           Local model storage
├── AudioCapture.swift           AVAudioEngine capture
├── AudioNormalizer.swift        Hardware format to 16 kHz mono Float32
├── TranscriptDestination.swift  Clipboard and CGEvent paste
├── TranscriptDeliveryPolicy.swift   Delivery policy (paste/Return safety)
├── TranscriptCorrectionEngine.swift Transcript correction
├── SessionCoordinator.swift     Session state machine
└── VoiceDockError.swift         Error definitions
```

### ASR models

| Role | Model | Selection |
|---|---|---|
| Quality (default) | `qwen3-1.7b-4bit` | No env var, or explicit |
| Fast | `qwen3-0.6b-8bit` | UI menu or `VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit` |

Exactly one provider is active at a time. The selection is persisted; changing
it takes effect through **Apply & Restart**, which uses the packaged restart
helper to relaunch the app. `ModelStatus` distinguishes the *selected* model
(saved preference for next launch) from the *active* model (the provider that
was actually created). Nemotron is retired from the active baseline — see
`docs/decisions/VOICEDOCK_NEMOTRON_RETIREMENT.md`.

### Automatic paste and Return

Automatic paste into the focused application is gated on macOS Accessibility
permission. Return-after-paste is a separate control, default OFF, with Return
suppression for terminal applications (`TerminalApplicationClassifier`).

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
| Qwen3-ASR | `qwen3-1.7b-4bit` (Quality, default) / `qwen3-0.6b-8bit` (Fast) | Local speech recognition |

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

- Recognition quality varies by phrase, accent, and code-switching.
- Product-name recognition is not yet vocabulary-adapted.
- The first model download is large.
- Intel Macs are not supported.
- Signing and notarization are not yet part of this checkpoint.

Historical note (Candidate 6 era): a diagnostic character counter, truncated
button labels, and unsafe Return-after-paste existed in that baseline. These
were addressed in the Candidate 7 line and are retained here only as history.

## Historical Baseline Identity (Candidate 6 — superseded)

```text
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
```

This identity belongs to the retired Candidate 6 artifact, not to the current
0.2 RC1 line.

The `.app` bundle, models, crash reports, raw logs, and local build products are intentionally excluded from the repository.

## Next Milestone: VoiceDock 0.2 RC1 Final Acceptance

- ✅ Source sealing on the `fix/stable-identity-accessibility` branch
- ⏳ Final artifact build from the sealed source HEAD
- ⏳ Owner physical proof: Quality model, Fast model,
  Accessibility-gated paste, paste/Return behavior
- ⏳ Explicit owner sign-off
- Consider signing/notarization (requires credentials)

## Project Governance

- `AGENTS.md` — engineering rules
- `CLAUDE.md` — project-specific build instructions
- `PLANS.md` — roadmap
- `.loop/DECISIONS.md` — durable technical decisions
- `.loop/NOW.md` — current execution state
- `.loop/HANDOFF.md` — session handoff

## License

MIT License.
