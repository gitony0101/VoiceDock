# Candidate 6 Gate C Physical Verification Results

**Date**: 2026-06-23  
**Candidate**: candidate-6 (FROZEN)  
**Status**: GATE C COMPLETE — ALL FUNCTIONAL TESTS PASS

---

## Candidate 6 Identity (Verified Before Testing)

```text
Artifact:    dist/candidate-6/VoiceDock.app
SHA-256:     6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash:      3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle ID:   com.voicedock.app
Signing:     Ad-hoc (Sign to Run Locally)
```

**Confirmation**: Candidate 6 remains frozen — no rebuild, re-sign, overwrite, or modification.

---

## Owner-Confirmed Physical Test Results

### Gate B: Hotkey Stability

| Test | Result | Evidence |
|------|--------|----------|
| Microphone permission | ✅ GRANTED | System prompt granted |
| Accessibility permission | ✅ GRANTED | System prompt granted |
| Control+Option+Space physical press | ✅ PASS | Physical key press detected |
| Physical release | ✅ PASS | No crash on release |
| Returned to Ready state | ✅ PASS | UI state transition correct |
| Process remained alive | ✅ PASS | No crash report |
| No new Candidate 6 crash report | ✅ NONE | All crashes matched Candidate 4 UUID |

**Running Executable**:
```
dist/candidate-6/VoiceDock.app/Contents/MacOS/VoiceDock
```

**Process Evidence**:
```
<pid> dist/candidate-6/VoiceDock.app/Contents/MacOS/VoiceDock
```

---

### Gate C: Speech Transcription and Delivery

#### Test 1: English Transcription

**Intended Phrase**:
```
Hello world, this is a test of VoiceDock transcription.
```

**Observed Transcript**:
```
Hello world, this is voice task of the voice tech transportation.
```

**pbpaste Output**:
```
Hello world, this is voice task of the voice tech transportation.
```

**Result**: 
- English recording/transcription pipeline: ✅ PASS
- Clipboard delivery: ✅ PASS
- English semantic accuracy: ⚠️ PARTIAL / NEEDS IMPROVEMENT

**Notes**: The percent sign shown after `pbpaste` was the zsh prompt caused by missing trailing newline and was not part of the clipboard text.

---

#### Test 2: Automatic Paste and Return

**Procedure**: Activate push-to-talk, speak, release, observe automatic paste

**Observed Result in TextEdit**:
```
This is an automatic paste and return test.
```

**Owner Confirmation**:
- ✅ Text was pasted automatically
- ✅ No manual Command+V required
- ✅ Cursor moved automatically to the next line
- ✅ Automatic paste: PASS
- ✅ Current automatic Return behavior: PASS
- ✅ App returned to Ready
- ✅ Process remained alive

**⚠️ Safety Finding**:

Automatic Return was previously observed pasting a mixed-language transcript into the focused Terminal and causing zsh to execute it as a command.

**Therefore Candidate 7 must**:
1. Expose automatic paste and automatic Return as separate settings
2. Default automatic Return to OFF
3. Clearly label the Return setting
4. Consider blocking or warning about automatic Return in Terminal, iTerm, Warp, and similar terminal applications

---

#### Test 3: Mixed-Language and Consecutive Sessions

**Observed Transcripts**:
```
This is the second test, 你好，这第二次测试。

Dirty Sun's Voice Docks Stability Test.

这是第三次 VoyStock Stability Test。
```

**Results**:
- ✅ Repeated-session recording pipeline: PASS
- ✅ Automatic paste across consecutive sessions: PASS
- ✅ Automatic Return across consecutive sessions: PASS
- ✅ Process stability across consecutive sessions: PASS
- ⚠️ English recognition accuracy: PARTIAL
- ⚠️ Mixed Chinese-English recognition accuracy: PARTIAL
- ⚠️ Product name recognition for "VoiceDock": NEEDS IMPROVEMENT

**Functional Loop Verified**:
```
Ready
→ Listening
→ Recording
→ Release
→ Transcription
→ Clipboard
→ Automatic paste
→ Automatic Return
→ Ready
→ Next session
```

---

## Candidate 6 Overall Result

| Functional Gate | Status |
|-----------------|--------|
| Gate B: Hotkey stability | ✅ PASS |
| Mandarin transcription pipeline | ✅ PASS |
| English transcription pipeline | ✅ PASS |
| Mixed Chinese-English pipeline | ✅ PASS |
| Clipboard delivery | ✅ PASS |
| Automatic paste | ✅ PASS |
| Current automatic Return behavior | ✅ PASS |
| Consecutive-session stability | ✅ PASS |
| Process stability | ✅ PASS |
| New Candidate 6 crash report | ✅ NONE |

| Recognition Quality | Status |
|---------------------|--------|
| Overall recognition quality | ⚠️ PARTIAL |
| Product-name recognition ("VoiceDock") | ❌ NEEDS IMPROVEMENT |

---

## Candidate 6 Status Declaration

**Candidate 6 is**:
- ✅ The first physically verified development baseline
- ✅ The verified rollback candidate
- ✅ Functionally complete for Gate C

**Candidate 6 is NOT**:
- ❌ The final release
- ❌ A production-ready v1.0.0
- ❌ A fully polished public release

---

## Automated Test Counts (Reconciled)

| Harness | Test Count | Notes |
|---------|------------|-------|
| SwiftPM (`swift test`) | 20 XCTest tests | VoiceDockCoreTests target |
| Xcode scheme (`xcodebuild test`) | 24 XCTest tests | VoiceDockTests target (includes HotKeyManagerTests) |

**Note**: No double-counting — different test targets. Swift Testing tests: 0.

---

## Candidate 7 Backlog (Recorded for Next Milestone)

1. Remove the visible `chars` counter from the public UI
2. Replace truncated bottom-button labels with clear accessible labels
3. Add separate automatic-paste and automatic-Return controls
4. Default automatic Return to OFF
5. Add terminal safety behavior for automatic Return
6. Add the approved VoiceDock icon
7. Add polished README icon and current screenshot
8. Improve recognition documentation and disclose model limitations
9. Investigate vocabulary or prompt-bias options for recognizing `VoiceDock`
10. Freeze Candidate 7 separately
11. Perform final physical Candidate 7 verification
12. Only after Candidate 7 verification consider public repository visibility and a `v0.1.0` prerelease

---

## Evidence Summary

**Functional Gates**: ALL PASS  
**Recognition Quality**: PARTIAL (accurate pipeline, variable word accuracy)  
**Process Stability**: PASS  
**Crash Provenance**: No Candidate 6 crashes — all historical crashes matched Candidate 4 UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`)

---

**Document Path**: `.loop/evidence/candidates/candidate-6/OWNER_GATE_C_RESULTS.md`

**Next Step**: Reconcile tracked documentation and commit sanitized evidence.