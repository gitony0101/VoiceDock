# VoiceDock Handoff

**Last Updated**: 2026-06-23 (Candidate 7 Phase A.1 AUTOMATED COMPLETE — OWNER UI RETEST REQUIRED)

## Executive Summary

Candidate 7 Phase A.1 automated gates are complete. Owner UI retest is required to confirm "Retry Transcription" label is no longer truncated.

**Candidate 6 remains the frozen, physically verified rollback baseline.**

## Active Candidate

**candidate-7-phase-a1** (Development Review Build — NOT FROZEN)

```text
Artifact: build/candidate-7-phase-a1-review/VoiceDock.app
SHA-256: eb442ac1bd26b0f3014e714e73aafa981a3cc5dd73100c9569c3ef359d5024f0
CDHash: 90a6083b2293c6fb0524fd2e7ae9ec2b100d0621
Bundle ID: com.voicedock.app
Signing: Ad-hoc
```

## Candidate 6 Rollback Baseline (Unchanged)

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Status: Frozen, physically verified (Gate C COMPLETE)
```

## Candidate 7 Phase A Owner Review Result (Historical)

**Result:** PARTIAL

All behavioral tests passed. Single UI failure: "Retry Transcription" label truncated to "Retry Transcr..." at default popover width.

## Candidate 7 Phase A.1 Automated Verification (Complete)

| Check | Result | Notes |
|-------|--------|-------|
| swift build | PASS | Debug build |
| swift test | PASS | 46 XCTest tests |
| xcodegen generate | PASS | Project regenerated |
| xcodebuild Debug build | PASS | Native app build |
| xcodebuild Debug test | PASS | 24 XCTest tests |
| xcodebuild Release build | PASS | Native app build |
| UI truncation fix | PASS | Two-row VStack layout |
| Behavioral code preserved | PASS | No delivery code modified |

**Test Count Reconciliation**:
- SwiftPM (`swift test`): 46 XCTest tests (VoiceDockCoreTests)
- Xcode (`xcodebuild test`): 24 XCTest tests (VoiceDockTests)

## Candidate 7 Phase A.1 Owner UI Retest (PENDING)

See `.loop/evidence/candidates/candidate-7-phase-a1/OWNER_UI_RETEST_REQUIRED.md` for complete retest instructions.

**Pending Tests**:
- [ ] "Retry Transcription" fully visible (no truncation)
- [ ] "Refresh Status" fully visible
- [ ] "More" fully visible
- [ ] No width-induced ellipsis on any action label
- [ ] Increased macOS text size still usable
- [ ] Retry/Refresh/More actions work correctly
- [ ] TextEdit paste smoke test
- [ ] Terminal suppression smoke test

## Candidate 7 Phase A.1 Change

**Single file modified:** `VoiceDockApp/UI/MenuBarView.swift`

Changed action area from single-row HStack to two-row VStack:
- Row 1: "Retry Transcription" (full width)
- Row 2: "Refresh Status" + "More" menu

All behavioral delivery code unchanged.

## How to Resume

After owner physical review:

1. **If verified**: Owner confirms "Candidate 7 Phase A verified — proceed to Phase B"
2. **Then**: Begin Phase B (branding/icon integration)
3. **After Phase B**: Freeze Candidate 7, perform physical verification
4. **Finally**: Consider v0.1.0 prerelease and public repository visibility

If issues found:
1. Owner reports exact failure
2. Fix and rebuild review artifact
3. Provide updated SHA-256 for re-verification