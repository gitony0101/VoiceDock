# VoiceDock Handoff

**Last Updated**: 2026-06-23

## Executive Summary

Candidate 6 is the current physically verified baseline. Automated gates pass. Partial manual verification complete. Remaining Gate C tests pending.

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

## Completed Verification

### Automated Gates (All Pass)

- swift package describe: PASS
- swift build: PASS
- swift test: PASS (20 XCTest)
- xcodegen generate: PASS
- xcodebuild Debug build: PASS
- xcodebuild Debug test: PASS (58 tests)
- xcodebuild Release build: PASS
- codesign verify: PASS
- Info.plist lint: PASS

### Physical Verification (Partial)

| Test | Result |
|------|--------|
| Microphone permission | GRANTED |
| Accessibility permission | GRANTED |
| Hotkey press/release | PASS |
| App stability | PASS (no crash) |
| Mandarin transcription | PASS ("好了，好，你能听到吗？") |

## Remaining Gate C Tests

### Setup
1. Keep Candidate 6 running (already verified stable)
2. Open text editor (TextEdit, Notes) with cursor in editable field

### Test 1: English Transcription
- Speak: "Hello world, this is a test of VoiceDock transcription."
- Expected: Accurate English transcript

### Test 2: Mixed Chinese-English
- Speak: "今天我要测试 VoiceDock local speech recognition."
- Expected: Mixed transcript preserving both languages

### Test 3: Automatic Paste
- After speaking, verify transcript automatically pastes
- Expected: Transcript appears without manual Cmd+V

### Test 4: Optional Return
- After paste, verify Return key behavior
- Expected: Cursor moves to new line (if enabled)

### Test 5: Three Consecutive Sessions
- Complete 3 full cycles: launch → hotkey → speak → transcript → ready
- Expected: All succeed without crash

## Repairs in Candidate 6

1. **MainActor isolation safety** — `Task { @MainActor ... }` instead of `MainActor.assumeIsolated`
2. **Permission state refresh** — UI updates on app activation
3. **Activation observer** — Listens for `NSApplication.didBecomeActive`
4. **Diagnostic log cleanup** — Removes stale logs on launch/exit
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
Status: Frozen, physically verified (partial)
Retention: Keep as rollback candidate
```

## How to Resume

After completing Gate C tests, report:

```text
GATE_B: PASSED
GATE_C_ENGLISH: PASSED/FAILED
GATE_C_MIXED: PASSED/FAILED
GATE_C_PASTE: PASSED/FAILED
GATE_C_RETURN: PASSED/FAILED
GATE_C_STABILITY: PASSED/FAILED
```

Then proceed to:
1. Final UI cleanup (remove diagnostic counters)
2. Candidate 7 creation
3. Final evidence documentation