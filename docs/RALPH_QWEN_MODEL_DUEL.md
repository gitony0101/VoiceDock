# VoiceDock Qwen Model Duel

Read this specification completely at the beginning of every iteration.

Before editing, read:

1. AGENTS.md
2. docs/QWEN3_ASR_06B_6BIT_INVESTIGATION.md
3. docs/QWEN3_ASR_PHASE2A_IMPLEMENTATION_REPORT.md
4. docs/QWEN3_ASR_PHASE2B_RUNTIME_REPORT.md
5. QwenModelDescriptor.swift
6. ModelStorage.swift
7. ModelInstaller.swift
8. Qwen3ASRProvider.swift
9. ASRProviderFactory.swift
10. AudioCapture.swift
11. AudioNormalizer.swift
12. SessionCoordinator.swift
13. Package.swift
14. project.yml
15. The pinned mlx-audio-swift Qwen3ASR source and reference documentation

Treat AGENTS.md as authoritative.

## Objective

Implement and prepare a fair local comparison between:

mlx-community/Qwen3-ASR-0.6B-8bit

and:

mlx-community/Qwen3-ASR-1.7B-4bit

Nemotron must remain available as the stable fallback.

The existing Qwen3-ASR 0.6B 6-bit model must remain installed and untouched, but it is not a primary candidate in this duel.

Do not change the production default during this phase.

## Canonical Model Directories

Use FileManager applicationSupportDirectory APIs.

The final paths must be:

~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-8bit/

~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-1.7B-4bit/

Do not place model files in:

1. The repository
2. DerivedData
3. The application bundle
4. The default Hugging Face cache
5. /tmp

## Part 1: Generalize Qwen Model Descriptors

Extend the current descriptor architecture to support:

1. Qwen3-ASR 0.6B 6-bit
2. Qwen3-ASR 0.6B 8-bit
3. Qwen3-ASR 1.7B 4-bit

Each descriptor must include:

1. Stable ID
2. Display name
3. Hugging Face repository ID
4. Canonical directory name
5. Model family
6. Quantization
7. Approximate disk size
8. Required files

Avoid separate duplicated provider classes for every Qwen model.

## Part 2: Generalize Qwen3ASRProvider

Refactor Qwen3ASRProvider so that it accepts a Qwen model descriptor.

Expected conceptual API:

Qwen3ASRProvider(descriptor: QwenModelDescriptor)

The provider must:

1. Resolve the descriptor-specific canonical path
2. Validate that model directory
3. Load with Qwen3ASRModel.fromModelDirectory
4. Warm up deterministically
5. Transcribe using the same generation configuration for both models
6. Support unload safely
7. Report model ID in privacy-safe timing diagnostics
8. Never log production transcript contents

The existing 0.6B 6-bit behavior must continue to compile.

## Part 3: Install Both Duel Models

Install and validate:

mlx-community/Qwen3-ASR-0.6B-8bit

mlx-community/Qwen3-ASR-1.7B-4bit

Use the existing safe ModelInstaller workflow.

Requirements:

1. Temporary custom cache
2. Staging validation
3. Atomic final move
4. Cleanup after success or failure
5. No duplicate complete copies in the default Hugging Face cache
6. No damage to existing installed models
7. No simultaneous duplicate downloads
8. No model files tracked by Git

Record final model sizes.

## Part 4: Runtime Selection

Extend ASRProviderFactory to support:

VOICEDOCK_ASR_MODEL=qwen3-0.6b-8bit

VOICEDOCK_ASR_MODEL=qwen3-1.7b-4bit

Preserve existing values:

VOICEDOCK_ASR_MODEL=qwen3-0.6b-6bit

VOICEDOCK_ASR_MODEL=nemotron-0.6b-8bit

Unknown values must follow the documented safe fallback behavior.

Do not change the no-override production default in this phase.

## Part 5: Fair Diagnostic Benchmark

Create or extend a normal macOS Metal-capable diagnostic executable named:

VoiceDockASRBench

It must run outside XCTest.

The runner must accept:

1. A model ID
2. A directory containing WAV fixtures
3. A JSON manifest containing reference transcripts and keywords
4. An output JSON or CSV path
5. An optional language mode

Example conceptual commands:

VoiceDockASRBench run 
--model qwen3-0.6b-8bit 
--fixtures "/absolute/path/fixtures" 
--manifest "/absolute/path/manifest.json" 
--output "/absolute/path/qwen06b8bit.json"

VoiceDockASRBench run 
--model qwen3-1.7b-4bit 
--fixtures "/absolute/path/fixtures" 
--manifest "/absolute/path/manifest.json" 
--output "/absolute/path/qwen17b4bit.json"

Each model must run in a separate process.

The exact same WAV fixtures must be used for both models.

The runner must use:

1. The same AudioNormalizer
2. The same sample rate
3. The same language mode
4. The same generation configuration
5. The same transcript normalization rules

## Part 6: Benchmark Measurements

For each fixture and model, record:

1. Model identifier
2. Fixture identifier
3. Audio duration
4. Sample count
5. Waveform RMS
6. Model load time
7. Warmup time
8. Inference time
9. Real-time factor
10. Process resident memory before load
11. Process resident memory after load
12. Peak resident memory when available
13. Transcript
14. Normalized character error rate
15. Keyword recall
16. Critical semantic token recall
17. Negation preservation result

Diagnostic transcripts may be written only to the explicit local benchmark result directory.

Production diagnostics must remain transcript-free.

## Part 7: Local Benchmark Directory

Use:

~/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/

Suggested structure:

QwenDuel/
fixtures/
manifest.json
results/
qwen3-0.6b-8bit.json
qwen3-1.7b-4bit.json
reports/

This directory must remain outside Git.

## Part 8: Test Corpus

Create a manifest template for these phrases.

### Fixture 1: DRL and Web Coding Combined

今天我在 review 一个 deep reinforcement learning project。PPO uses an on-policy rollout，GAE controls the bias-variance tradeoff，and the bootstrap mask should be zero only when terminated is true，not when the episode is merely truncated。接下来请检查我的 Next.js App Router implementation，把 server-side data fetching 留在 Server Component 里，用 Zod validate the request body，并确认 POST slash API slash transcribe 在 Release build 里不会 block the main thread。

Critical terms:

PPO
GAE
on-policy
rollout
bias-variance tradeoff
bootstrap mask
terminated
not
truncated
Next.js
App Router
Server Component
Zod
POST
API
transcribe
Release build
main thread

### Fixture 2: VoiceDock Model Decision

VoiceDock should load Qwen3-ASR one point seven B four bit from Library Application Support，keep Nemotron as the fallback，and compare model load time，peak memory，real-time factor，and release-to-paste latency。如果 one point seven B 的 accuracy 没有明显提高，就不要因为参数更多而把它设置成 default model。

Critical terms:

VoiceDock
Qwen3-ASR
one point seven B
four bit
Library Application Support
Nemotron
fallback
peak memory
real-time factor
release-to-paste latency
没有
不要
default model

### Fixture 3: Replay Buffer

Replay buffer stores state，action，reward，next state and done。Off-policy algorithms can reuse historical transitions，but PPO usually collects fresh rollout data before each update。

### Fixture 4: Gymnasium Termination

在 Gymnasium 里面，done equals terminated or truncated，但是 bootstrap mask 只能根据 terminated 置零，不能把 time-limit truncation 当成 terminal state。

### Fixture 5: Swift and MLX

VoiceDock uses Swift six，AVFoundation and MLX Audio。The ASR provider is implemented as an actor，so model loading and transcription remain concurrency-safe。

### Fixture 6: Typed Web API

请把 POST slash API slash transcribe 改成 a typed Route Handler，使用 Zod validate the request body，并将 validation error 返回为 HTTP status code four hundred and twenty-two。

## Part 9: Recording Fairness

The owner records each fixture exactly once.

Both models must receive the same saved WAV file.

Do not compare two separately recorded readings of the same phrase.

Provide a small developer-only recording function using existing macOS audio APIs or the existing VoiceDock capture path.

Save recordings as valid WAV files under the local benchmark fixture directory.

Do not commit owner recordings.

## Part 10: Scoring

Produce these scores:

1. Normalized text accuracy: 25 points
2. Technical keyword recall: 20 points
3. Negation, number and logical-token preservation: 15 points
4. Manual semantic preservation field: 10 points
5. Inference speed and RTF: 15 points
6. Load and warmup performance: 10 points
7. Memory efficiency: 5 points

Total: 100 points.

Hard failures:

1. Missing or reversing a critical negation
2. Losing more than two critical technical terms in one fixture
3. Changing the central sentence meaning
4. Crashing or failing to transcribe
5. Excessive latency that makes push-to-talk unusable

## Part 11: Decision Rules

Recommend Qwen3-ASR 0.6B 8-bit as default when:

1. Its total score is within five points of 1.7B
2. It is materially faster or lighter
3. It passes all semantic hard gates

Recommend Qwen3-ASR 1.7B 4-bit as default when:

1. Its total quality score is at least ten points higher
2. It materially improves technical terms and negation preservation
3. Its latency remains acceptable for push-to-talk
4. Its memory usage is acceptable on the M1 16 GB target

Recommend a two-mode product when:

1. 0.6B is faster
2. 1.7B is meaningfully more accurate
3. Both pass minimum quality gates

Suggested modes:

Fast: Qwen3-ASR 0.6B 8-bit

Accurate: Qwen3-ASR 1.7B 4-bit

Fallback: Nemotron 0.6B 8-bit

Do not make the final default switch automatically.

## Part 12: Automated Tests

Add deterministic tests for:

1. All model descriptors
2. Canonical directory mapping
3. Required file validation
4. Factory environment parsing
5. Correct provider descriptor injection
6. Unknown model fallback
7. Benchmark manifest parsing
8. Character normalization
9. Keyword recall
10. Critical token recall
11. Negation checks
12. Result serialization

Unit tests must not load full MLX weights.

## Verification

Run:

1. swift build
2. swift test
3. xcodegen generate
4. xcodebuild Debug build
5. xcodebuild Debug test
6. xcodebuild Release build
7. git diff --check

Then verify:

1. Both models are installed at canonical paths
2. Both models load inside a normal macOS process
3. Both models complete warmup
4. VoiceDockASRBench builds
5. The benchmark runner accepts the same fixture set for both models
6. Existing Nemotron remains operational
7. Existing 0.6B 6-bit remains untouched
8. Production default remains unchanged
9. No model or fixture files are tracked by Git

## Documentation

Create:

docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md

Include:

1. Files changed
2. Descriptor architecture
3. Model paths and sizes
4. Runtime selection values
5. Benchmark runner commands
6. Fixture recording procedure
7. Scoring methodology
8. Empty result table ready for owner recordings
9. Automated gate results
10. Remaining owner actions

Do not declare a winner until the same recorded fixtures have been run through both models.

## Restrictions

1. Do not delete Nemotron.
2. Do not delete Qwen3-ASR 0.6B 6-bit.
3. Do not change the production default.
4. Do not upgrade mlx-audio-swift.
5. Do not upgrade mlx-swift.
6. Do not change the app icon.
7. Do not add public model-selection UI.
8. Do not commit or push.
9. Do not output VOICEDOCK_COMPLETE.

## Completion Promise

Output exactly:

QWEN_MODEL_DUEL_HARNESS_READY

Only when:

1. Both duel models are installed and validated
2. Both models load and warm up in a normal macOS process
3. Runtime selection supports both models
4. The benchmark runner builds
5. The same fixture set can be processed by both models
6. Scoring and result serialization are implemented
7. All automated gates pass
8. Nemotron remains available
9. Production default remains unchanged
10. Owner recording and execution steps are documented

Do not claim a model winner before owner fixture results exist.
































```

```





```

```

















```

```







```bash

```



```bash

```











```

```































































































```swift

```

















```bash

```


















