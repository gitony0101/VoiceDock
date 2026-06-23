# VoiceDock Handoff

**Last Updated**: 2026-06-23 (Candidate 7 Phase A AUTOMATED COMPLETE — OWNER REVIEW REQUIRED)

## Executive Summary

Candidate 7 Phase A automated gates are complete. Owner physical review is required before proceeding to Phase B (branding) or Candidate 7 freeze.

**Candidate 6 remains the frozen, physically verified rollback baseline.**

## Active Candidate

**candidate-7-phase-a** (Development Review Build — NOT FROZEN)

```text
Artifact: build/candidate-7-phase-a-review/VoiceDock.app
SHA-256: 29e5b609bb4f7d15c8d6ee7cdbb608cdd688500984129506170191fb87941763
CDHash: e02c039216a37a4330bc547b145ea39cbb18ab86
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

## Candidate 7 Phase A Automated Verification (Complete)

| Check | Result | Notes |
|-------|--------|-------|
| swift build | PASS | Debug build |
| swift test | PASS | 46 XCTest tests |
| xcodegen generate | PASS | Project regenerated |
| xcodebuild Debug build | PASS | Native app build |
| xcodebuild Debug test | PASS | 24 XCTest tests |
| xcodebuild Release build | PASS | Native app build |

**Test Count Reconciliation**:
- SwiftPM (`swift test`): 46 XCTest tests (VoiceDockCoreTests)
- Xcode (`xcodebuild test`): 24 XCTest tests (VoiceDockTests)

## Candidate 7 Phase A Owner Physical Review (PENDING)

See `.loop/evidence/candidates/candidate-7-phase-a/OWNER_UI_REVIEW_REQUIRED.md` for complete test instructions.

**Pending Tests**:
- [ ] UI verification (char counter absent, action labels readable)
- [ ] Preference defaults (paste=ON, return=OFF)
- [ ] Preference persistence (relaunch test)
- [ ] Clipboard-only delivery (paste OFF)
- [ ] Paste without Return (default)
- [ ] Paste with Return (non-terminal)
- [ ] Terminal safety (Apple Terminal, iTerm2, Warp)
- [ ] Three-session stability (English, Mandarin, Mixed)

## Candidate 7 Phase A Changes

1. **Character counter removed** — No "X chars" in title bar
2. **Bottom actions redesigned** — Retry, Refresh, More menu (no truncation)
3. **Independent preferences** — Automatic paste (default ON), Return after paste (default OFF)
4. **Terminal safety** — Return suppressed before event synthesis for known terminals
5. **26 new automated tests** — Preferences, terminal classifier, delivery policy

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