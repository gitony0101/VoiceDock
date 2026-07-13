# VoiceDock Handoff

**Last Updated**: 2026-07-13 (Stage A COMPLETE — OWNER VERIFIED)

## Executive Summary

Qwen Dual-Model Routing Stage A is **COMPLETE — OWNER VERIFIED**.

**Default ASR model**: Qwen3-ASR 1.7B 4-bit (Quality)
**Fast ASR model**: Qwen3-ASR 0.6B 8-bit (via `VOICEDOCK_ASR_MODEL`)
**Nemotron status**: Retired from active baseline; retained for Stage B rollback

## Automated Verification (Complete)

| Check | Result |
|-------|--------|
| `swift test` | ✅ 26 tests passed |
| `xcodegen generate` | ✅ Success |
| `xcodebuild` Debug | ✅ BUILD SUCCEEDED |
| `xcodebuild` Release | ✅ BUILD SUCCEEDED |
| `xcodebuild test` | ✅ 50 tests passed |
| `git diff --check` | ✅ No errors |

## Owner Physical Verification (Complete)

| Category | Result |
|----------|--------|
| Quality model (no env var) | ✅ Qwen3 1.7B 4-bit loads, warmups, transcribes |
| Fast model (env var) | ✅ Qwen3 0.6B 8-bit loads, warmups, transcribes |
| No Nemotron fallback | ✅ Confirmed |
| Routing (nil/empty/invalid) | ✅ Falls back to Quality |

**Evidence**: `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md`

## Repository Status

**Current branch**: `feat/candidate7-phase-b-branding`

**Dirty working tree**: Yes — multiple untracked production files from Qwen duel implementation.

### Untracked Production Files

| File | Description |
|------|-------------|
| `VoiceDockCore/Sources/ASRProviderFactory.swift` | Stage A routing |
| `VoiceDockCore/Sources/Qwen3ASRProvider.swift` | Qwen provider |
| `VoiceDockCore/Sources/QwenModelDescriptor.swift` | Qwen descriptors |
| `VoiceDockCore/Sources/ModelStorage.swift` | Model storage |
| `VoiceDockCore/Sources/ModelInstaller.swift` | Model installer |
| `VoiceDockCore/Sources/BenchmarkCore.swift` | Benchmark core |
| `VoiceDockAppTests/ASRProviderFactoryTests.swift` | Stage A tests |
| `VoiceDockAppTests/Qwen3ASRProviderTests.swift` | Qwen tests |
| `VoiceDockAppTests/QwenModelDescriptorTests.swift` | Descriptor tests |
| `VoiceDockAppTests/QwenModelStorageTests.swift` | Storage tests |
| `VoiceDockAppTests/QwenIntegrationTests.swift` | Integration tests |
| `Benchmarks/` | Benchmark suite |
| `docs/QWEN3_*.md` | Qwen investigation docs |
| `docs/RALPH_*.md` | Ralph duel docs |
| `docs/archive/qwen-duel/` | Archived duel evidence |

**Recommendation**: Review and commit these files as a coherent baseline before Stage B.

## Nemotron Rollback Components (Preserved)

| Component | Status |
|-----------|--------|
| `MLXAudioSTTProvider.swift` | ✅ Preserved |
| `ASRModelSelection.nemotron` | ✅ Preserved |
| `QwenModelDescriptor.nemotron_0_6B_8bit` | ✅ Preserved |
| Factory creation path | ✅ Preserved |

## Next Action

**Stage B — Nemotron Retirement Verification**

Before Stage B:
1. Owner confirms no rollback needed from Quality model
2. Review and commit untracked production files
3. Stage B will verify Nemotron can be safely removed

**Do NOT delete any Nemotron code or model data until Stage B approval.**

## How to Resume

### Continue Development
```bash
# Already on: feat/candidate7-phase-b-branding
# Review untracked files, then commit Stage A baseline
```

### Stage B Prerequisites
- ✅ Stage A automated gates passed
- ✅ Stage A owner physical verification passed
- ✅ Routing behavior verified
- ✅ Evidence document created
- ⏳ Owner confirmation: no rollback needed
- ⏳ Checkpoint commit of untracked files

### After Stage B Complete
1. Remove Nemotron code (if owner approves)
2. Clean up model data directories
3. Update documentation
4. Consider next product milestone
