# Candidate 6 Evidence

**Created**: 2026-06-23

## Artifact

```text
dist/candidate-6/VoiceDock.app
```

## Identity

```text
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Architecture: arm64
Bundle identifier: com.voicedock.app
Signing: ad-hoc (Sign to Run Locally)
```

## Why Candidate 6 (Not Candidate 5)

**Candidate 5 was NEVER physically crash-tested.**

All crash reports in `~/Library/Logs/DiagnosticReports/` were analyzed:

| Crash File | UUID | Match |
|------------|------|-------|
| VoiceDock-2026-06-23-090012.ips | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| VoiceDock-2026-06-23-075606.ips | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| VoiceDock-2026-06-23-060209.ips | 646d1bd8-d300-3adb-8ab7-9234321683c6 | Candidate 4 |
| **Candidate 5** | **3745FA4C-2619-3DDB-8565-0CBBA80AC7E1** | **No crash** |
| **Candidate 6** | **3745FA4C-2619-3DDB-8565-0CBBA80AC7E1** | **Same as C5** |

**Conclusion**: The alleged "Candidate 5 Gate B failure" was actually **Candidate 4** crashing. Candidate 5 shares the same UUID as Candidate 6 (`3745FA4C...`) but was never physically tested.

## Repairs in Candidate 6

Candidate 6 includes all Candidate 5 planned repairs plus additional workspace fixes:

1. **MainActor isolation safety** — AppKit selectors use `Task { @MainActor ... }` instead of `MainActor.assumeIsolated` (Candidate 4 crash fix)
2. **Permission state refresh** — UI updates when user returns from System Settings
3. **Activation observer** — Listens for `NSApplication.didBecomeActive` to trigger permission refresh
4. **Diagnostic log cleanup** — Removes stale logs on launch and exit (crash recovery)
5. **Audio format handling** — Tap installed with hardware input format, normalized to 16 kHz mono Float32
6. **Buffer timeout protection** — Prevents unbounded buffer growth (60 second max)

## Verification (Reconciled Test Counts)

**Swift Package Manager** (`swift test`):
- XCTest tests: 20
- Swift Testing tests: 0 (reported separately, completed instantly)
- **Total: 20 tests**

**Xcode Scheme** (`xcodebuild -scheme VoiceDock test`):
- XCTest tests: 24 (includes 4 additional HotKeyManagerTests)
- Swift Testing tests: 0
- **Total: 24 tests**

**Note**: No double-counting — SwiftPM and Xcode run different test bundles.
- SwiftPM tests: VoiceDockCoreTests target only (20 tests)
- Xcode tests: VoiceDockTests target (24 tests with UI/hotkey simulations)

```text
swift package describe:  PASS
swift build:             PASS
swift test:              PASS (20 XCTest tests)
xcodegen generate:       PASS
xcodebuild Debug build:  PASS
xcodebuild Debug test:   PASS (24 XCTest tests)
xcodebuild Release build: PASS
codesign verify:         PASS
Info.plist lint:         PASS
```

## Frozen State

Candidate 6 is frozen after this build.

**DO NOT** rebuild, re-sign, replace, or overwrite:

```text
dist/candidate-6/VoiceDock.app
```

Any further changes must create Candidate 7.

## Next Step

Continue with remaining Gate C tests and stability verification.

## Owner Physical Verification (2026-06-23)

### Confirmed Tests (Gate B + Gate C Complete)

| Test | Result | Notes |
|------|--------|-------|
| Microphone permission | GRANTED | System prompt granted |
| Accessibility permission | GRANTED | System prompt granted |
| Hotkey press | PASS | Physical key press detected |
| Hotkey release | PASS | Physical key release detected |
| App remained alive | PASS | No crash - contradicts earlier crash hypothesis |
| Returned to Ready | PASS | UI returned to ready state |
| Mandarin transcription | PASS | "好了，好，你能听到吗？" |
| English transcription | PASS (pipeline) | "Hello world, this is voice task of the voice tech transportation." |
| Mixed Chinese-English | PASS (pipeline) | "This is the second test, 你好，这第二次测试。" |
| Clipboard delivery | PASS | Clipboard delivery confirmed |
| Automatic paste | PASS | Text pasted without manual Cmd+V |
| Optional Return | PASS | Cursor moved to new line |
| 3-session stability | PASS | 3 consecutive cycles without crash |

### Recognition Quality Findings

| Aspect | Status |
|--------|--------|
| Pipeline functionality | ✅ PASS |
| English accuracy | ⚠️ PARTIAL |
| Mixed Chinese-English accuracy | ⚠️ PARTIAL |
| Product-name recognition ("VoiceDock") | ❌ NEEDS IMPROVEMENT |

### Disconfirmed Hypothesis

**Earlier crash reports were NOT Candidate 6** - they matched Candidate 4's UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`). Candidate 6 has a different UUID (`3745FA4C-2619-3DDB-8565-0CBBA80AC7E1`) and has been physically verified as stable.

### Pending Physical Tests

**Gate C is COMPLETE.** No pending physical tests remain.