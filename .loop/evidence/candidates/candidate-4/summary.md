# Candidate 4 Summary

**Status**: Crashed — Root Cause Evidence Preserved

**Retention**: **KEEP** — Critical failure evidence for engineering learning

## Identity

```text
SHA-256: af34e1384915ce399ee740ee747486c8ed96ff4549c2588a08b9fc39b922df93
CDHash: a1ed1b26b1a954ae9bd0dde1224381803af07610
Mach-O UUID: 646D1BD8-D300-3ADB-8AB7-9234321683C6
```

## Failure Mode

```text
Exception: EXC_BAD_ACCESS / SIGBUS / KERN_INVALID_ADDRESS
Location: MainActor.assumeIsolated in AppDelegate.togglePopover(_:)
Trigger: Hotkey press/release during Gate B testing
```

## Root Cause

Unsafe use of `MainActor.assumeIsolated` in AppKit selector context caused crash when main queue re-entrancy occurred.

## Repair

Candidate 6 replaced `MainActor.assumeIsolated` with `Task { @MainActor ... }` pattern.

## Evidence Preserved

- `crash-gateB-124531.ips` — Original crash report (UUID matched)
- `gate-b-failure/` — Gate B failure evidence
- `physical-gate-b-20260622-124529/` — Physical test attempt record
- `runtime-diagnostics-124517.log` — Runtime logs

## Crash Provenance

All crash reports with UUID `646d1bd8-d300-3adb-8ab7-9234321683c6` match this candidate — **not** Candidate 5 or 6.

---

*This candidate represents a critical engineering learning moment: crash provenance must be established by UUID matching, not assumption.*