# VoiceDock Phased ASR Maintenance Agent

## Purpose

This document is the long-term operating framework for maintaining and evolving VoiceDock.

VoiceDock is a native macOS push-to-talk application for local automatic speech recognition (ASR). Its product scope is intentionally narrow:

> VoiceDock supports compatible local ASR models for speech-to-text input.

VoiceDock is not a general-purpose AI model manager.

This document defines boundaries, sequencing, and phase gates. It must not be treated as authorization to implement every phase at once.

---

## 1. Product Scope

VoiceDock supports only speech-recognition models.

### Supported category

- Automatic Speech Recognition (ASR)
- Speech-to-text
- Local inference
- Native macOS execution
- VoiceDock-compatible model formats
- Architectures supported by compiled VoiceDock adapters

### Explicitly unsupported categories

- Large language models
- Text generation models
- Vision models
- Image generation models
- Text-to-speech models
- Embedding models
- Reranking models
- Multimodal chat models
- Arbitrary Hugging Face repositories
- Models requiring Python or remote code execution

The product promise is:

> Import and run any VoiceDock-compatible local ASR model.

The product promise is not:

> Import and run any Hugging Face model.

---

## 2. Compatibility Boundary

A model is VoiceDock-compatible only when all of the following are true:

1. It is an ASR model.
2. Its architecture is supported by a compiled VoiceDock adapter.
3. Its weights use a supported local runtime format.
4. Its tokenizer and audio processor are supported.
5. It can run through VoiceDock's native Swift and MLX runtime.
6. It does not require Python.
7. It does not require `trust_remote_code`.
8. It does not require a subprocess or local model server.
9. It does not require model conversion inside VoiceDock.
10. It passes VoiceDock compatibility validation before activation.

A new size or quantization of an already supported ASR architecture may be imported without changing VoiceDock code.

A completely new ASR architecture requires a new compiled adapter and a separate development phase.

Unknown architectures must be rejected with a clear compatibility message.

---

## 3. Lightweight Product Rules

VoiceDock must remain a focused speech-input utility.

### Mandatory rules

1. Model weights must never be embedded in the application bundle.
2. Model weights must remain under:

   `~/Library/Application Support/VoiceDock/Models/`

3. VoiceDock may load only one active ASR provider at a time.
4. Inactive models must not remain in memory.
5. Normal app startup must not scan model tensors.
6. Normal app startup may read only lightweight settings and registry metadata.
7. Model downloads must never begin during ordinary startup.
8. Hugging Face network access must never be required for local transcription.
9. Model-management operations must remain outside the real-time push-to-talk path.
10. Model verification, file hashing, and download work must not block the main thread.
11. Import failure must not replace or damage the current active model.
12. Unknown repositories must never execute arbitrary code.
13. VoiceDock must not include Python, Conda, Docker, Node, Rosetta, or a local HTTP server.
14. VoiceDock must not perform model conversion or quantization.
15. Model files, recordings, and downloaded weights must never enter Git.
16. Public default model behavior must not change without an explicit owner decision.

---

## 4. Current Owner Decisions

These decisions are active unless the owner explicitly changes them.

1. Use Qwen3-ASR 1.7B 4-bit for owner dogfooding and long-term daily evaluation (Quality/default).
2. Use Qwen3-ASR 0.6B 8-bit as the Fast model option (via `VOICEDOCK_ASR_MODEL`).
3. Nemotron support removed (2026-07-13).
4. Qwen3-ASR 0.6B 6-bit support removed (2026-07-13).
5. Continue improving VoiceDock as a daily-use product.
6. Add model management gradually.
7. Support only compatible ASR models.
8. Include application icon, menu-bar icon, interface, and usability work in a dedicated product-polish phase.

---

## 5. Development Method

VoiceDock must be developed one phase at a time.

Each phase must have its own Markdown task specification.

The master framework does not authorize implementation by itself.

Before starting a phase, create one phase file using this naming pattern:

`docs/phases/VOICEDOCK_PHASE_<NUMBER>_<NAME>.md`

Only one phase may be active at a time.

The active phase must define:

- objective
- user value
- current baseline
- exact scope
- explicit non-goals
- files allowed to change
- files forbidden to change
- implementation sequence
- tests
- acceptance criteria
- rollback plan
- owner-operated verification
- completion promise

The agent must stop after completing the active phase.

The agent must not automatically continue to the next phase.

---

## 6. Phased Roadmap

### Phase 0 — Current Baseline Closure

Goal:

Create a clean and trustworthy checkpoint for the Qwen3 dual-model VoiceDock implementation.

Scope:

- Qwen3-ASR 1.7B 4-bit as Quality/default
- Qwen3-ASR 0.6B 8-bit as Fast option
- Nemotron retired from active support (2026-07-13)
- Qwen3-ASR 0.6B 6-bit retired from active support (2026-07-13)
- document current model support
- finish current repository cleanup
- reconcile current reports and test totals
- confirm build and test gates
- establish a clean Git checkpoint
- record current known recognition weaknesses
- no new UI
- no model import
- no Hugging Face integration

Completion condition:

The repository has one verified baseline that can be safely extended.

---

### Phase 1 — Daily Driver and Product Polish

Goal:

Make VoiceDock reliable and pleasant for daily use with the currently installed models.

Scope:

- persistent owner-selected model
- current-model indicator
- model-loading state
- warmup state
- recording state
- transcribing state
- error state
- stable push-to-talk flow
- duplicate-paste prevention
- transcript-delivery reliability
- hotkey settings
- auto-paste setting
- optional Return setting
- launch-at-login
- application icon
- menu-bar icon
- preferences organization
- first-run and permission recovery
- About screen

Non-goals:

- no local-folder import
- no Hugging Face download
- no new architecture adapter
- no general model manager

Completion condition:

The owner can use Qwen3-ASR 1.7B 4-bit as a daily driver without Terminal-based model selection.

---

### Phase 2 — Installed ASR Model Registry

Goal:

Manage only the ASR models already installed and already supported by VoiceDock.

Scope:

- lightweight model registry
- list installed models
- show active model
- show architecture
- show quantization
- show disk size
- show validation state
- activate model
- verify model
- safely delete inactive model
- protect active model from deletion
- load only one model at a time
- rollback if activation fails

Non-goals:

- no arbitrary local model import
- no Hugging Face network access
- no new model architecture

Completion condition:

The user can manage and switch among the existing supported models from VoiceDock.

---

### Phase 3 — Import Compatible Local ASR Folder

Goal:

Allow the user to import a local model directory only when it matches a supported ASR architecture.

Scope:

- choose local folder
- inspect configuration
- detect supported ASR architecture
- match compiled adapter
- verify required files
- reject unsupported model categories
- reject unsafe remote-code requirements
- copy into managed storage
- install atomically
- register model
- run self-test
- activate only after successful validation

Recommended MVP behavior:

Copy the model into managed VoiceDock storage.

Do not reference arbitrary external folders in the MVP.

Completion condition:

A compatible variant of an already supported ASR architecture can be imported without code changes.

---

### Phase 4 — Install Compatible ASR Model from Hugging Face

Goal:

Use Hugging Face only as a model-file source.

Scope:

- accept repository identifier
- inspect repository metadata
- determine whether it is a supported ASR architecture
- reject non-ASR repositories
- reject unsupported architecture
- reject remote-code requirements
- display required download size
- download only required files
- show progress
- support cancellation
- verify downloaded files
- pass the same installer used by local-folder import

Non-goals:

- no Hugging Face runtime shell
- no Python
- no arbitrary repository execution
- no model conversion
- no support for non-ASR models

Completion condition:

A supported VoiceDock-compatible ASR repository can be installed without changing the real-time transcription path.

---

### Phase 5 — Recognition Quality and Personal Vocabulary

Goal:

Improve real-world mixed Chinese-English transcription without increasing model size.

Scope:

- custom vocabulary
- technical-term normalization
- model-name normalization
- repeated-syllable cleanup
- mixed punctuation
- raw transcript retention
- corrected transcript separation
- user-editable replacement rules
- safeguards against over-correction

Examples:

- `Voice Dock` or `Voice Doctor` → `VoiceDock`
- `Local A S R` → `local ASR`
- `both trap` → `bootstrap`
- `APP Router` → `App Router`
- repeated forms such as `关关闭` → `关闭`

Completion condition:

VoiceDock improves recurring user-specific terms without hiding the original ASR output.

---

### Phase 6 — Additional ASR Architecture Adapter

Goal:

Add one new ASR architecture only when there is a demonstrated user need.

Rules:

- one architecture per phase
- compiled adapter only
- full compatibility specification
- benchmark against existing models
- no dynamic executable plugins
- no unrelated model categories

Completion condition:

The new architecture passes the same activation, unload, benchmark, and regression gates as existing adapters.

---

## 7. Phase Gate Template

Every phase task specification must include the following sections.

### 1. Phase title

### 2. One-sentence objective

### 3. User problem

### 4. Current verified baseline

### 5. Scope

### 6. Explicit non-goals

### 7. Architecture constraints

### 8. Files allowed to change

### 9. Files forbidden to change

### 10. Implementation sequence

### 11. Tests

Separate:

- unit tests
- filesystem integration tests
- opt-in model tests
- owner microphone tests
- manual UI tests

### 12. Performance gates

### 13. Acceptance criteria

### 14. Rollback plan

### 15. Documentation updates

### 16. Final evidence report

### 17. Completion promise

---

## 8. Agent Operating Rules

The development agent must:

1. Read `AGENTS.md` completely.
2. Read `VOICEDOCK_MASTER_PROMPT.md` completely.
3. Read this document completely.
4. Read the active phase specification completely.
5. Inspect the current Git status before editing.
6. Treat `project.yml` as the Xcode source of truth.
7. Preserve current model files.
8. Preserve Nemotron support.
9. Preserve the existing push-to-talk path unless the phase explicitly changes it.
10. Distinguish compile success from runtime success.
11. Distinguish file validation from model load.
12. Distinguish model load from warmup.
13. Distinguish warmup from real inference.
14. Preserve raw error text.
15. Never invent successful measurements.
16. Never declare a phase complete without the phase acceptance evidence.
17. Never commit or push unless the owner explicitly requests it.
18. Stop after the active phase.
19. Do not create the next phase automatically.
20. Do not broaden VoiceDock beyond ASR.

---

## 9. Documentation Structure

Recommended structure:

```text
docs/
  phases/
    VOICEDOCK_PHASE_0_BASELINE_CLOSURE.md
    VOICEDOCK_PHASE_1_DAILY_DRIVER_AND_PRODUCT_POLISH.md
    VOICEDOCK_PHASE_2_INSTALLED_ASR_MODEL_REGISTRY.md
    VOICEDOCK_PHASE_3_LOCAL_ASR_IMPORT.md
    VOICEDOCK_PHASE_4_HUGGING_FACE_ASR_INSTALL.md
    VOICEDOCK_PHASE_5_RECOGNITION_QUALITY.md
  architecture/
  benchmarks/
  decisions/
```

Only the current active phase requires a complete executable task prompt.

Future phase files may remain short roadmap placeholders until the owner activates them.

---

## 10. Immediate Next Step

The next active phase should be:

> Phase 0 — Current Baseline Closure

Phase 0 must finish the current Qwen work, preserve all installed ASR models, document the owner dogfooding decision, reconcile the repository state, and establish a trustworthy checkpoint.

After Phase 0 is accepted, create the separate Phase 1 task specification for daily-driver usability, application icon, menu-bar icon, and interface polish.

Do not begin local import or Hugging Face integration before Phases 0, 1, and 2 are complete.

---

## 11. Required First Agent Action

When this framework is first introduced, the agent must:

1. Perform a read-only repository audit.
2. Confirm the current baseline.
3. Create only:

   `docs/phases/VOICEDOCK_PHASE_0_BASELINE_CLOSURE.md`

4. Do not implement Phase 0 in the same task.
5. Report unresolved decisions requiring owner approval.
6. Stop.

Completion status for this planning action:

`VOICEDOCK_PHASE_0_PLAN_READY`
