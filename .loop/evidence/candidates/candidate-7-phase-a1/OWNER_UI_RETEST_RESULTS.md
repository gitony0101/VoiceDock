# Owner UI Retest Results — Candidate 7 Phase A

**Date:** 2026-06-23  
**Review Build:** `build/candidate-7-phase-a1-review/VoiceDock.app`  
**Executable SHA-256:** `eb442ac1bd26b0f3014e714e73aafa981a3cc5dd73100c9569c3ef359d5024f0`  
**Source Commit:** `0847b5eca6c7881c146cf1d8f14fbeb309eec822`

---

## Owner Physical Test Scope

All UI and delivery safety tests were performed by the owner on the Phase A.1 review build.

---

## Confirmed PASS Results

### UI Layout

| Test | Result | Notes |
|------|--------|-------|
| Character counter absent | ✅ PASS | No "X chars" text in title bar |
| No empty character-counter gap | ✅ PASS | Layout looks clean |
| Retry Transcription fully visible | ✅ PASS | No ellipsis, no truncation |
| Refresh Status fully visible | ✅ PASS | No ellipsis |
| More fully visible | ✅ PASS | No truncation |
| No width-induced ellipsis | ✅ PASS | All action labels readable at default popover width |
| Two-row action layout readable | ✅ PASS | Primary action on row 1, secondary on row 2 |
| More menu actions available | ✅ PASS | All expected items present |

### Permissions

| Test | Result | Notes |
|------|--------|-------|
| Microphone permission granted | ✅ PASS | System prompt accepted |
| Accessibility permission granted | ✅ PASS | System prompt accepted |

### Preferences and Delivery

| Test | Result | Notes |
|------|--------|-------|
| Automatically paste transcript default ON | ✅ PASS | Works as expected |
| Press Return after paste default OFF | ✅ PASS | Works as expected |
| Preferences independent | ✅ PASS | Each toggle behaves separately |
| Preferences persist after relaunch | ✅ PASS | Settings retained |
| TextEdit paste with Return OFF | ✅ PASS | Transcript pasted, no Return sent |
| TextEdit paste with Return ON | ✅ PASS | Exactly one Return sent |
| Paste OFF, clipboard still updates | ✅ PASS | Clipboard receives transcript |
| No duplicate paste observed | ✅ PASS | Single paste event |
| No duplicate Return observed | ✅ PASS | Single Return when enabled |

### Terminal Safety

| Test | Result | Notes |
|------|--------|-------|
| Apple Terminal Return suppression | ✅ PASS | Return suppressed before event synthesis |
| Transcript did not execute automatically | ✅ PASS | Text pasted but not executed |
| Return suppression happened before execution | ✅ PASS | Correct ordering |
| VoiceDock remained alive | ✅ PASS | Process survived |

*Note: iTerm2 and Warp physical tests were not performed in this session.*

### End-to-End and Stability

| Test | Result | Notes |
|------|--------|-------|
| English session | ✅ PASS | Pipeline functional |
| Mandarin session | ✅ PASS | Pipeline functional |
| Mixed Chinese-English session | ✅ PASS | Pipeline functional |
| Ready → Listening → Transcribing → Delivering → Ready | ✅ PASS | Full state cycle |
| Three-session stability | ✅ PASS | No crashes across sessions |
| Process remained alive | ✅ PASS | Menu bar icon visible throughout |
| New crash report | ✅ NONE | No new crash reports generated |
| Real microphone-to-chat-input workflow | ✅ PASS | End-to-end verified |

---

## Recognition-Quality Limitations (Preserved)

| Aspect | Status | Notes |
|--------|--------|-------|
| English recognition accuracy | PARTIAL | Pipeline works; word accuracy varies |
| Mixed-language recognition accuracy | PARTIAL | Code-switching supported; accuracy varies |
| VoiceDock product-name recognition | NEEDS IMPROVEMENT | Model misrecognizes as "Voice Docks", "VoyStock", etc. |

---

## Process Survival and Crash Report

- **Process survival:** ✅ PASS — VoiceDock remained alive throughout all tests
- **Crash report:** ✅ NONE — No new crash reports generated

---

## Screenshot Observation

The owner confirmed via screenshot that the corrected two-row layout displays:
- "Retry Transcription" fully visible on row 1
- "Refresh Status" and "More" fully visible on row 2
- No truncation or ellipsis at default popover width

*A sanitized screenshot will be prepared separately for Phase B documentation.*

---

## Overall Result

**PASS**

All owner physical tests completed successfully.

---

## Final Status

`CANDIDATE7_PHASE_A_OWNER_VERIFIED`
