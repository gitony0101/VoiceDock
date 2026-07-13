# VoiceDock Qwen3-ASR 0.6B 6-bit Retirement Record

**Date:** 2026-07-13  
**Status:** `QWEN3_06B_6BIT_MODEL_DATA_REMOVED`  
**Next Task:** Remove qwen3-0.6b-6bit from active code, factory routing, descriptors, tests, and documentation

---

## 1. Owner Approval

**Approval date:** 2026-07-13

**Decision:** Retire `qwen3-0.6b-6bit` model from VoiceDock.

**Rationale:**
- Consolidate to two active models for MVP
- `qwen3-0.6b-8bit` serves as the Fast model (8-bit quantization)
- `qwen3-1.7b-4bit` serves as the Quality model (4-bit quantization, larger model)
- 6-bit quantization provides no distinct advantage over 8-bit for the Fast tier

---

## 2. Retired Model Information

| Property | Value |
|----------|-------|
| **Model identifier** | `qwen3-0.6b-6bit` |
| **Hugging Face repository** | `mlx-community/Qwen3-ASR-0.6B-6bit` |
| **Local directory name** | `Qwen3-ASR-0.6B-6bit` |
| **Original local path** | `/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit` |
| **Model family** | Qwen3-ASR |
| **Parameters** | 0.6 billion |
| **Quantization** | 6-bit |

---

## 3. Model Data Deletion Record

**Deletion date:** 2026-07-13

**Deleted path:**
```
/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit
```

**Pre-deletion contents (12 files):**
| File | Size |
|------|------|
| `model.safetensors` | 818 MB |
| `tokenizer.json` | 4.5 MB |
| `vocab.json` | 2.6 MB |
| `merges.txt` | 1.6 MB |
| `model.safetensors.index.json` | 70 KB |
| `tokenizer_config.json` | 12 KB |
| `generation_config.json` | 142 B |
| `config.json` | 7.0 KB |
| `chat_template.json` | 1.1 KB |
| `preprocessor_config.json` | 330 B |
| `README.md` | 1008 B |
| `.gitattributes` | 1.5 KB |

**Disk space reclaimed:** ~828 MB

---

## 4. Preserved Qwen Models

**Verified intact after deletion:**

| Model | Path | Size |
|-------|------|------|
| **Qwen3-ASR-0.6B-8bit (Fast)** | `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-8bit` | ~969 MB |
| **Qwen3-ASR-1.7B-4bit (Quality)** | `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-1.7B-4bit` | ~1.5 GB |

**Verification:**
- ✓ `Qwen3-ASR-0.6B-6bit` no longer exists
- ✓ `Qwen3-ASR-0.6B-8bit` exists and intact
- ✓ `Qwen3-ASR-1.7B-4bit` exists and intact
- ✓ No 0.6B 6-bit model data remains in VoiceDock Models directory
- ✓ No Qwen files deleted from Hugging Face cache

---

## 5. Reason for Retirement

**Primary reason:** Model consolidation for MVP delivery.

**Supporting factors:**
- Two-model configuration (Fast + Quality) is sufficient for MVP
- 8-bit quantization provides better quality than 6-bit for similar performance
- Reduces model selection complexity during active development
- Owner dogfooding validates 0.6B 8-bit as suitable Fast tier

---

## 6. Replacement Models

| Role | Model | Repository | Quantization |
|------|-------|------------|--------------|
| **Fast (default)** | Qwen3-ASR 0.6B 8-bit | `mlx-community/Qwen3-ASR-0.6B-8bit` | 8-bit |
| **Quality** | Qwen3-ASR 1.7B 4-bit | `mlx-community/Qwen3-ASR-1.7B-4bit` | 4-bit |

---

## 7. Historical Evidence Preservation

**Qwen3-ASR 0.6B 6-bit investigation evidence remains untouched:**
- `docs/QWEN3_ASR_06B_6BIT_INVESTIGATION.md`
- `docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md`
- `docs/QWEN3_ASR_PHASE2A_IMPLEMENTATION_REPORT.md`
- `docs/QWEN3_ASR_PHASE2B_RUNTIME_REPORT.md`
- `docs/RALPH_QWEN_DUEL_RUNTIME_REPAIR.md`
- `docs/RALPH_QWEN_MODEL_DUEL.md`
- `docs/archive/qwen-duel/`

**Rollback capability:**
- Git history contains all qwen3-0.6b-6bit implementation code
- Original Hugging Face repository remains available: `mlx-community/Qwen3-ASR-0.6B-6bit`
- Model can be re-downloaded if needed

---

## 8. Outstanding Removal Scope (Next Task)

The following still reference `qwen3-0.6b-6bit` and require removal in a subsequent task:

**Code removal:**
- Any `QwenModelDescriptor.qwen3_0_6B_6bit` or similar case
- Factory creation path for 6-bit model
- Model routing that includes 6-bit option

**Test removal:**
- Tests specifically targeting 6-bit model
- Mock providers configured for 6-bit

**Documentation updates:**
- Remove 6-bit model from routing tables
- Update `VOICEDOCK_MASTER_PROMPT.md` if it references 6-bit
- Update `AGENTS.md` architecture section if needed
- Update this retirement record with final completion status

**NOT to be removed:**
- Historical Qwen investigation evidence
- Archived benchmark results
- This retirement record

---

## 9. Restoration Approach

If Qwen3-ASR 0.6B 6-bit restoration is ever required:

1. **Re-download model:**
   ```bash
   # Model will be auto-downloaded by VoiceDock if path exists in code
   # Or manually from Hugging Face:
   # mlx-community/Qwen3-ASR-0.6B-6bit
   ```

2. **From Git history:**
   ```bash
   git checkout <commit-before-removal> -- <affected-files>
   ```

3. **Code changes required:**
   - Restore model descriptor case
   - Restore factory creation path
   - Restore routing configuration

---

## 10. Verification Checklist

- [x] Repository safety verified (pwd, git root, .git exists)
- [x] VoiceDock process stopped before deletion (not running)
- [x] Exact model path inspected and verified
- [x] Deletion safety gates passed
- [x] Preserved models verified before deletion
- [x] Only Qwen3-ASR-0.6B-6bit deleted
- [x] Post-deletion verification complete
- [x] 8-bit model intact
- [x] 1.7B 4-bit model intact
- [x] Retirement record created
- [ ] Code references removed (NEXT TASK)
- [ ] Test references removed (NEXT TASK)
- [ ] Documentation updated (NEXT TASK)

---

## 11. Status

`QWEN3_06B_6BIT_MODEL_DATA_REMOVED`

---

## 12. Final Report Summary

| Item | Result |
|------|--------|
| **Repository safety** | ✓ Verified - feat/candidate7-phase-b-branding branch |
| **VoiceDock process status** | ✓ Not running |
| **Exact model path** | `/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit` |
| **Pre-deletion size** | ~828 MB (12 files) |
| **Path deleted** | `/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit` |
| **Disk space reclaimed** | ~828 MB |
| **Fast model (8-bit)** | `/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-8bit` (~969 MB) |
| **Quality model (1.7B 4-bit)** | `/Users/sagawithme/Library/Application Support/VoiceDock/Models/Qwen3-ASR-1.7B-4bit` (~1.5 GB) |
| **0.6B 6-bit data remaining** | None |
| **Retirement record path** | `docs/decisions/VOICEDOCK_QWEN3_06B_6BIT_RETIREMENT.md` |
| **Swift code changed** | None |
| **Dependencies removed** | None |
| **Commits or pushes** | None |
| **Next required task** | Remove `qwen3-0.6b-6bit` from active code, factory routing, descriptors, tests, and current documentation |