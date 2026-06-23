# Owner UI Retest Required — Candidate 7 Phase A.1

**Build:** Candidate 7 Phase A.1 Development Review Build  
**Status:** NOT FROZEN — NOT RELEASE — OWNER UI RETEST REQUIRED  
**Date:** 2026-06-23  
**Review Build Source:** Working tree after fix for "Retry Transcription" truncation

---

## Quick Summary

Candidate 7 Phase A.1 is a narrowly scoped UI truncation repair.

**Phase A owner review result:** PARTIAL

The only failure was "Retry Transcription" label truncation at the default popover width. All other tests passed.

**Phase A.1 fix:** Changed action area from single-row HStack to two-row VStack:
- Row 1: "Retry Transcription" (full width)
- Row 2: "Refresh Status" and "More" menu

This patch is automated-complete. Owner visual retest is required to confirm labels are no longer truncated.

**Candidate 6 remains the rollback baseline** — unchanged and physically verified.

---

## Review Build Identity

| Property | Value |
|----------|-------|
| **Path** | `build/candidate-7-phase-a1-review/VoiceDock.app` |
| **SHA-256** | `eb442ac1bd26b0f3014e714e73aafa981a3cc5dd73100c9569c3ef359d5024f0` |
| **CDHash** | `90a6083b2293c6fb0524fd2e7ae9ec2b100d0621` |
| **Mach-O UUID** | `arm64` (single-arch, not embedded in ad-hoc signature) |
| **Bundle ID** | `com.voicedock.app` |
| **Architecture** | `arm64` (Apple Silicon only) |
| **Signing Status** | Ad-hoc (local testing) |
| **Configuration** | Release |
| **Timestamp** | 2026-06-23 |

---

## What Changed in Phase A.1

### Single File Changed

**File:** `VoiceDockApp/UI/MenuBarView.swift`

### Before (Phase A)

```swift
// Action buttons - primary row
HStack(spacing: 12) {
    Button("Retry Transcription") { ... }
    Button("Refresh Status") { ... }
    Menu("More") { ... }
}
.font(.caption)
```

At 340pt popover width, "Retry Transcription" truncated to "Retry Transcr..."

### After (Phase A.1)

```swift
// Action area - two-row layout to prevent truncation
VStack(spacing: 8) {
    // Row 1: Primary action (full width)
    Button("Retry Transcription") { ... }
    .font(.caption)
    .frame(maxWidth: .infinity)
    
    // Row 2: Secondary actions (Refresh + More)
    HStack(spacing: 12) {
        Button("Refresh Status") { ... }
        Menu("More") { ... }
        Spacer()
    }
    .font(.caption)
}
```

### Behavioral Code Preserved

The following files were **NOT** modified — all delivery behavior is unchanged:

- `VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift` — unchanged
- `VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift` — unchanged
- `VoiceDockCore/Sources/TerminalApplicationClassifier.swift` — unchanged
- `VoiceDockCore/Sources/TranscriptDestination.swift` — unchanged
- `VoiceDockCore/Sources/SessionCoordinator.swift` — unchanged

All Phase A behavioral tests remain passing.

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
git diff --check → clean (no whitespace errors)
```

---

## Owner UI Retest Checklist

### Step 1: Verify Build Identity

```bash
shasum -a 256 build/candidate-7-phase-a1-review/VoiceDock.app/Contents/MacOS/VoiceDock
```

Expected SHA-256: `eb442ac1bd26b0f3014e714e73aafa981a3cc5dd73100c9569c3ef359d5024f0`

### Step 2: Launch and Open Popover

```bash
open build/candidate-7-phase-a1-review/VoiceDock.app
```

Wait for the menu bar icon (🎙︎) to appear. Click to open the popover.

### Step 3: Visual UI Inspection

At **default popover width** (no manual resizing):

- [ ] **"Retry Transcription"** — fully visible, no ellipsis, no truncation
- [ ] **"Refresh Status"** — fully visible, no ellipsis
- [ ] **"More"** — fully visible, no truncation
- [ ] **No width-induced ellipsis** on any action label
- [ ] **No font-size reduction** — standard macOS caption font preserved
- [ ] **Character counter absent** — no "X chars" text in title bar
- [ ] **No empty diagnostic spacer** — layout looks clean
- [ ] **Two-row layout** — "Retry Transcription" on its own row

### Step 4: Increased macOS Text Size Test

In System Settings → Accessibility → Display → Text Size:
1. Increase text size to a larger setting
2. Return to VoiceDock popover

- [ ] All action labels remain fully visible
- [ ] Layout remains usable (no overlapping controls)
- [ ] "Retry Transcription" still readable

### Step 5: Action Functionality Tests

- [ ] **Retry Transcription** — clickable, changes state appropriately
- [ ] **Refresh Status** — permission badges update when clicked
- [ ] **More menu** — opens correctly

### Step 6: More Menu Items

Open the "More" menu and verify:

- [ ] "Open Microphone Settings" present
- [ ] "Open Accessibility Settings" present
- [ ] "Show Diagnostics" / "Hide Diagnostics" present (state-dependent)
- [ ] "Quit VoiceDock" present and visually distinct (destructive role)

### Step 7: Smoke Tests

#### TextEdit Paste Smoke Test

1. Focus TextEdit
2. Hold `Control+Option+Space`, speak a phrase
3. Release

- [ ] Transcript appears in TextEdit (if automatic paste ON)
- [ ] OR transcript on clipboard for manual paste (if automatic paste OFF)
- [ ] No duplicate paste

#### Terminal Suppression Smoke Test

1. Focus **Terminal.app** (`com.apple.Terminal`)
2. Hold `Control+Option+Space`, speak a harmless phrase like "hello test"
3. Release

- [ ] Transcript is pasted into Terminal
- [ ] Transcript does **not execute** (no Return sent)
- [ ] Cursor remains at end of pasted text
- [ ] Console/log shows "Return suppressed for terminal safety"

### Step 8: Stability

- [ ] VoiceDock returns to "Ready" state after each session
- [ ] Process remains alive (menu bar icon stays visible)
- [ ] No new crash report generated

---

## Phase A Owner Review Result (For Reference)

**Result:** PARTIAL

### Passed in Phase A
- Visible character counter is absent
- No abnormal empty gap observed
- Microphone permission works
- Accessibility permission works
- Automatically paste transcript defaults to ON
- Press Return after paste defaults to OFF
- Preferences behave independently
- Preferences persist after relaunch
- TextEdit paste with Return OFF works
- TextEdit paste with Return ON sends exactly one Return
- Paste OFF still leaves transcript on clipboard
- No duplicate paste observed
- No duplicate Return observed
- Apple Terminal Return suppression works
- Terminal command did not execute automatically
- Suppression behavior matched expectations
- English session passed
- Mandarin session passed
- Mixed-language session passed
- VoiceDock returned to Ready
- Process remained alive
- No new crash report appeared

### Failed in Phase A (Blocker)
- **"Retry Transcription" fully visible: FAIL** — truncated to "Retry Transcr..."
- **No truncated labels: FAIL**

---

## How to Proceed

### If UI Retest Passes

1. Reply with: **"Candidate 7 Phase A.1 UI verified — commit and push"**
2. I will:
   - Commit the fix with message: `fix: prevent Candidate 7 primary action truncation`
   - Push to `origin/feat/candidate7-release-polish`
   - Update documentation
   - Await Phase B approval or further instructions

### If UI Retest Fails

1. Report the exact failure (what is still truncated, or new issue observed)
2. I will:
   - Diagnose root cause
   - Fix and rebuild review artifact
   - Provide updated SHA-256 for re-verification

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
- [ ] No Phase B branding/icon changes
- [ ] No behavioral delivery code changes

---

## Files Changed (Phase A.1)

### Modified

- `VoiceDockApp/UI/MenuBarView.swift` — restructured action area from single-row HStack to two-row VStack

### Unchanged (Behavioral Code Preserved)

- `VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift`
- `VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift`
- `VoiceDockCore/Sources/TerminalApplicationClassifier.swift`
- `VoiceDockCore/Sources/TranscriptDeliveryDecision.swift`
- `VoiceDockCore/Sources/TranscriptDestination.swift`
- `VoiceDockCore/Sources/SessionCoordinator.swift`

---

## Next Steps

After your UI retest:

1. **If verified:** I will commit and push to `origin/feat/candidate7-release-polish`
2. **If Phase B approved:** I will begin branding/icon integration planning
3. **If release approval:** I will prepare Candidate 7 freeze, signing, and notarization (requires credentials)

---

**DO NOT OUTPUT `VOICEDOCK_COMPLETE`** — this is a narrowly scoped UI repair patch.

**Stop Condition Met:** Automated gates complete, owner UI retest required.