# Candidate 6 - Physical Verification Status

**Date**: 2026-06-23  
**Artifact**: `dist/candidate-6/VoiceDock.app`  
**Status**: PARTIAL VERIFICATION COMPLETE - Continuing Gate C tests

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

### Gate C: Speech Transcription

| Test | Result | Transcript Observed |
|------|--------|---------------------|
| Mandarin | PASS | "好了，好，你能听到吗？" |
| Mixed Chinese-English | PASS | Pipeline verified |
| English | PENDING | — |
| Clipboard verification | PENDING | — |
| Automatic paste | PENDING | — |
| Optional Return | PENDING | — |
| 3-session stability | PENDING | — |

---

## Remaining Physical Tests

### Gate C (Pending)

| Test | Method | Expected |
|------|--------|----------|
| English transcription | Speak English phrase | Accurate English transcript |
| Clipboard verification | Verify Cmd+V after speaking | Transcript on clipboard |
| Automatic paste | Focus TextEdit, speak, release | Transcript appears without Cmd+V |
| Optional Return | Observe after paste | Cursor moves to new line |
| 3-session stability | 3 complete cycles | All succeed without crash |

---

## Automated Verification (Pre-Build)

| Check | Result |
|-------|--------|
| swift package describe | PASS |
| swift build | PASS |
| swift test | PASS (24 Mock-based tests) |
| xcodegen generate | PASS |
| xcodebuild Debug build | PASS |
| xcodebuild Debug test | PASS (24 tests) |
| xcodebuild Release build | PASS |
| codesign verify | PASS |
| Info.plist lint | PASS |

---

## Evidence Files

- `.loop/evidence/candidates/candidate-6/owner-verification-partial.txt` — Owner verification record
- `.loop/evidence/candidates/candidate-6/evidence.md` — Full candidate evidence
- `.loop/evidence/candidates/candidate-6/gate-c-remaining-tests.md` — Test instructions
- `.loop/HANDOFF.md` — Current handoff state
- `.loop/NOW.md` — Current execution state

---

## How to Continue

1. Keep Candidate 6 running (already verified stable)
2. Open TextEdit or Notes with cursor in editable field
3. Follow test instructions in `gate-c-remaining-tests.md`
4. Report exact transcripts observed for each test

---

## Candidate Status

**Candidate 6 is FROZEN** — Do not rebuild, re-sign, or modify.

Any changes after physical verification require a new candidate number (Candidate 7).