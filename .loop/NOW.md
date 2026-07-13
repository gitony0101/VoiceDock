# VoiceDock Current Execution State

**Last Updated**: 2026-07-13 (Stage A COMPLETE — OWNER VERIFIED)

## Status

```text
QWEN_DUAL_MODEL_ROUTING_STAGE_A_OWNER_VERIFIED
```

## ASR Model Configuration (Stage A)

| Model | Role | Selection |
|-------|------|-----------|
| `qwen3-1.7b-4bit` | **Quality (DEFAULT)** | No env var, or explicit |
| `qwen3-0.6b-8bit` | **Fast** | `VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit` |
| `qwen3-0.6b-6bit` | Preserved | Explicit selection only |
| `nemotron-0.6b-8bit` | Rollback | Explicit selection only (Stage B) |

**Owner dogfooding**: `qwen3-1.7b-4bit` (Quality)

## Stage A Automated Verification

| Check | Result |
|-------|--------|
| `swift test` | ✅ 26 tests |
| `xcodegen generate` | ✅ Success |
| `xcodebuild` Debug | ✅ BUILD SUCCEEDED |
| `xcodebuild` Release | ✅ BUILD SUCCEEDED |
| `xcodebuild test` | ✅ 50 tests |
| `git diff --check` | ✅ No errors |

## Stage A Owner Physical Verification

| Category | Result |
|----------|--------|
| Quality model (no env var) | ✅ PASS — Qwen3 1.7B 4-bit loads, warmups, transcribes |
| Fast model (env var) | ✅ PASS — Qwen3 0.6B 8-bit loads, warmups, transcribes |
| No Nemotron fallback | ✅ Confirmed — failures remain visible |
| Routing behavior | ✅ Verified — nil/empty/invalid → Quality |

**Evidence**: `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md`

## Repository Status

**Current branch**: `feat/candidate7-phase-b-branding`

**Dirty working tree**: Yes — multiple untracked production files from Qwen duel implementation. See evidence document for full inventory.

**Checkpoint recommendation**: Review and commit untracked production files before Stage B.

## Next Action

**Awaiting Stage B**: Nemotron retirement verification after owner confirms no rollback needed.

**Do not delete Nemotron code or model data until Stage B approval.**
