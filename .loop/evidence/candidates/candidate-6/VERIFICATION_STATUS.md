# Candidate 6 - Physical Verification Status

**Date**: 2026-06-23  
**Artifact**: `dist/candidate-6/VoiceDock.app`  
**Status**: ✅ GATE C COMPLETE — ALL FUNCTIONAL TESTS PASS

**Note**: Candidate 6 is NOT the final release. It is the first physically verified development baseline and verified rollback candidate. Candidate 7 will be the final release.

---

## Identity Verification

| Property | Value |
|----------|-------|
| SHA-256 | `6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317` |
| CDHash | `3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4` |
| Mach-O UUID | `3745FA4C-2619-3DDB-8565-0CBBA80AC7E1` |
| Bundle ID | `com.voicedock.app` |
| Signing | Ad-hoc (Sign to Run Locally) |

---

## Completed Physical Tests

### Gate B: Hotkey Stability

| Test | Result | Notes |
|------|--------|-------|
| Microphone permission | GRANTED | System prompt |
| Accessibility permission | GRANTED | System prompt |
| Hotkey press detected | PASS | Physical key press |
| Hotkey release detected | PASS | Physical key release |
| Application remained alive | PASS | No crash report |
| Returned to Ready state | PASS | UI state transition correct |

**Crash Provenance**: All previously reported crashes matched Candidate 4 UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`). Candidate 6 has no matching crash reports.

### Gate C: Speech Transcription (Complete)

| Test | Result | Transcript Observed |
|------|--------|---------------------|
| Mandarin | ✅ PASS | "好了，好，你能听到吗？" |
| English | ✅ PASS (pipeline) | "Hello world, this is voice task of the voice tech transportation." |
| Mixed Chinese-English | ✅ PASS (pipeline) | "This is the second test, 你好，这第二次测试。" |
| Clipboard verification | ✅ PASS | Clipboard delivery confirmed |
| Automatic paste | ✅ PASS | Text pasted without manual Cmd+V |
| Optional Return | ✅ PASS | Cursor moved to new line |
| 3-session stability | ✅ PASS | 3 consecutive cycles without crash |

---

## Automated Verification (Complete — Reconciled Counts)

| Check | Result | Notes |
|-------|--------|-------|
| swift package describe | PASS | Package resolved |
| swift build | PASS | Debug build |
| swift test | PASS | 20 XCTest tests |
| xcodegen generate | PASS | Project generated |
| xcodebuild Debug build | PASS | Native app build |
| xcodebuild Debug test | PASS | 24 XCTest tests (Xcode scheme) |
| xcodebuild Release build | PASS | Native app build |
| codesign verify | PASS | Ad-hoc signature valid |
| Info.plist lint | PASS | No errors |

**Test Count Reconciliation**:
- SwiftPM (`swift test`): 20 XCTest tests (VoiceDockCoreTests target)
- Xcode (`xcodebuild test`): 24 XCTest tests (VoiceDockTests target, includes HotKeyManagerTests)
- No double-counting — different test targets

---

## Evidence Files

- `.loop/evidence/candidates/candidate-6/OWNER_GATE_C_RESULTS.md` — Owner-confirmed Gate C results
- `.loop/evidence/candidates/candidate-6/owner-verification-partial.txt` — Earlier partial verification record
- `.loop/evidence/candidates/candidate-6/evidence.md` — Full candidate evidence
- `.loop/evidence/candidates/candidate-6/gate-c-remaining-tests.md` — Test instructions
- `.loop/HANDOFF.md` — Current handoff state
- `.loop/NOW.md` — Current execution state

---

## How to Continue

Gate C physical verification is **COMPLETE**.

**Next step**: Proceed to Candidate 7 cleanup and final release preparation.

---

## Candidate Status

**Candidate 6 is FROZEN** — Do not rebuild, re-sign, or modify.

Any changes after physical verification require a new candidate number (Candidate 7).