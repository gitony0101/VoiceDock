# VoiceDock Qwen Recovery Validation Report

**Report Date**: 2026-07-21  
**Branch**: `recover/qwen-minimal-runtime`  
**Commit**: `d5b3624235acc18935689061a36b889deed639aa`  
**Status**: OWNER_VERIFIED

---

## Executive Summary

This document records the owner-validated physical test results for the VoiceDock Qwen minimal recovery build.

---

## Git State at Validation

```
Branch: recover/qwen-minimal-runtime
HEAD: d5b3624235acc18935689061a36b889deed639aa
Commit Message: fix: correct PTT acceptance and termination state machine
```

**Recent Commits**:
1. `d5b36242` (HEAD → recover/qwen-minimal-runtime) fix: correct PTT acceptance and termination state machine
2. `334143b5` fix: stabilize hotkey and application lifecycle
3. `f9a6ff1d` refactor: restrict production ASR routing to Qwen
4. `8ed6f1c7` chore: regenerate Xcode project from project.yml
5. `e87eb2cd` docs: define Qwen minimal recovery phase
6. `cfbfdb21` (qwen-baseline-audit) feat(asr): establish verified Qwen dual-model baseline

**Working Tree Status**: Clean (no uncommitted changes)

**VoiceDock Process**: Not running

---

## Owner Physical Validation Results

### Test Sentences

The owner recorded three test sentences during the recovery validation session:

| # | Expected Sentence | Actual Raw Qwen Transcript |
|---|-------------------|---------------------------|
| 1 | Testing VoiceDock Qwen recovery. | Testing voice: Doc Kovan recovery. |
| 2 | 你好，这是 VoiceDock 千问模型恢复测试。 | 你好，这是 Voice Duck 千问模型恢复测试。 |
| 3 | 这是 VoiceDock mixed Chinese English recovery test. | This voice stock makes Chinese English recopy test. |

### Observed Behavior

| Aspect | Result |
|--------|--------|
| All three transcripts automatically inserted into focused text field | ✅ PASS |
| Press Return after paste remained OFF | ✅ PASS |
| No automatic submission occurred | ✅ PASS |
| Owner selected Quit VoiceDock from menu | ✅ PASS |
| VoiceDock exited cleanly | ✅ PASS |
| No replacement VoiceDock process appeared after quit | ✅ PASS |

---

## ASR Error Patterns Observed

The Qwen3 model exhibited consistent misrecognition patterns:

### Pattern 1: Product Name Corruption

| Error | Correction Needed |
|-------|-------------------|
| Voice Duck | VoiceDock |
| voice duck | VoiceDock |
| voice: Doc | VoiceDock |
| Voice Document | VoiceDock |
| voice stock | VoiceDock |

### Pattern 2: Model Name Corruption

| Error | Correction Needed |
|-------|-------------------|
| Kovan | Qwen |

### Pattern 3: Technical Term Corruption

| Error | Correction Needed |
|-------|-------------------|
| makes Chinese English | mixed Chinese English |
| recopy test | recovery test |
| Honor TVT | Owner PTT |

---

## Post-Recovery State

After validation:

1. **Repository State Preserved**: ✅
   - No uncommitted changes
   - No forced resets or rebases
   - Recovery commits intact

2. **Application State**: ✅
   - VoiceDock exited cleanly
   - No orphan processes
   - Menu bar process removed on quit

3. **Validation Evidence**: ✅
   - Owner-confirmed raw transcripts recorded
   - Owner-confirmed behavior documented
   - ASR error patterns identified

---

## Baseline Correction Corpus

These three raw/corrected pairs form the initial correction corpus for the Personal Transcript Correction v1 feature:

### Sample 1
**Raw**: `Testing voice: Doc Kovan recovery.`  
**Corrected**: `Testing VoiceDock Qwen recovery.`

### Sample 2
**Raw**: `你好，这是 Voice Duck 千问模型恢复测试。`  
**Corrected**: `你好，这是 VoiceDock 千问模型恢复测试。`

### Sample 3
**Raw**: `This voice stock makes Chinese English recopy test.`  
**Corrected**: `This VoiceDock mixed Chinese English recovery test.`

---

## Next Steps

1. ✅ Preservation complete: recovery branch is clean
2. ⏳ Create `feat/personal-transcript-correction` branch
3. ⏳ Implement deterministic correction engine
4. ⏳ Wire into transcript delivery path
5. ⏳ Owner validation of correction On/Off behavior

---

**Verification Status**: `AUTOMATED_GATES_COMPLETE_MANUAL_VERIFICATION_PENDING`

**Note**: This document records the raw Qwen transcript behavior that the Personal Transcript Correction v1 feature will address through deterministic rules.