Read AGENTS.md and docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md completely.

Perform a focused Qwen Duel readiness repair. Do not change model architecture, model defaults, dependencies, app icon, or installed model weights.

Required work:

1. Implement a real developer-only fixture recorder inside VoiceDockASRBench.

Add a command similar to:

VoiceDockASRBench record 
--fixture fixture_1_drl_web_coding 
--output "$HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/fixtures/fixture_1_drl_web_coding.wav"

The recorder must:

* use the existing VoiceDock AudioCapture path where practical
* save valid PCM WAV
* produce mono 16 kHz audio, or save source audio and normalize through the same production AudioNormalizer
* begin recording after an explicit user action
* stop recording after an explicit user action
* print duration, sample count, minimum, maximum and RMS
* never run an ASR model while recording
* never save recordings inside the repository
* safely replace an existing fixture only with explicit confirmation or a force flag

2. The owner must record exactly six WAV files once.

Both Qwen models must process the same six files.

Remove or correct any instruction suggesting that each model requires a separate recording.

3. Correct all benchmark command examples.

Do not use a quoted tilde path.

Use paths based on:

"$HOME/Library/Application Support/VoiceDock/Diagnostics/QwenDuel/..."

4. Reconcile the test counts.

Run and report separately:

* swift test
* xcodebuild test for the VoiceDock scheme
* any tests exclusive to SwiftPM
* any tests exclusive to Xcode

Explain why the currently documented counts 11 plus 15 plus 5 do not match the stated total of 26.

5. Verify that both installed model directories are valid.

Do not download either model again.

6. Search for duplicate complete Qwen model copies under the default Hugging Face cache.

Report exact paths and sizes.

Do not delete any cache during this task.

7. Prove that both models load and warm up in VoiceDockASRBench.

Capture exact load and warmup durations for:

* qwen3-0.6b-8bit
* qwen3-1.7b-4bit

Do not claim success based only on the executable building.

8. Update:

docs/QWEN3_ASR_MODEL_DUEL_IMPLEMENTATION.md

The document must contain:

* exact recording commands for all six fixtures
* exact benchmark commands for both models
* corrected path handling
* corrected test totals
* actual model load and warmup evidence
* duplicate cache findings
* the rule that each phrase is recorded exactly once

Restrictions:

* Do not change the production default
* Do not delete Nemotron
* Do not delete any Qwen model
* Do not download models again
* Do not add a public model UI
* Do not upgrade dependencies
* Do not commit or push
* Do not declare a model winner

Output exactly:

QWEN_DUEL_OWNER_READY

Only when the fixture recorder works, six WAV files can be recorded once, both models load and warm up, benchmark commands use valid paths, and the report matches the real test results.

