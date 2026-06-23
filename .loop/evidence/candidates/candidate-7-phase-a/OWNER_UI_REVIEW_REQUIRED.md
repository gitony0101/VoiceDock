# Owner UI Review Required — Candidate 7 Phase A

**Build:** Candidate 7 Phase A Development Review Build  
**Status:** NOT FROZEN — NOT RELEASE — PHYSICAL REVIEW REQUIRED  
**Date:** 2026-06-23  
**Source Commit:** `8ded5108be22425f822031a792fc04b97801ff14`

---

## Quick Summary

Candidate 7 Phase A automated gates are complete. The following changes require **physical verification** on your M1 Mac before proceeding to Phase B (branding) or Candidate 7 freeze.

**Candidate 6 remains the rollback baseline** — unchanged and physically verified.

---

## Review Build Identity

| Property | Value |
|----------|-------|
| **Path** | `build/candidate-7-phase-a-review/VoiceDock.app` |
| **SHA-256** | `29e5b609bb4f7d15c8d6ee7cdbb608cdd688500984129506170191fb87941763` |
| **CDHash** | `e02c039216a37a4330bc547b145ea39cbb18ab86` |
| **Mach-O UUID** | (arm64, single-arch) |
| **Bundle ID** | `com.voicedock.app` |
| **Architecture** | `arm64` (Apple Silicon only) |
| **Signing Status** | Ad-hoc (local testing) |
| **Configuration** | Release |
| **Timestamp** | 2026-06-23T16:32:28-0300 |

---

## What Changed in Phase A

### 1. Character Counter Removed

**Before:** Top title bar showed "65 chars" when transcript exists.  
**After:** No character counter visible. Transcript still shown in "Last transcript" section.

**Files changed:** `VoiceDockApp/UI/MenuBarView.swift` (lines 25-29 removed)

### 2. Bottom Action Area Redesigned

**Before:** Six crammed buttons with truncated labels ("Op...", "Sho...", "Refr...").  
**After:** Clean three-button row:
- **Retry Transcription** — retry failed ASR
- **Refresh Status** — refresh permission state
- **More** — popover menu containing:
  - Open Microphone Settings
  - Open Accessibility Settings
  - Show Diagnostics
  - Quit VoiceDock

**Files changed:** `VoiceDockApp/UI/MenuBarView.swift` (action area restructured)

### 3. Paste and Return Are Now Independent

**Before:** `sendReturn` hardcoded to `true` in `TranscriptDestination.paste()`.  
**After:** Two independent preferences:
- **Automatically paste transcript** — default ON (matches Candidate 6)
- **Press Return after paste** — default OFF (safer than Candidate 6)

**Files changed:**
- New: `VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift`
- New: `VoiceDockCore/Sources/FrontmostApplicationProviding.swift`
- New: `VoiceDockCore/Sources/TerminalApplicationClassifier.swift`
- New: `VoiceDockCore/Sources/TranscriptDeliveryDecision.swift`
- New: `VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift`
- Modified: `VoiceDockCore/Sources/TranscriptDestination.swift`
- Modified: `VoiceDockCore/Sources/SessionCoordinator.swift`

### 4. Terminal Safety — Return Suppression

When both paste and Return are enabled AND a terminal app is frontmost, Return is **suppressed before event synthesis**.

**Supported terminals:**
- `com.apple.Terminal` — Apple Terminal
- `com.googlecode.iterm2` — iTerm2
- `dev.warp.Warp` — Warp (bundle ID observed, not verified on your system)

**Behavior:**
- Clipboard updates
- Paste occurs (Cmd-V)
- Return is **not sent**
- Log message: "Return suppressed for terminal safety (com.apple.Terminal)"

### 5. Substantive Automated Tests Added

**Before:** 20 tests (all Mock-based).  
**After:** 46 SwiftPM tests + 24 Xcode tests.

**New test coverage:**
- `TranscriptDeliveryPreferencesTests` — 6 tests
  - Default values (paste=ON, return=OFF)
  - Persistence via UserDefaults
  - Independent mutations
- `TerminalApplicationClassifierTests` — 10 tests
  - Known terminal recognition
  - Non-terminal rejection
- `TranscriptDeliveryPolicyTests` — 10 tests
  - All 4 delivery decisions
  - Terminal suppression logic

---

## Physical Verification Checklist

### UI Tests

Launch the review build:

```bash
open build/candidate-7-phase-a-review/VoiceDock.app
```

Wait for the menu bar icon (🎙︎) to appear. Click to open the popover.

- [ ] **No character counter** — "X chars" text absent from title bar
- [ ] **No empty gap** — title bar layout looks clean
- [ ] **Retry Transcription** — full label visible, no truncation
- [ ] **Refresh Status** — full label visible, no truncation
- [ ] **More menu** — visible, clickable
- [ ] **More menu items:**
  - [ ] Open Microphone Settings
  - [ ] Open Accessibility Settings
  - [ ] Show Diagnostics / Hide Diagnostics
  - [ ] Quit VoiceDock
- [ ] **Quit is subordinate** — visually distinct (destructive role)
- [ ] **Increased macOS text size** — increase system text size in System Settings, verify popover remains usable
- [ ] **All actions work:**
  - [ ] Retry Transcription — changes state appropriately
  - [ ] Refresh Status — permission badges update
  - [ ] More menu items open correct dialogs
  - [ ] Quit terminates the app

### Preference Tests

With the popover open:

- [ ] **Automatically paste transcript** defaults to ON (green toggle)
- [ ] **Press Return after paste** defaults to OFF (gray toggle)
- [ ] **Return toggle disabled** when automatic paste is OFF
- [ ] **Toggle paste OFF**, relaunch app, verify it remains OFF
- [ ] **Toggle Return ON**, relaunch app, verify it remains ON
- [ ] **Preferences independent** — changing one doesn't affect the other

### Functional Tests

#### Test 1: Clipboard-Only Delivery (Paste OFF)

1. Set "Automatically paste transcript" to OFF
2. Focus a text editor (TextEdit, Notes)
3. Hold `Control+Option+Space`, speak a phrase
4. Release
5. Manually paste (Cmd-V)

Expected:
- [ ] Transcript appears from clipboard
- [ ] No automatic paste occurred
- [ ] No Return sent

#### Test 2: Paste Without Return (Default)

1. Set "Automatically paste transcript" to ON
2. Set "Press Return after paste" to OFF
3. Focus a text editor
4. Hold `Control+Option+Space`, speak a phrase
5. Release

Expected:
- [ ] Transcript appears in editor automatically
- [ ] Cursor remains on same line (no newline added)

#### Test 3: Paste With Return (Non-Terminal)

1. Set both toggles to ON
2. Focus a text editor (TextEdit, Notes)
3. Hold `Control+Option+Space`, speak a phrase
4. Release

Expected:
- [ ] Transcript appears in editor
- [ ] Cursor moves to next line (Return sent)
- [ ] Exactly one Return (no duplicate)

#### Test 4: Clipboard Always Works

1. With any preference combination
2. Hold `Control+Option+Space`, speak
3. Release
4. Without waiting for paste, manually Cmd-V

Expected:
- [ ] Clipboard contains transcript regardless of paste settings

### Terminal Safety Tests

**WARNING:** These tests verify that Return is suppressed to prevent accidental command execution.

#### Test 5: Apple Terminal — Return Suppression

1. Set both toggles to ON
2. Focus **Terminal.app** (`com.apple.Terminal`)
3. Hold `Control+Option+Space`, speak a **harmless phrase** (e.g., "hello world")
4. Release

Expected:
- [ ] Transcript is pasted into Terminal
- [ ] Transcript does **not execute** (no Return sent)
- [ ] Cursor remains at end of pasted text
- [ ] VoiceDock returns to "Ready" state
- [ ] Process remains alive
- [ ] Console/log shows "Return suppressed for terminal safety"

#### Test 6: iTerm2 — Return Suppression (if installed)

1. Set both toggles to ON
2. Focus **iTerm2** (`com.googlecode.iterm2`)
3. Hold `Control+Option+Space`, speak a harmless phrase
4. Release

Expected:
- [ ] Same as Terminal test — paste occurs, Return suppressed

#### Test 7: Warp — Return Suppression (if installed)

1. Set both toggles to ON
2. Focus **Warp**
3. Hold `Control+Option+Space`, speak a harmless phrase
4. Release

Expected:
- [ ] Same as Terminal test — paste occurs, Return suppressed

### Stability Tests

#### Test 8: Three Consecutive Sessions

1. **Session 1 (English):** Speak clear English phrase
2. **Session 2 (Mandarin):** Speak clear Mandarin phrase (中文测试)
3. **Session 3 (Mixed):** Speak mixed Chinese-English (你好 world)

For each session:
- [ ] State transitions: Ready → Listening → Transcribing → Delivering → Ready
- [ ] Clipboard contains transcript
- [ ] Paste behavior matches preferences
- [ ] Return behavior matches preferences + terminal safety
- [ ] No duplicate paste events
- [ ] No duplicate Return events
- [ ] App remains responsive

---

## Automated Verification Results

### SwiftPM (Headless)

```
swift test
→ 46 tests passed
→ 0 failures
```

### Xcode Tests

```
xcodebuild test -scheme VoiceDock
→ 24 tests passed
→ 0 failures
```

### Builds

```
xcodebuild -scheme VoiceDock -configuration Debug build → PASSED
xcodebuild -scheme VoiceDock -configuration Release build → PASSED
```

---

## Migration from Candidate 6

If you have existing Candidate 6 preferences:

| Candidate 6 | Candidate 7 Default | Notes |
|-------------|---------------------|-------|
| (no storage) `sendReturn=true` hardcoded | `automaticPaste=true`, `sendReturnAfterPaste=false` | **Safer default** — Return is OFF until you enable it |

First launch of Candidate 7:
- Automatic paste: **ON** (you'll get automatic paste like Candidate 6)
- Return after paste: **OFF** (safer — prevents terminal execution)

You can change these in the UI under the transcript area.

---

## Known Limitations (Unchanged from Candidate 6)

These are **not** Phase A issues — they are documented in AGENTS.md and remain for Phase B or later:

- [ ] Recognition quality varies by accent, phrase, and code-switching
- [ ] Product name "VoiceDock" may misrecognize (e.g., "Voice Docks", "VoyStock")
- [ ] No signing/notarization yet (required for distribution)
- [ ] No branding/icon customization (Phase B)
- [ ] Carbon hotkey registration may fall back to NSEvent (app-local only) if Accessibility not fully trusted
- [ ] No real ASR inference tests — all automated tests use `MockASRProvider`

---

## How to Proceed

### If All Tests Pass

1. Reply with: **"Candidate 7 Phase A verified — proceed to Phase B"**
2. I will:
   - Update documentation
   - Commit the changes
   - Push to `origin/feat/candidate7-release-polish`
   - Begin Phase B (branding/icon) planning if requested

### If Issues Found

1. Report the exact failure (which test, what happened)
2. I will:
   - Diagnose root cause
   - Fix and re-verify
   - Rebuild review artifact
   - Provide updated SHA-256 for verification

### If Terminal Bundle ID Mismatch

If Warp or another terminal has a different bundle ID:

1. Report the actual bundle ID (see Console or activity monitor)
2. I will update `TerminalApplicationClassifier.knownTerminals`

---

## Candidate 6 Rollback Baseline

Candidate 6 remains untouched:

| Property | Value |
|----------|-------|
| **Path** | `dist/candidate-6/VoiceDock.app` |
| **SHA-256** | `6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317` |
| **CDHash** | `3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4` |
| **Mach-O UUID** | `3745FA4C-2619-3DDB-8565-0CBBA80AC7E1` |
| **Status** | Frozen, physically verified |

Do not modify, delete, or rebuild Candidate 6.

---

## What is NOT Included

- [ ] No frozen Candidate 7 release
- [ ] No `dist/candidate-7` directory
- [ ] No release tag
- [ ] No GitHub Release
- [ ] No merge to `main`

---

## Files Changed

### New Files

- `VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift`
- `VoiceDockCore/Sources/FrontmostApplicationProviding.swift`
- `VoiceDockCore/Sources/TerminalApplicationClassifier.swift`
- `VoiceDockCore/Sources/TranscriptDeliveryDecision.swift`
- `VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift`
- `VoiceDockAppTests/TranscriptDeliveryPreferencesTests.swift`
- `VoiceDockAppTests/TerminalApplicationClassifierTests.swift`
- `VoiceDockAppTests/TranscriptDeliveryPolicyTests.swift`
- `.loop/CANDIDATE7_PHASE_A_PLAN.md`
- `.loop/evidence/candidates/candidate-7-phase-a/OWNER_UI_REVIEW_REQUIRED.md` (this file)

### Modified Files

- `VoiceDockApp/UI/MenuBarView.swift` — removed char counter, redesigned action area, added settings toggles
- `VoiceDockCore/Sources/TranscriptDestination.swift` — added `copyToClipboard()`, `deliver(decision:)`
- `VoiceDockCore/Sources/SessionCoordinator.swift` — integrated delivery policy

---

## Next Steps

After your physical review:

1. **If verified:** I will commit and push to `origin/feat/candidate7-release-polish`
2. **If Phase B approved:** I will begin branding/icon integration planning
3. **If release approval:** I will prepare Candidate 7 freeze, signing, and notarization (requires credentials)

---

**DO NOT OUTPUT `VOICEDOCK_COMPLETE`** — physical review is required.

**Stop Condition Met:** Automated gates complete, owner physical review required.