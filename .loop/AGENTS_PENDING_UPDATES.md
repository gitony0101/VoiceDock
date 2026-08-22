# Pending AGENTS.md Updates (blocked by write-protection timeouts)

During the 0.2 RC1 source-sealing pass, four factual sync edits to `AGENTS.md`
were approved by the owner but could not be applied because the file's write
protection confirmation timed out repeatedly. Two earlier edits DID apply:

Applied:
1. "Fixed MVP Technology": Nemotron model line replaced by the Qwen3 family
   (qwen3-1.7b-4bit Quality default, qwen3-0.6b-8bit Fast), with a historical
   retirement note pointing at `docs/decisions/VOICEDOCK_NEMOTRON_RETIREMENT.md`.
2. "Current MVP Scope": `local Nemotron transcription` → `local Qwen3-ASR transcription`.

The following four edits are still PENDING. Apply them manually (or approve a
future agent pass) to finish AGENTS.md synchronization.

---

## Pending Edit 1 — MVP scope exclusion list

REPLACE:

```text
Explicitly excluded from this Smart Ralph specification:

VAD
automatic endpointing
pre-roll
partial streaming transcripts
model selection
model switching
model registry
managed model downloads
external model folders
AI assistant
chat providers
conversation history
TTS
signing and notarization unless credentials are available

Do not widen scope until the Push-to-Talk MVP is verified.
```

WITH:

```text
Explicitly excluded from the original Smart Ralph specification:

VAD
automatic endpointing
pre-roll
partial streaming transcripts
AI assistant
chat providers
conversation history
TTS
signing and notarization unless credentials are available

Historical note: "model selection / model switching / model registry / managed
model downloads / external model folders" were excluded from the original MVP
specification. VoiceDock 0.2 intentionally supersedes this: Quality/Fast Qwen3
model selection, persistent preference, and Apply & Restart are implemented
product features. That part of the exclusion list no longer applies.

Do not widen scope beyond the implemented 0.2 feature set without a new
specification.
```

## Pending Edit 2 — Architecture section

REPLACE the header line:

```text
**Current Implementation (2026-06-22 Refactored)**:
```

WITH:

```text
**Current Implementation (VoiceDock 0.2 RC1)**:
```

In the `VoiceDockCore/` tree listing, REPLACE:

```text
├── ASRProvider.swift       Protocol: actor ASRProvider
├── MLXAudioSTTProvider.swift Nemotron ASR implementation
├── AudioCapture.swift      AVAudioEngine, 16 kHz mono Float32
├── AudioNormalizer.swift   Format conversion (pure function)
├── TranscriptDestination.swift Clipboard + CGEvent paste
├── SessionCoordinator.swift  State machine, workflow orchestration
└── VoiceDockError.swift    Unified error types
```

WITH:

```text
├── ASRProvider.swift       Protocol: actor ASRProvider
├── Qwen3ASRProvider.swift  Active Qwen3-ASR implementation
├── ASRProviderFactory.swift  Quality/Fast routing, one active provider
├── ASRModelPreferences.swift Persistent model preference
├── ModelStatus.swift       Selected-vs-active model state
├── ModelStorage.swift      Local model storage
├── AudioCapture.swift      AVAudioEngine, 16 kHz mono Float32
├── AudioNormalizer.swift   Format conversion (pure function)
├── TranscriptDestination.swift Clipboard + CGEvent paste
├── TranscriptDeliveryPolicy.swift Paste/Return delivery policy
├── TranscriptCorrectionEngine.swift Transcript correction
├── SessionCoordinator.swift  State machine, workflow orchestration
└── VoiceDockError.swift    Unified error types
```

In the `VoiceDockApp/` tree listing, ADD under PermissionManager:

```text
└── RestartHelper/          Packaged restart helper (Apply & Restart)
```

After rule 14 ("Keep one large ASR model resident on the M1 baseline"), APPEND:

```markdown
15. Exactly one ASR provider is active at a time; selection changes take
    effect only via Apply & Restart using the packaged restart helper.
16. `ModelStatus.activeModel` is written exactly once from the factory result;
    the saved preference (`selectedModel`) must never be presented as Active
    before provider creation.
17. Xcode unit tests run with TEST_HOST isolation; tests inject isolated
    preference stores and recorders and must never touch production
    diagnostics.
```

Also REPLACE in "ASR Boundary":

```text
The implementation may evolve from verified requirements, but shared interfaces must not expose unnecessary Nemotron internals.
```

WITH:

```text
The implementation may evolve from verified requirements, but shared interfaces must not expose unnecessary provider internals (Qwen3, Nemotron-historical, or future providers).
```

## Pending Edit 3 — Build and Verification status block

REPLACE:

```text
**Verified (2026-06-22)**:
- ✅ Debug build passes
- ✅ Release build passes
- ✅ 24 unit tests pass (all Mock-based)

**Pending Verification**:
- ⏳ Real microphone audio capture
- ⏳ Real ASR inference with Nemotron model
...
**Current Test Coverage Gap**: All 24 tests use `MockASRProvider` and `MockAudioCapture`. No test exercises the real ASR pipeline.
```

WITH:

```text
Automated gates (Debug build, Release build, swift test, xcodebuild test) are
run at every sealing point; current results live in git history for the
relevant release-sealing commit rather than as hard-coded counts here.

**Pending Verification (owner-only)**:
- ⏳ Final artifact acceptance for VoiceDock 0.2 RC1
- ⏳ Owner physical proof: Quality model, Fast model, Accessibility-gated
  paste, paste/Return behavior
```

(Keep the existing command examples unchanged.)

## Pending Edit 4 — Completion section

REPLACE the entire "**Current Status (2026-06-22)**" checklist and the
"run Nemotron locally through MLXAudioSTT" line in the completion flow with:

```text
AUTOMATED ENGINEERING GATES COMPLETE
FINAL OWNER ACCEPTANCE PENDING
```

and change the flow step to:

```text
run the active Qwen3-ASR model locally through MLXAudioSTT
```

Keep the closing rule: do not output `VOICEDOCK_COMPLETE` until final owner
verification is done.
