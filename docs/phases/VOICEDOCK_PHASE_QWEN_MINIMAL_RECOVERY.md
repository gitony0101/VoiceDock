# VoiceDock Qwen Minimal Recovery

## Objective

Recover a stable Qwen-only daily driver from exact commit cfbfdb21.

Keep:

- qwen3-1.7b-4bit as Quality/default
- qwen3-0.6b-8bit as Fast
- real PTT
- automatic paste
- Press Return after paste OFF

Remove production routing for:

- Nemotron
- qwen3-0.6b-6bit

## Verified Baseline

Exact clean cfbfdb21 has already physically proven:

- Qwen3-ASR 1.7B selection
- model validation
- model load
- warmup
- Coordinator Ready
- real multilingual PTT
- transcription
- paste

The test used an isolated CFFIXED_USER_HOME and did not change the canonical manifest.

Do not call quit passed or failed. Classify historical quit as delayed or inconclusive.

## Scope

This phase recovers a minimal Qwen-only runtime from a known-good commit. It strips unproven model routing, focuses on two supported identifiers, and hardens the quit lifecycle.

## Explicit Non-Goals

- No VAD
- No streaming
- No model switching UI
- No general model registry
- No external model folders
- No AI assistant
- No TTS
- No signing or notarization work

## Ownership Contracts

MenuBarView Quit:

1. record click timestamp
2. call NSApplication.shared.terminate(nil) once

AppDelegate:

- sole AppKit termination owner
- first applicationShouldTerminate starts cleanup and returns .terminateLater
- repeated requests do not start duplicate cleanup
- cleanup completion or timeout calls exactly once:

NSApplication.shared.reply(toApplicationShouldTerminate: true)

- never call terminate(nil) again after cleanup
- applicationWillTerminate performs final idempotent synchronous cleanup only

SessionCoordinator:

- cleans recording, transcription, and model resources
- never calls NSApplication.shared.terminate(nil)
- never calls reply(toApplicationShouldTerminate:)
- repeated cleanup is idempotent

Hotkey:

- AppDelegate strongly retains exactly one HotKeyManager
- callbacks weakly capture AppDelegate
- callbacks resolve the current coordinator at event time
- release is ignored when the corresponding press was rejected

## Model-Routing Contract

ASRProviderFactory is the single production selection source.

Supported identifiers exactly:

- qwen3-1.7b-4bit
- qwen3-0.6b-8bit

Missing, empty, invalid, or retired values select Quality.
Invalid or retired values also emit a warning.
No production route may instantiate Nemotron.

## Allowed Files

- VoiceDockApp/AppDelegate.swift
- VoiceDockApp/UI/MenuBarView.swift, Quit wiring only
- VoiceDockCore/Sources/SessionCoordinator.swift
- VoiceDockCore/Sources/ASRProviderFactory.swift
- VoiceDockCore/Sources/QwenModelDescriptor.swift
- Qwen3ASRProvider.swift only if a call-site audit proves necessary
- relevant tests
- project.yml only for test declarations
- README.md only after all runtime gates pass
- current phase documentation

## Forbidden Files

The following are unchanged and unevaluated:

- ModelStorage.swift
- ModelInstaller.swift
- ModelLifecycleCoordinator or equivalent
- manifest schemas
- migration
- adoption
- model registry
- download behavior
- AudioCapture.swift
- TranscriptDestination.swift
- PermissionManager.swift
- Info.plist
- icons and branding
- canonical models and manifests
- main worktree

Do not describe these as stable or transactional.

## Implementation Sequence

1. Audit ASRProviderFactory for supported identifiers
2. Remove Nemotron and retired qwen3-0.6b-6bit routing
3. Wire QwenModelDescriptor validation
4. Harden AppDelegate quit lifecycle
5. Wire SessionCoordinator cleanup idempotency
6. Add HotKeyManager weak-capture callbacks
7. Write unit tests for factory and quit contract
8. Run Debug and Release builds
9. Execute runtime verification gates

## Unit Test Matrix

Cover:

- supported identifiers equal exactly Quality and Fast
- missing and empty values select Quality
- invalid and retired values select Quality and emit warning
- retired identifiers cannot instantiate their former providers
- AppDelegate retains HotKeyManager
- callback resolves current coordinator
- rejected press followed by release does not stop recording
- coordinator cleanup cannot terminate the app
- first termination request returns .terminateLater
- repeated requests do not duplicate cleanup
- Menu Quit initiates terminate exactly once
- cleanup success sends one AppKit reply
- timeout sends one AppKit reply
- applicationWillTerminate is idempotent

Do not describe terminate(nil) as the AppKit reply.

## Runtime Verification Gates

Gate 1:
Debug build, Release build, and complete tests pass.

Gate 2:
Record commit, app path, executable SHA-256 and UUID, framework SHA-256 and UUID, and PID. Prove isolated Qwen 1.7B load, warmup, and Ready. Canonical manifest SHA-256 must remain unchanged.

Gate 3:
Three separate PTT recordings: English, Mandarin, mixed Chinese-English.

Gate 4:
Transcript automatically appears in the focused application. Clipboard is only the intermediary. Return remains OFF, cursor stays on the same line, and no submission occurs.

Gate 5:
Record click, applicationShouldTerminate, cleanup completion, AppKit reply, and PID-exit timestamps. Maximum exit latency is 10 seconds. No forced kill.

## Safety Constraints

Use:

CFFIXED_USER_HOME=/tmp/VoiceDock-Recovery-Qwen-Home

and unique DerivedData:

/tmp/VoiceDock-Recovery-Qwen-DD-<timestamp>

Never delete canonical Application Support, historical apps, or historical DerivedData.

## Rollback Plan

If validation fails:

1. halt the worktree
2. preserve all logs and SHA-256 evidence
3. restore exact commit cfbfdb21
4. document the failure mode
5. await owner review

## Completion Marker

AUTOMATED_GATES_COMPLETE_MANUAL_VERIFICATION_PENDING

## Future Phase Note

- raw transcript
- deterministic corrected transcript
- optional meaning-preserving rewrite

No current implementation.
