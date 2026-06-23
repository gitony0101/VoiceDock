# VoiceDock Handoff

**Last Updated**: 2026-06-23 (Gate C COMPLETE)

## Executive Summary

Candidate 6 is the current physically verified development baseline. Automated gates pass. Gate C physical verification COMPLETE. Candidate 7 backlog defined.

**Note**: Candidate 6 is NOT the final release. It is the first physically verified development baseline and verified rollback candidate. Candidate 7 will be the final release.

## Active Candidate

**candidate-6** (Frozen)

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle ID: com.voicedock.app
Signing: Ad-hoc
```

## Crash Provenance (Critical Finding)

**The alleged "Candidate 5 Gate B failure" was actually Candidate 4 crashing.**

All crash reports analyzed:

| Crash Timestamp | UUID | Candidate |
|-----------------|------|-----------|
| 09:00:12 | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| 07:56:06 | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| 06:02:09 | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| — | 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1 | **Candidate 5/6 — NO CRASH** |

**Conclusion**: Candidate 5 was never physically crash-tested. Candidate 6 shares the same UUID as Candidate 5 and has been physically verified as stable.

## Automated Verification (Complete — Reconciled Counts)

| Check | Result | Notes |
|-------|--------|-------|
| swift package describe | PASS | Package resolved |
| swift build | PASS | Debug build |
| swift test | PASS | 20 XCTest tests (VoiceDockCoreTests) |
| xcodegen generate | PASS | Project generated |
| xcodebuild Debug build | PASS | Native app build |
| xcodebuild Debug test | PASS | 24 XCTest tests (VoiceDockTests) |
| xcodebuild Release build | PASS | Native app build |
| codesign verify | PASS | Signature valid |
| Info.plist lint | PASS | No errors |

**Test Count Reconciliation**:
- SwiftPM (`swift test`): 20 XCTest tests
- Xcode (`xcodebuild test`): 24 XCTest tests (includes HotKeyManagerTests)
- No double-counting — different test targets

## Physical Verification (Gate C COMPLETE)

| Test | Result | Notes |
|------|--------|-------|
| Microphone permission | GRANTED | System prompt |
| Accessibility permission | GRANTED | System prompt |
| Hotkey press/release | PASS | Physical key press detected |
| App stability | PASS (no crash) | No crash report |
| Mandarin transcription | PASS | "好了，好，你能听到吗？" |
| English transcription | PASS (pipeline) | "Hello world, this is voice task of the voice tech transportation." |
| Mixed Chinese-English | PASS (pipeline) | "This is the second test, 你好，这第二次测试。" |
| Clipboard delivery | PASS | Clipboard delivery confirmed |
| Automatic paste | PASS | Text pasted without manual Cmd+V |
| Optional Return | PASS | Cursor moved to new line |
| 3-session stability | PASS | 3 consecutive cycles without crash |

## Recognition Quality Findings

| Aspect | Status |
|--------|--------|
| Pipeline functionality | ✅ PASS |
| English accuracy | ⚠️ PARTIAL |
| Mixed Chinese-English accuracy | ⚠️ PARTIAL |
| Product-name recognition ("VoiceDock") | ❌ NEEDS IMPROVEMENT |

## Repairs in Candidate 6

1. **MainActor isolation safety** — `Task { @MainActor ... }` instead of `MainActor.assumeIsolated`
2. **Permission state refresh** — UI updates on app activation
3. **Activation observer** — Listens for `NSApplication.didBecomeActive`
4. **Diagnostic log cleanup** — Removes stale logs on launch/exit (crash recovery)
5. **Audio format handling** — Hardware format → 16 kHz mono Float32
6. **Buffer timeout protection** — 60 second max buffer

## Historical Candidates

### Candidate 4 (Crashed)
```text
UUID: 646D1BD8-D300-3ADB-8AB7-9234321683C6
Crash: EXC_BAD_ACCESS in MainActor.assumeIsolated
```

### Candidate 5 (Superseded, Never Physically Tested)
```text
UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Status: Superseded by Candidate 6
```

### Candidate 6 (Current Baseline)
```text
Status: Frozen, physically verified (Gate C COMPLETE)
Retention: Keep as rollback candidate
```

## How to Resume

Gate C is COMPLETE. Proceed to Candidate 7:

1. Review Candidate 7 backlog in PLANS.md
2. Implement UI cleanup items (remove `chars` counter, fix button labels)
3. Add separate automatic-paste and automatic-Return controls
4. Default automatic Return to OFF
5. Add terminal safety behavior
6. Add VoiceDock icon and screenshots
7. Freeze Candidate 7
8. Perform Candidate 7 physical verification
9. Consider v0.1.0 prerelease after Candidate 7 verification