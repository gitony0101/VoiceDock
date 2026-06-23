# Candidate 6 Summary

**Status**: First Physically Verified Development Baseline (Frozen)

**Retention**: **KEEP** — Rollback candidate and first physically verified development baseline

**Note**: Candidate 6 is NOT the final release. Candidate 7 will be the final release after complete Gate C verification and final UI cleanup.

## Identity

```text
Artifact: dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle ID: com.voicedock.app
Signing: Ad-hoc
```

## Verified Tests

### Automated Gates (All Pass)
- swift package describe: PASS
- swift build: PASS
- swift test: PASS (24 Mock-based tests)
- xcodegen generate: PASS
- xcodebuild Debug build: PASS
- xcodebuild Debug test: PASS (24 tests)
- xcodebuild Release build: PASS
- codesign verify: PASS
- Info.plist lint: PASS

### Physical Verification (Partial Pass)
| Test | Result |
|------|--------|
| Microphone permission | GRANTED |
| Accessibility permission | GRANTED |
| Hotkey press/release | PASS |
| App stability | PASS (no crash) |
| Mandarin transcription | PASS ("好了，好，你能听到吗？") |
| Mixed Chinese-English | PASS (pipeline verified) |
| English transcription | PENDING |
| Clipboard verification | PENDING |
| Automatic paste | PENDING |
| 3-session stability | PENDING |

## Repairs Included

1. **MainActor isolation safety** — `Task { @MainActor ... }` instead of `MainActor.assumeIsolated`
2. **Permission state refresh** — UI updates on app activation
3. **Activation observer** — Listens for `NSApplication.didBecomeActive`
4. **Diagnostic log cleanup** — Removes stale logs on launch/exit
5. **Audio format handling** — Hardware format → 16 kHz mono Float32
6. **Buffer timeout protection** — 60s max buffer

## Crash Provenance

**Candidate 6 has NO matching crash reports.**

All previously reported crashes matched Candidate 4 UUID (`646d1bd8-d300-3adb-8ab7-9234321683c6`).

## Evidence Files

- `evidence.md` — Full candidate evidence
- `owner-verification-partial.txt` — Owner test record
- `VERIFICATION_STATUS.md` — Verification dashboard
- `ga te-c-remaining-tests.md` — Test instructions

## Status

**FROZEN** — Do not rebuild, re-sign, or modify.

Any further changes require Candidate 7.

## Role

- Current development baseline
- Rollback candidate for Candidate 7
- First physically verified development baseline

---

*Candidates 4 and 6 form the critical engineering pair: one proves the failure mode, one proves the repair works.*