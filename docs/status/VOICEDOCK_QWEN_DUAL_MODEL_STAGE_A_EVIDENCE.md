# VoiceDock Qwen Dual-Model Routing Stage A Evidence

**Date:** 2026-07-13  
**Status:** `QWEN_DUAL_MODEL_ROUTING_STAGE_A_OWNER_VERIFIED`

---

## 1. Stage A Objective

Implement Qwen dual-model product routing to retire Nemotron from the active product baseline while preserving it as a Stage B rollback mechanism.

**Scope:**
- Change default ASR model from Nemotron to Qwen3-ASR 1.7B 4-bit
- Support explicit Fast model selection via `VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit`
- Preserve `qwen3-0.6b-6bit` support
- Retain Nemotron code for Stage B rollback safety
- No automatic runtime fallback between models

---

## 2. Approved Product Decisions

| Decision | Status |
|----------|--------|
| Keep `qwen3-0.6b-8bit` as Fast model | ✅ Approved |
| Keep `qwen3-1.7b-4bit` as Quality model | ✅ Approved |
| Keep `qwen3-0.6b-6bit` unchanged | ✅ Preserved |
| Owner dogfooding model: `qwen3-1.7b-4bit` | ✅ Confirmed |
| Retire Nemotron from active baseline | ✅ Implemented |
| Nemotron no longer default | ✅ Implemented |
| Nemotron no longer silent fallback | ✅ Implemented |
| Nemotron code retained for Stage B rollback | ✅ Preserved |
| No automatic runtime fallback | ✅ Enforced |

---

## 3. Routing Table

| Environment Variable Value | Selected Model | Provider |
|---------------------------|----------------|----------|
| (not set) | `qwen3-1.7b-4bit` | Qwen3ASRProvider |
| (empty string) | `qwen3-1.7b-4bit` | Qwen3ASRProvider |
| (invalid/malformed) | `qwen3-1.7b-4bit` | Qwen3ASRProvider |
| `qwen3-1.7b-4bit` | `qwen3-1.7b-4bit` | Qwen3ASRProvider |
| `qwen3-0.6b-8bit` | `qwen3-0.6b-8bit` | Qwen3ASRProvider |
| `qwen3-0.6b-6bit` | `qwen3-0.6b-6bit` | Qwen3ASRProvider |
| `nemotron-0.6b-8bit` | `nemotron-0.6b-8bit` | MLXAudioSTTProvider |

**Explicit owner verification:**
- ✅ No env var → Quality model loads and transcribes
- ✅ Fast model via env var → Fast model loads and transcribes
- ✅ No Nemotron fallback observed in either test

---

## 4. Automated Verification Results

### SwiftPM Tests
```
swift test
```
**Result:** ✅ 26 tests passed in 2 suites
- AudioNormalizerTests: 5 tests
- QwenModelDescriptorTests: 11 tests
- ASRProviderFactoryTests: 10 tests

### Xcode Generation
```
xcodegen generate
```
**Result:** ✅ Success

### Debug Build
```
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Debug -destination 'platform=macOS' build
```
**Result:** ✅ BUILD SUCCEEDED

**Debug App Path:**
```
/Users/sagawithme/Library/Developer/Xcode/DerivedData/VoiceDock-bizdozqptehvjddjddjhaknjyvbi/Build/Products/Debug/VoiceDock.app
```

### Release Build
```
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Release -destination 'platform=macOS' build
```
**Result:** ✅ BUILD SUCCEEDED

**Release App Path:**
```
/Users/sagawithme/Library/Developer/Xcode/DerivedData/VoiceDock-bizdozqptehvjddjddjhaknjyvbi/Build/Products/Release/VoiceDock.app
```

### Xcode Tests
```
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Debug -destination 'platform=macOS' test
```
**Result:** ✅ 50 tests passed in 3 suites
- AudioNormalizerTests
- QwenModelDescriptorTests
- ASRProviderFactoryTests
- HotKeyManagerTests (including synthetic PTT pipeline tests)

### Whitespace Check
```
git diff --check
```
**Result:** ✅ No whitespace errors

---

## 5. Manual Quality Model Evidence

**Test Command:**
```bash
open -a /Users/sagawithme/Library/Developer/Xcode/DerivedData/VoiceDock-bizdozqptehvjddjddjhaknjyvbi/Build/Products/Debug/VoiceDock.app
```

**Runtime Log Evidence:**
```
2026-07-13 14:40:30.848 — Creating ASR provider for: qwen3-1.7b-4bit
2026-07-13 14:40:30.848 — Using Qwen3 ASR provider: qwen3-1.7b-4bit
2026-07-13 14:40:30.848 — Loading Qwen3 model: mlx-community/Qwen3-ASR-1.7B-4bit
2026-07-13 14:40:32.981 — Qwen3 model loaded successfully
2026-07-13 14:40:33.833 — Qwen3 warmup complete
2026-07-13 14:40:56.324 — Transcribing 164800 samples with Qwen3
2026-07-13 14:40:58.329 — Qwen3 transcription complete
```

**Observed Performance:**
- Model load time: 2.13 seconds
- Warmup time: 0.85 seconds
- Transcription time: 2.01 seconds (164800 samples ≈ 10.3 seconds audio)
- Real-time factor: ~0.20 (5x faster than real-time)

**Verification:**
- ✅ Qwen3-ASR 1.7B 4-bit selected (no env var)
- ✅ Model loaded successfully
- ✅ Warmup completed
- ✅ Real microphone transcription completed
- ✅ No Nemotron fallback occurred

---

## 6. Manual Fast Model Evidence

**Test Command:**
```bash
VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit open -a /Users/sagawithme/Library/Developer/Xcode/DerivedData/VoiceDock-bizdozqptehvjddjddjhaknjyvbi/Build/Products/Debug/VoiceDock.app
```

**Runtime Log Evidence:**
```
2026-07-13 14:45:23.650 — Creating ASR provider for: qwen3-0.6b-8bit
2026-07-13 14:45:23.650 — Using Qwen3 ASR provider: qwen3-0.6b-8bit
2026-07-13 14:45:23.650 — Loading Qwen3 model: mlx-community/Qwen3-ASR-0.6B-8bit
2026-07-13 14:45:25.238 — Qwen3 model loaded successfully
2026-07-13 14:45:25.640 — Qwen3 warmup complete
2026-07-13 14:45:38.629 — Transcribing 148800 samples with Qwen3
2026-07-13 14:45:39.712 — Qwen3 transcription complete
```

**Observed Performance:**
- Model load time: 1.59 seconds
- Warmup time: 0.40 seconds
- Transcription time: 1.08 seconds (148800 samples ≈ 9.3 seconds audio)
- Real-time factor: ~0.12 (8x faster than real-time)

**Verification:**
- ✅ Qwen3-ASR 0.6B 8-bit selected (explicit env var)
- ✅ Model loaded successfully
- ✅ Warmup completed
- ✅ Real microphone transcription completed
- ✅ No Nemotron fallback occurred

---

## 7. Benchmark Disclaimer

The timing measurements above represent **two owner-operated runtime samples** on a single M1 Mac with 16 GB unified memory. These are observational measurements from actual usage sessions, not a formal accuracy or performance benchmark.

**No claim is made that Quality (`qwen3-1.7b-4bit`) is universally more accurate than Fast (`qwen3-0.6b-8bit`) based solely on these two samples.** Formal accuracy comparison requires controlled testing with standardized speech corpora.

---

## 8. Nemotron Fallback Confirmation

**Confirmed:** No Nemotron fallback occurred during either manual test session. The routing code does not trigger Nemotron on Qwen load, warmup, or transcription failure. Model failures remain visible as errors.

---

## 9. Remaining Nemotron Rollback Components

The following Nemotron components are intentionally preserved for Stage B rollback safety:

| Component | Path | Status |
|-----------|------|--------|
| Provider implementation | `VoiceDockCore/Sources/MLXAudioSTTProvider.swift` | Preserved |
| Enum case | `ASRModelSelection.nemotron` | Preserved |
| Model descriptor | `QwenModelDescriptor.nemotron_0_6B_8bit` | Preserved |
| Factory creation path | `ASRProviderFactory.createProvider()` → `.nemotron` case | Preserved |

**Stage B will determine final Nemotron disposition after verification that no rollback is required.**

---

## 10. Known Non-Blocking Log Noise

The following log messages are observed during test runs but do not block Stage A:

### CoreAudio Error (test environment only)
```
CoreData: error: Failed to create NSXPCConnection
```
Occurs during XCTest execution; does not affect production runtime.

### MLX Metallib Warning
```
MLX error: Failed to load the default metallib. library not found...
```
Occurs during XCTest; does not affect production runtime with real models.

### AppIntents Metadata
```
warning: Metadata extraction skipped. No AppIntents.framework dependency found.
```
Harmless build warning; does not affect runtime.

### HotKey Carbon Error (test/simulator)
```
[HotKeyManager] Carbon RegisterEventHotKey failed: paramErr (-9878)
```
Expected in test environments without Accessibility permission; falls back to NSEvent.

---

## 11. Dirty Working Tree Inventory

**Tracked Modifications (git status M):**
- `Package.resolved`
- `Package.swift`
- `VoiceDock.xcodeproj/project.pbxproj`
- `VoiceDockApp/AppDelegate.swift`
- `VoiceDockCore/Sources/SessionCoordinator.swift`
- `project.yml`

**Untracked Source Files (git status ??):**
- `Benchmarks/` (new directory)
- `VOICEDOCK_PHASED_ASR_MAINTENANCE_AGENT.md`
- `VoiceDockAppTests/ASRProviderFactoryTests.swift`
- `VoiceDockAppTests/Qwen3ASRProviderTests.swift`
- `VoiceDockAppTests/QwenIntegrationTests.swift`
- `VoiceDockAppTests/QwenModelDescriptorTests.swift`
- `VoiceDockAppTests/QwenModelStorageTests.swift`
- `VoiceDockCore/Sources/ASRProviderFactory.swift`
- `VoiceDockCore/Sources/BenchmarkCore.swift`
- `VoiceDockCore/Sources/ModelInstaller.swift`
- `VoiceDockCore/Sources/ModelStorage.swift`
- `VoiceDockCore/Sources/Qwen3ASRProvider.swift`
- `VoiceDockCore/Sources/QwenModelDescriptor.swift`

**Documentation:**
- `docs/QWEN3_ASR_06B_6BIT_INVESTIGATION.md`
- `docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md`
- `docs/QWEN3_ASR_PHASE2A_IMPLEMENTATION_REPORT.md`
- `docs/QWEN3_ASR_PHASE2B_RUNTIME_REPORT.md`
- `docs/RALPH_QWEN_DUEL_RUNTIME_REPAIR.md`
- `docs/RALPH_QWEN_MODEL_DUEL.md`
- `docs/archive/qwen-duel/` (directory)

**Archived (git status R):**
- `.loop/CANDIDATE7_PHASE_A1_PLAN.md` → `docs/archive/candidate-history/plans/CANDIDATE7_PHASE_A1_PLAN.md`
- `.loop/CANDIDATE7_PHASE_A_PLAN.md` → `docs/archive/candidate-history/plans/CANDIDATE7_PHASE_A_PLAN.md`

**New Files (this task):**
- `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md`

---

## 12. Stage B Prerequisites

Before Stage B (Nemotron retirement verification) can proceed:

1. ✅ Stage A routing implemented and verified
2. ✅ Quality model (1.7B 4-bit) owner-verified on real hardware
3. ✅ Fast model (0.6B 8-bit) owner-verified on real hardware
4. ✅ No automatic fallback behavior present
5. ⏳ Owner decision on Nemotron deletion timing
6. ⏳ Confirmation that no production users depend on Nemotron

---

## 13. Recommended Checkpoint Commit Manifest

Before Stage B, consider committing:

```
VoiceDockCore/Sources/ASRProviderFactory.swift    — Stage A routing
VoiceDockAppTests/ASRProviderFactoryTests.swift   — Stage A tests
docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md
```

**Note:** Many untracked production files exist from the Qwen duel implementation. These should be reviewed and committed together as a coherent baseline before Stage B.

---

## 14. Status

`QWEN_DUAL_MODEL_ROUTING_STAGE_A_OWNER_VERIFIED`

---

## 15. Files Modified by This Task

| File | Change |
|------|--------|
| `VoiceDockCore/Sources/ASRProviderFactory.swift` | Changed default from `.nemotron` to `.qwen3_1_7B_4bit`; updated fallback logic; updated documentation |
| `VoiceDockAppTests/ASRProviderFactoryTests.swift` | Updated tests to expect `.qwen3_1_7B_4bit` as default and fallback |
| `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md` | Created (this document) |

**No files deleted.**

**No model data modified.**

**No MLX dependencies changed.**