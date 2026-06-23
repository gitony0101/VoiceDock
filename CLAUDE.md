# VoiceDock

@AGENTS.md

## Current Repository State (2026-06-22 — Refactored)

VoiceDock is a native macOS menu bar application for push-to-talk speech-to-text.

**Architecture**:
- `VoiceDockApp/` — UI layer (MenuBarView, AppDelegate, HotKeyManager, PermissionManager)
- `VoiceDockCore/` — Business logic (ASR, Audio, SessionCoordinator, TranscriptDestination)
- `VoiceDockAppTests/` — Unit tests (24 tests, Mock-based)

**Build System**:
- XcodeGen-generated Xcode project (`project.yml` is source of truth)
- Swift Package Manager for testing (`Package.swift`)
- Dependency: `Blaizzy/mlx-audio-swift` (MLX, MLXAudioSTT, MLXAudioCore)

**Current Status**:
- ✅ Debug build: PASS
- ✅ Release build: PASS  
- ✅ Unit tests: 24/24 PASS (Mock)
- ✅ Permission state refresh: FIXED (2026-06-22)
- ⏳ Manual M1 verification: PENDING (requires physical test)

Do not reset the repository, recreate the project from scratch, or repeat completed planning.

The active execution state is under:

* `specs/voicedock-ptt-mvp/`

Before changing product scope or acceptance criteria, read:

* `VOICEDOCK_MASTER_PROMPT.md`
* `docs/VOICELOCK_DEEP_AUDIT_REPORT.md` (project audit)

## Build-System Ownership

`project.yml` is the authoritative source for the Xcode project.

After changing Xcode targets, packages, settings, entitlements, Info.plist properties, or schemes:

1. update `project.yml`
2. run `xcodegen generate`
3. verify the regenerated project
4. rerun applicable Xcode builds and tests

Do not manually edit:

* `VoiceDock.xcodeproj/project.pbxproj`
* generated workspace package references
* generated Info.plist content

`Package.swift` may remain as the SwiftPM build and test definition only if it uses the same production sources without maintaining a duplicate implementation.

## Execution Mode

Continue the active Smart Ralph loop automatically.

Do not stop after planning, summaries, scaffolding, compilation milestones, refactoring checkpoints, or partial verification.

For every task:

observe
→ implement
→ verify
→ inspect
→ repair
→ update persisted state
→ continue

Product delivery takes priority over cosmetic refactoring and test-target perfection.

Do not widen scope beyond the Push-to-Talk MVP.

## Verification

A SwiftPM executable is not the final product artifact.

The final product must be a native `VoiceDock.app` built through Xcode.

**Completion Criteria** (per AGENTS.md):
- ✅ Debug build: `xcodebuild -scheme VoiceDock -configuration Debug build`
- ✅ Release build: `xcodebuild -scheme VoiceDock -configuration Release build`
- ✅ Unit tests: `xcodebuild -scheme VoiceDock test` (24 tests, Mock-based)
- ⏳ Manual M1 test: Physical microphone + ASR + paste verification **(PENDING)**

**Known Gaps** (from deep audit):
- Accessibility permission not granted in test runs → paste simulation skipped
- Carbon hotkey registration fails (error -9878) → falls back to NSEvent (app-local only)
- No real ASR inference tests — all transcription tests use `MockASRProvider`
- No performance measurements (latency, memory footprint)

**Fixed Issues** (2026-06-22):
- ✅ Permission state refresh bug — UI now updates live when user returns from System Settings
- ✅ Temporary log file cleanup — stale logs cleaned on launch + exit (crash recovery)
- ✅ TCC code-identity troubleshooting — Added diagnostic info + user guide in `docs/TCC_CODE_IDENTITY_TROUBLESHOOTING.md`

Do not claim completion until automated checks and required real-device checks have truthful evidence.

If owner interaction is required, finish all remaining automated work first and request only the exact permission or speech test needed.

## Git Mode

Do not push, create a remote, or publish the repository.

During the current autonomous run, do not create new commits unless the owner explicitly enables checkpoint commits.

