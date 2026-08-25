# VoiceDock Handoff

**Last Updated**: 2026-08-24 — VoiceDock 0.2 RC1 RELEASE SEALED

## Live Status

This document no longer maintains an independent status record.

**For current operational status, read `.loop/NOW.md` — it is the single
source of truth for live project state.**

## Summary (non-authoritative)

- Project: VoiceDock 0.2 RC1, source sealed on the
  `fix/stable-identity-accessibility` release-sealing branch.
- Canonical repository:
  `/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock-Stable-Identity-Accessibility-Fix`
- Automated engineering gates: complete at seal time.
- Final owner acceptance: **PASS** — owner verified the installed artifact
  built from `001135d33119e98a849a55a7d595dc7336eb613b` (Quality/Fast models,
  Accessibility-gated paste, paste/Return behavior, language fidelity).
- Release tag: `v0.2.0-rc1` → `001135d33119e98a849a55a7d595dc7336eb613b`.
- Known non-blocking observation: "VoiceDock" may transcribe as "voice dog"
  (Quality) or "VoiceDockk" (Fast) — ASR terminology debt, not fixed in
  0.2 RC1.

## Historical Context (do not treat as current claims)

Earlier stages are recorded in their own evidence documents:

- Qwen dual-model routing Stage A owner verification:
  `docs/status/VOICEDOCK_QWEN_DUAL_MODEL_STAGE_A_EVIDENCE.md`
- Nemotron retirement decision:
  `docs/decisions/VOICEDOCK_NEMOTRON_RETIREMENT.md`
- Qwen3 0.6B 6-bit retirement decision:
  `docs/decisions/VOICEDOCK_QWEN3_06B_6BIT_RETIREMENT.md`

Per-stage test counts and verification tables from those stages are preserved
in those documents only; they are not current status claims.
