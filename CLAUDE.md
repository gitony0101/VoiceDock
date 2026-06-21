# VoiceDock

@AGENTS.md

## Current Repository State

The previous generated implementation was intentionally deleted.

Treat this repository as a clean documentation-first reset.

Do not restore deleted source files, `Package.swift`, tests, scripts, generated scaffolding, or legacy `.loop/` files merely because they exist in Git history.

The active Smart Ralph specification under `specs/` is the only execution state.

## Active Release

The current release is the VoiceDock Push-to-Talk MVP.

Before planning scope, architecture, or acceptance criteria, read:

* `VOICEDOCK_MASTER_PROMPT.md`

## Fixed MVP Technology

Use:

* Swift 6
* SwiftUI
* AppKit where required
* AVFoundation and AVAudioEngine
* native Xcode macOS application target
* `Blaizzy/mlx-audio-swift`
* Swift product `MLXAudioSTT`
* model `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit`

Do not replace the primary ASR path with:

* WhisperKit
* Apple Speech
* Python inference
* NVIDIA NeMo runtime
* Electron
* Tauri
* subprocess workers
* local HTTP servers

## Execution

Use Smart Ralph for planning, task decomposition, implementation, verification, progress persistence, and continuation.

Resume persisted work before creating new work.

Work on one coherent task at a time.

Run builds and tests in the foreground and preserve their actual exit codes.

Commit only verified green work locally.

Do not push or create a remote repository.

Continue automatically until the current MVP is verified or a genuine owner-only external action is required.

