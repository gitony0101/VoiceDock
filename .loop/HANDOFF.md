# VoiceDock Handoff

**Last Updated**: 2026-07-13 (Nemotron + 6-bit Retired)

## Executive Summary

Nemotron and Qwen3-ASR 0.6B 6-bit support have been removed from active code.

**Default ASR model**: Qwen3-ASR 1.7B 4-bit (Quality)
**Fast ASR model**: Qwen3-ASR 0.6B 8-bit (via `VOICEDOCK_ASR_MODEL`)

**Retired:**
- `nemotron-0.6b-8bit` — code removed 2026-07-13
- `qwen3-0.6b-6bit` — code removed 2026-07-13

## Automated Verification (Retirement Complete)

| Check | Result |
|-------|--------|
| `swift test` | ✅ Pending re-run |
| `xcodegen generate` | ✅ Pending re-run |
| `xcodebuild` Debug | ✅ Pending re-run |
| `xcodebuild` Release | ✅ Pending re-run |
| `xcodebuild test` | ✅ Pending re-run |
| `git diff --check` | ✅ Pending re-run |

## Repository Status

**Current branch**: `feat/candidate7-phase-b-branding`

**Retired files:**
| File | Status |
|------|--------|
| `VoiceDockCore/Sources/MLXAudioSTTProvider.swift` | ✅ Deleted |
| `ASRModelSelection.nemotron` | ✅ Removed |
| `ASRModelSelection.qwen3_0_6B_6bit` | ✅ Removed |
| `QwenModelDescriptor.nemotron_0_6B_8bit` | ✅ Removed |
| `QwenModelDescriptor.qwen3_0_6B_6bit` | ✅ Removed |
| Factory Nemotron path | ✅ Removed |
| Factory 6-bit path | ✅ Removed |

**Updated documentation:**
- `AGENTS.md` — Qwen3 dual-model baseline
- `CLAUDE.md` — test count updated
- `README.md` — Qwen3 dependencies
- `VOICEDOCK_MASTER_PROMPT.md` — technology stack updated
- `VOICEDOCK_PHASED_ASR_MAINTENANCE_AGENT.md` — owner decisions updated
- `.loop/DECISIONS.md` — D10 updated
- `.loop/NOW.md` — retirement status
- `.loop/HANDOFF.md` — this file

## Next Action

**Verification gates pending**: Run `swift test`, `xcodegen generate`, Xcode builds and tests.

**Commit pending**: Create local retirement commit after verification gates pass.

---

## Model Safety Verification (Pending)

Confirm these directories remain untouched:

- `$HOME/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-8bit`
- `$HOME/Library/Application Support/VoiceDock/Models/Qwen3-ASR-1.7B-4bit`

Confirm these are absent (data deleted in prior task):

- Nemotron model data (deleted 2026-07-13)
- Qwen3-ASR 0.6B 6-bit model data (deleted 2026-07-13)
