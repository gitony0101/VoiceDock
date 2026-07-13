# Candidate 7 Phase A.1 Plan — UI Truncation Repair

## Status

```text
CANDIDATE7_PHASE_A_OWNER_REVIEW_PARTIAL
```

## Owner Review Summary

**Date:** 2026-06-23

**Result:** PARTIAL

### Passed
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

### Failed (Blocker)
- **Retry Transcription fully visible: FAIL** — Label truncated to "Retry Transcr..."
- **No truncated labels: FAIL**

## Root Cause Analysis

### Current Layout (MenuBarView.swift:207-239)

```swift
// Action buttons - primary row
HStack(spacing: 12) {
    Button("Retry Transcription") { ... }
    Button("Refresh Status") { ... }
    Menu("More") { ... }
}
.font(.caption)
```

This HStack sits inside a VStack with fixed frame:

```swift
.frame(width: 340, height: 420)
```

### Truncation Mechanism

The issue is **intrinsic button width vs. available horizontal space**.

At `.font(.caption)` with standard macOS system font:
- "Retry Transcription" requires ~130-140pt intrinsic width
- "Refresh Status" requires ~90-100pt intrinsic width  
- "More" requires ~40-50pt intrinsic width
- Total minimum: ~260-290pt

With `spacing: 12` between buttons (24pt total) and VStack padding:
- Available width: 340pt - (2 × padding ≈ 32pt) = ~308pt actual
- Buttons compete for space, SwiftUI distributes via Spacer logic

The HStack has no explicit width distribution, so buttons shrink proportionally. "Retry Transcription" being the longest label gets truncated first.

### Why Current Layout Fails

1. **Single-row constraint** — All three buttons must fit horizontally
2. **No priority** — SwiftUI doesn't know "Retry Transcription" should get more space
3. **Fixed popover width** — 340pt is reasonable but not enough for three caption buttons with this label length
4. **No truncation resistance** — No `.lineLimit(1)` or `.truncationMode(.clip)` to force layout awareness

## Proposed Solution

### Two-Row Vertical Layout

```
┌─────────────────────────────────────┐
│  [Title area]                       │
│  ─────────────────────────────────  │
│  [State indicator]                  │
│  [Permission rows]                  │
│  [Diagnostics if shown]             │
│  [Failure message if failed]        │
│  [Last transcript if exists]        │
│                                     │
│  [Paste toggles]                    │
│  ─────────────────────────────────  │
│  [  Retry Transcription           ] │  ← Row 1: Full width
│  [Refresh Status]  [More ▾]         │  ← Row 2: Split
│                                     │
└─────────────────────────────────────┘
```

### Implementation

```swift
// Delivery settings (existing)
VStack(alignment: .leading, spacing: 8) {
    // ... toggles ...
}
.padding(.vertical, 4)

Divider()

// Action area - restructured to two rows
VStack(spacing: 8) {
    // Row 1: Primary action (Retry Transcription)
    Button("Retry Transcription") {
        Task { @MainActor in
            await coordinator.retry()
            permissions.refresh(reason: .retry)
        }
    }
    .font(.caption)
    .disabled(!isReadyOrFailed)
    .frame(maxWidth: .infinity)
    
    // Row 2: Secondary actions (Refresh + More)
    HStack(spacing: 12) {
        Button("Refresh Status") {
            permissions.refresh(reason: .manualRefresh)
        }
        .font(.caption)
        
        Menu("More") {
            // ... menu items ...
        }
        .font(.caption)
        
        Spacer()
    }
}
```

### Files to Change

| File | Change |
|------|--------|
| `VoiceDockApp/UI/MenuBarView.swift` | Restructure action area from single HStack to two-row VStack |

### Files NOT to Change

- `VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift` — Behavioral code, out of scope
- `VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift` — Behavioral code, out of scope
- `VoiceDockCore/Sources/TerminalApplicationClassifier.swift` — Behavioral code, out of scope
- `VoiceDockAppTests/*` — Tests should pass without modification
- `project.yml` — No build system changes needed
- `Package.swift` — No dependency changes needed

## Review Build Path

```
build/candidate-7-phase-a1-review/VoiceDock.app
```

**Note:** Distinct from Phase A build at `build/candidate-7-phase-a-review/VoiceDock.app`

## Owner Retest Scope

Minimal retest focused on UI layout:

1. Launch Phase A.1 review build
2. Verify SHA-256 identity
3. Open popover at default size
4. Verify "Retry Transcription" fully visible (no ellipsis)
5. Verify "Refresh Status" fully visible
6. Verify "More" fully visible
7. Test increased macOS text size still usable
8. Activate Retry Transcription — works correctly
9. Activate Refresh Status — works correctly
10. Open More menu — all items present
11. One TextEdit smoke test — paste behavior unchanged
12. One Apple Terminal smoke test — Return suppression unchanged
13. Confirm process alive after tests
14. Confirm no new crash

## Non-Goals

- Do NOT begin Phase B (branding/icon)
- Do NOT add icon source
- Do NOT change recognition models
- Do NOT tune ASR
- Do NOT freeze Candidate 7
- Do NOT create dist/candidate-7
- Do NOT create tag or GitHub Release
- Do NOT merge to main
- Do NOT modify behavioral delivery code

## Success Criteria

1. ✅ "Retry Transcription" fully visible at default popover width
2. ✅ "Refresh Status" fully visible
3. ✅ "More" fully visible
4. ✅ No width-induced ellipsis on any action label
5. ✅ No font-size reduction to force fit
6. ✅ Character counter remains absent
7. ✅ No empty diagnostic spacer reintroduced
8. ✅ More menu contains all required items
9. ✅ Retry uses same handler (coordinator.retry())
10. ✅ Refresh uses same handler (permissions.refresh())
11. ✅ More actions retain existing handlers
12. ✅ Keyboard focus order logical (top-to-bottom)
13. ✅ Accessibility labels remain meaningful
14. ✅ Increased macOS text size remains usable

## Verification Commands

```bash
# Clean build
xcodegen generate
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Debug build
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Debug test
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -configuration Release build

# Test counts (expected)
# swift test: 46 XCTest
# xcodebuild test: 24 XCTest

# Lint
git diff --check
```

## Evidence Gate

After implementation:
- Record Phase A.1 build identity (SHA-256, CDHash, UUID)
- Verify Candidate 6 identity unchanged
- Update `.loop/NOW.md`, `.loop/HANDOFF.md`, `.loop/DECISIONS.md`
- Create `.loop/evidence/candidates/candidate-7-phase-a1/OWNER_UI_RETEST_REQUIRED.md`
- Update `PLANS.md` with Phase A.1 status
- Document Phase A owner result as PARTIAL

## Git Discipline

Commit message:
```
fix: prevent Candidate 7 primary action truncation
```

Push to:
```
origin/feat/candidate7-release-polish
```

Do NOT:
- Use `git add .` or `git add -A`
- Commit review-build binaries
- Commit dist/candidate-7 (should not exist)
- Commit icon source (remains locally excluded)
- Merge to main

## Stop Condition

Output exactly:
```
CANDIDATE7_PHASE_A1_OWNER_REVIEW_REQUIRED
```

Then report:
- Phase A.1 plan path
- Final commit SHA
- Changed files
- Exact UI layout change
- Proof behavioral delivery code preserved
- Test results by harness
- New review-build path and identity
- Candidate 6 post-build identity
- Owner retest document path
- Known limitations
- Phase A owner result remains PARTIAL until retest
- Candidate 7 not frozen
- dist/candidate-7 does not exist
- No tag or GitHub Release exists
- Phase B not started
- Icon source not modified or committed