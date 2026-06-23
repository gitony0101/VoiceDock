# VoiceDock Decisions

## D1: XcodeGen Is Authoritative

**Decision**: `project.yml` is the single source of truth for Xcode targets, dependencies, Info.plist properties, build settings, and schemes.

**Implication**: Do not manually edit `VoiceDock.xcodeproj/project.pbxproj`. Change `project.yml`, then run `xcodegen generate`.

**Evidence**: `AGENTS.md`, `CLAUDE.md`, and `project.yml` all agree.

---

## D2: Source Ownership

**Decision**: `VoiceDockCore/Sources` owns reusable production core types. `VoiceDockApp` owns the native app shell, AppKit/SwiftUI UI, permissions, and hotkey service.

**Implication**: Do not restore deleted duplicate production files under `VoiceDockApp/ASR`, `VoiceDockApp/Audio`, or `VoiceDockApp/SessionCoordinator.swift`.

---

## D3: SwiftPM Test Harness

**Decision**: `Package.swift` defines the SwiftPM test harness only. It must not maintain duplicate production implementations.

**Implication**: Before relying on `swift test`, ensure SwiftPM uses the same source ownership as Xcode. Currently `VoiceDockCore` is a library target with tests in `VoiceDockAppTests`.

---

## D4: Accessibility Is AX/CGEvent

**Decision**: The app uses `AXIsProcessTrusted()`/`AXIsProcessTrustedWithOptions()` and CGEvents for paste simulation.

**Implication**: Permission UX must clearly call this "Accessibility permission" — not Apple Events.

---

## D5: Required Shortcut

**Decision**: The MVP shortcut is **Control+Option+Space**.

**Implication**: Older Command+Space references are stale and must not guide implementation.

---

## D6: Crash Provenance by UUID Matching

**Decision**: Crash reports must be attributed to the correct candidate by matching Mach-O UUID, not by assumption or file timestamp.

**Finding (2026-06-23)**: All crash reports with UUID `646d1bd8-d300-3adb-8ab7-9234321683c6` belonged to **Candidate 4**. Candidate 5 and Candidate 6 share UUID `3745FA4C-2619-3DDB-8565-0CBBA80AC7E1` and have **no matching crash reports**.

**Conclusion**: 
- Candidate 4: Proven physical crash (MainActor isolation failure)
- Candidate 5: Never physically crash-tested
- Candidate 6: First physically verified stable baseline

**Implication**: Candidate 6 is safe to use for Gate C testing. The "Candidate 5 crash" was actually Candidate 4.

---

## D7: Candidate Retention Strategy

**Decision (2026-06-23)**: Three-tier retention:

1. **Final Product**: `dist/VoiceDock.app` (Candidate 7 target)
2. **Rollback Baseline**: `dist/archive/candidate-6/VoiceDock.app` (first physically verified development baseline)
3. **Light Evidence**: Summaries for Candidates 1-5

**Implication**: After Candidate 7 verification:
- Keep: Candidate 6 (rollback), Candidate 4 crash evidence
- Delete: Candidate 1-3, 5 full `.app` bundles (retain summaries only)

**Note**: Candidate 6 is NOT the final release. It is the first physically verified development baseline and verified rollback candidate.

---

## D8: Repository Cloud Checkpoint

**Decision (2026-06-23)**: Create a clean Git checkpoint containing:
- Source code, tests, build configuration
- Sanitized evidence summaries (no raw crash reports, logs, or `.app` bundles)
- Comprehensive `.gitignore` excluding local artifacts

**Implication**: Repository remains useful for collaboration without gigabytes of build artifacts or privacy-sensitive crash dumps.

---

## D9: Privacy Defaults

**Decision**: VoiceDock defaults to:
- Local microphone processing only
- No telemetry
- No transcript history
- No cloud upload
- No background network activity except explicit model download

**Implication**: Any feature that changes these defaults requires explicit owner approval and documentation.