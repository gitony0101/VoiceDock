# VoiceDock Current Execution State

**Last Updated**: 2026-06-23 (Gate C COMPLETE)

## Status

```text
GATE_C_COMPLETE — CANDIDATE_6_VERIFIED_BASELINE
```

## Active Candidate

**candidate-6** (Frozen 2026-06-23)

**Role**: First physically verified development baseline, verified rollback candidate

**Note**: Candidate 6 is NOT the final release. Candidate 7 will be the final release after final UI cleanup and polish.

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
```

## Owner Physical Verification Completed (Gate C COMPLETE)

| Test | Result | Evidence |
|------|--------|----------|
| Microphone permission | GRANTED | Owner confirmed |
| Accessibility permission | GRANTED | Owner confirmed |
| Hotkey press | PASS | Physical key press detected |
| Hotkey release | PASS | Physical key release detected |
| App remained alive | PASS | No crash report |
| Returned to Ready | PASS | UI state transition correct |
| Mandarin transcription | PASS | "好了，好，你能听到吗？" |
| English transcription | PASS (pipeline) | "Hello world, this is voice task of the voice tech transportation." |
| Mixed Chinese-English | PASS (pipeline) | "This is the second test, 你好，这第二次测试。" |
| Clipboard delivery | PASS | Clipboard delivery confirmed |
| Automatic paste | PASS | Text pasted without manual Cmd+V |
| Optional Return | PASS | Cursor moved to new line |
| 3-session stability | PASS | 3 consecutive cycles without crash |

**Crash Provenance**: All previously reported crashes matched Candidate 4 UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`). Candidate 6 has no matching crash reports.

## Automated Verification (Complete — Reconciled Counts)

| Check | Result | Notes |
|-------|--------|-------|
| swift package describe | PASS | Package resolved |
| swift build | PASS | Debug build |
| swift test | PASS | 20 XCTest tests |
| xcodegen generate | PASS | Project generated |
| xcodebuild Debug build | PASS | Native app build |
| xcodebuild Debug test | PASS | 24 XCTest tests |
| xcodebuild Release build | PASS | Native app build |
| codesign verify | PASS | Ad-hoc signature valid |
| Info.plist lint | PASS | No errors |

**Test Count Reconciliation**:
- SwiftPM (`swift test`): 20 XCTest tests (VoiceDockCoreTests target)
- Xcode (`xcodebuild test`): 24 XCTest tests (VoiceDockTests target, includes HotKeyManagerTests)
- No double-counting — different test targets

## Gate C Documentation (Complete)

| Document | Purpose |
|----------|---------|
| `OWNER_GATE_C_RESULTS.md` | Sanitized owner-confirmed Gate C results |
| `GATE_C_OWNER_ACTION_REQUIRED.md` | Physical test instructions (archived) |
| `GATE_C_RESULT_TEMPLATE.md` | Result template (archived) |

## Recognition Quality Findings

| Aspect | Status |
|--------|--------|
| Pipeline functionality | ✅ PASS |
| English accuracy | ⚠️ PARTIAL |
| Mixed Chinese-English accuracy | ⚠️ PARTIAL |
| Product-name recognition ("VoiceDock") | ❌ NEEDS IMPROVEMENT |

## Next Action

**Gate C is COMPLETE.** Proceed to:

1. Candidate 7 backlog (UI cleanup, safer Return defaults, branding)
2. Freeze Candidate 7 separately
3. Perform Candidate 7 physical verification
4. Consider v0.1.0 prerelease after Candidate 7 verification

## Document Responsibilities

| File | Purpose |
|------|---------|
| `.loop/NOW.md` | Current execution state (this file) |
| `.loop/HANDOFF.md` | Detailed handoff for next session |
| `.loop/DECISIONS.md` | Durable technical decisions |
| `PLANS.md` | Project roadmap and milestones |
| `AGENTS.md` | Engineering constitution |
| `CLAUDE.md` | Build system and project instructions |
| `.loop/evidence/candidates/candidate-6/GATE_C_OWNER_ACTION_REQUIRED.md` | Gate C test instructions |
| `.loop/evidence/candidates/candidate-6/GATE_C_RESULT_TEMPLATE.md` | Gate C result template |