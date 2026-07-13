# VoiceDock Nemotron Retirement Record

**Date:** 2026-07-13  
**Status:** `NEMOTRON_MODEL_DATA_REMOVED`  
**Next Task:** Full Nemotron code removal

---

## 1. Original Model Information

| Property | Value |
|----------|-------|
| **Model name** | Nemotron-3.5-ASR-0.6B-8bit |
| **Hugging Face repository** | `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit` |
| **Canonical directory name** | `nemotron-3.5-asr-streaming-0.6b-8bit` |
| **Environment variable value** | `nemotron-0.6b-8bit` |
| **Provider file** | `VoiceDockCore/Sources/MLXAudioSTTProvider.swift` |
| **Model family** | `Nemotron-ASR` |

---

## 2. Original Loading Behavior

The Nemotron model was originally loaded through:

1. **Environment variable:** `VOICEDOCK_ASR_MODEL=nemotron-0.6b-8bit`
2. **Factory path:** `ASRProviderFactory.createProvider()` → `.nemotron` case → `MLXAudioSTTProvider()`
3. **Loading mechanism:** `NemotronASRModel.fromPretrained()` from MLXAudioSTT framework
4. **Model location:** `~/Library/Application Support/VoiceDock/Models/nemotron-3.5-asr-streaming-0.6b-8bit/`

---

## 3. Reason for Retirement

**Primary reason:** Qwen3-ASR models provide superior mixed-language (Chinese-English) recognition accuracy.

**Supporting factors:**
- Qwen3-ASR models are actively maintained
- Better performance on technical vocabulary
- Owner dogfooding preference for Qwen3-ASR 1.7B 4-bit
- No production users depend on Nemotron

---

## 4. Qwen Replacement Models

| Role | Model | Repository | Directory |
|------|-------|------------|-----------|
| **Quality (default)** | Qwen3-ASR 1.7B 4-bit | `mlx-community/Qwen3-ASR-1.7B-4bit` | `Qwen3-ASR-1.7B-4bit` |
| **Fast** | Qwen3-ASR 0.6B 8-bit | `mlx-community/Qwen3-ASR-0.6B-8bit` | `Qwen3-ASR-0.6B-8bit` |
| **Preserved** | Qwen3-ASR 0.6B 6-bit | `mlx-community/Qwen3-ASR-0.6B-6bit` | `Qwen3-ASR-0.6B-6bit` |

---

## 5. Historical Evidence Preservation

**Nemotron historical evidence remains untouched:**
- Candidate development records
- Performance benchmark results
- Recognition quality comparisons
- Owner verification documents

**Rollback capability:**
- Git history contains all Nemotron implementation code
- Original Hugging Face repository remains available
- `MLXAudioSTTProvider.swift` preserved until final verification

---

## 6. Future Removal Scope (Next Task)

**Files to be removed:**
- `VoiceDockCore/Sources/MLXAudioSTTProvider.swift`
- `ASRModelSelection.nemotron` case
- `QwenModelDescriptor.nemotron_0_6B_8bit` descriptor
- Factory creation path for Nemotron

**Documentation updates:**
- Remove Nemotron from routing tables
- Update VOICEDOCK_MASTER_PROMPT.md technology section
- Update AGENTS.md architecture section
- Update this retirement record with completion status

**NOT to be removed:**
- Historical Candidate evidence
-Archived benchmark results
- This retirement record

---

## 7. Restoration Approach

If Nemotron restoration is ever required:

1. **From Git history:**
   ```bash
   git checkout <commit-before-removal> -- VoiceDockCore/Sources/MLXAudioSTTProvider.swift
   ```

2. **From Hugging Face:**
   ```bash
   # Original repository remains available
   mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
   ```

3. **Code changes required:**
   - Restore `ASRModelSelection.nemotron` case
   - Restore `QwenModelDescriptor.nemotron_0_6B_8bit`
   - Restore factory creation path
   - Update routing documentation

---

## 8. Model Data Deletion Record

**Owner approval:** Full Nemotron model data deletion approved by owner on 2026-07-13.

**Deletion date:** 2026-07-13

**Deleted paths:**
1. `/Users/sagawithme/.cache/huggingface/hub/models--mlx-community--nemotron-3.5-asr-streaming-0.6b-8bit` (~720 MB)
2. `/Users/sagawithme/.cache/huggingface/hub/mlx-audio/mlx-community_nemotron-3.5-asr-streaming-0.6b-8bit` (~720 KB)
3. `/Users/sagawithme/.cache/huggingface/hub/.locks/models--mlx-community--nemotron-3.5-asr-streaming-0.6b-8bit` (~156 KB)

**Total disk space reclaimed:** ~721 MB

**Qwen models verified intact:**
- `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit` ✓
- `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-8bit` ✓
- `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-1.7B-4bit` ✓

**Verification:** Zero `nemotron` paths remain in `~/.cache/huggingface/hub/`

**Current status:** `NEMOTRON_MODEL_DATA_REMOVED`

---

## 9. Completion Criteria (Next Task)

The Nemotron retirement task is complete only when:

- [ ] `MLXAudioSTTProvider.swift` removed
- [ ] `ASRModelSelection.nemotron` case removed
- [ ] `QwenModelDescriptor.nemotron_0_6B_8bit` removed
- [ ] Factory creation path removed
- [ ] `VOICEDOCK_MASTER_PROMPT.md` updated
- [ ] `AGENTS.md` updated
- [ ] Automated tests pass without Nemotron references
- [ ] Xcode Debug build succeeds
- [ ] Xcode Release build succeeds
- [ ] Xcode tests pass
- [ ] Owner confirms no rollback needed
- [ ] This record updated with completion status


## 10. Status

`NEMOTRON_MODEL_DATA_REMOVED`