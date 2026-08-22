# VoiceDock Current Execution State

**Last Updated**: 2026-07-27 — VoiceDock 0.2 RC1 source-sealing pass

## Status

```text
AUTOMATED ENGINEERING GATES COMPLETE
FINAL OWNER ACCEPTANCE PENDING
```

(This document is the single operational source of truth for live project
status. `.loop/HANDOFF.md` points here and does not maintain an independent
status.)

## Project

- **Project**: VoiceDock 0.2 RC1
- **Canonical repository**: `/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock-Stable-Identity-Accessibility-Fix`
- **Canonical source status**: clean release-sealing branch (`fix/stable-identity-accessibility`)
- **Baseline HEAD at seal start**: `61eea56ffbdd1a82331c4219cbb1ee2b319c02ec`
- The sealing commit itself is not recorded here until it exists.
- **Owner acceptance**: PENDING
- **Next milestone**: final artifact build → owner Quality/Fast/Accessibility/paste proof

The checkout at `/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock`
is legacy/superseded for VoiceDock 0.2. Do not merge, cherry-pick, rebase, or
copy files from it.

## Current Architecture (as implemented in source)

Native macOS menu-bar push-to-talk speech-to-text app. Local-only processing:
no telemetry, no transcript history, no cloud upload.

### ASR

- Active ASR family: **Qwen3-ASR** (MLX, via `mlx-audio-swift`).
- **Quality** = `qwen3-1.7b-4bit` (default selection)
- **Fast** = `qwen3-0.6b-8bit`
- Exactly **one active provider at a time**; the provider is created through
  `ASRProviderFactory` from the persistent model preference.
- Nemotron is retired from the active baseline (see
  `docs/decisions/VOICEDOCK_NEMOTRON_RETIREMENT.md`). Historical rollback
  references remain in code but are explicit-selection/retired only.

### Model preference & ModelStatus semantics

- The selected model is persisted through a shared `ASRPreferenceStore`.
- `ModelStatus.selectedModel` is the saved preference applied on next launch;
  `ModelStatus.activeModel` is set exactly once from the factory result after a
  provider has actually been created. A saved preference is never presented as
  Active before provider creation, and load failures are surfaced rather than
  silently falling back to Quality.
- Changing the selection requires **Apply & Restart**: the packaged restart
  helper (`voice-dock-restart-helper`, copied into `Contents/MacOS` via an
  XcodeGen CopyFiles phase) relaunches the app so the new selection becomes
  active.

### Delivery & safety

- Automatic paste into the focused application is gated on macOS
  **Accessibility permission**.
- Return-after-paste remains separately controlled and defaults OFF, with
  Return suppression for terminal applications
  (`TerminalApplicationClassifier`).
- Transcript correction (`TranscriptCorrectionEngine`,
  `PersonalTranscriptCorrectionEngine`) and delivery policy
  (`TranscriptDeliveryPolicy`, `TranscriptDeliveryPreferences`) exist in
  current source and are part of the delivery path.

### Runtime composition

```text
VoiceDockApp/        UI + macOS integration (AppDelegate, MenuBarView,
                     HotKeyManager, PermissionManager, RestartHelper)
VoiceDockCore/       Business logic framework (ASR providers/factory,
                     audio capture+normalization, SessionCoordinator,
                     delivery/correction policy, model storage/status)
```

Xcode unit tests run with **TEST_HOST isolation**: the test bundle loads into a
dedicated `VoiceDock.app` test host with injected recorders/stores so tests
cannot touch production diagnostics or preferences.

## Verification Record

Stage A of Qwen dual-model routing was previously owner-verified physically
(see `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md`). That
evidence applies to that stage only; it does not constitute final acceptance
for VoiceDock 0.2 RC1.

Historical per-stage test counts (24 / 26 / 46 / 50) are recorded in their own
stage documents and are intentionally not repeated here as current claims.
Current automated-gate results are produced by running the gates; see the
release-sealing evidence in this repository's git history for the seal-pass
record.

## Owner Acceptance (PENDING)

Final owner acceptance for 0.2 RC1 still requires:

1. Final artifact build from the sealed source HEAD
2. Owner physical proof: Quality model, Fast model, Accessibility-gated paste,
   paste/Return behavior
3. Explicit owner sign-off

Do not mark final acceptance complete until all three are recorded.
