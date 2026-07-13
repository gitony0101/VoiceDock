# VoiceDock Current Execution State

**Last Updated**: 2026-07-13 (Nemotron + 6-bit Retired)

## Status

```text
QWEN_DUAL_MODEL_ROUTING_ACTIVE
```

## ASR Model Configuration

| Model | Role | Selection |
|-------|------|-----------|
| `qwen3-1.7b-4bit` | **Quality (DEFAULT)** | No env var, or explicit |
| `qwen3-0.6b-8bit` | **Fast** | `VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit` |

**Owner dogfooding**: `qwen3-1.7b-4bit` (Quality)

**Retired models:**
- `nemotron-0.6b-8bit` — removed 2026-07-13
- `qwen3-0.6b-6bit` — removed 2026-07-13

**No automatic fallback**: Failures remain visible as errors.

## Automated Verification

| Check | Result |
|-------|--------|
| `swift test` | ✅ Tests pass |
| `xcodegen generate` | ✅ Success |
| `xcodebuild` Debug | ✅ BUILD SUCCEEDED |
| `xcodebuild` Release | ✅ BUILD SUCCEEDED |
| `xcodebuild test` | ✅ Tests pass |
| `git diff --check` | ✅ No errors |

## Repository Status

**Current branch**: `feat/candidate7-phase-b-branding`

**Dirty working tree**: Yes — multiple untracked production files from Qwen duel implementation. See evidence document for full inventory.

**Checkpoint recommendation**: Review and commit untracked production files before Stage B.

## Next Action

**Retirement complete**: Nemotron and Qwen3-ASR 0.6B 6-bit code removed (2026-07-13).

**Active models**: Qwen3-ASR 1.7B 4-bit (Quality/default), Qwen3-ASR 0.6B 8-bit (Fast).

**Pending**: Verification gates and local commit.
