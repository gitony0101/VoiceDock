# VoiceDock Push-to-Talk MVP Tasks

## Task Overview

Implement a native macOS menu bar application for push-to-talk speech-to-text input using:
- Swift 6, SwiftUI, AppKit, AVFoundation
- Blaizzy/mlx-audio-swift for ASR
- Nemotron 3.5 ASR 0.6B 8-bit model
- Carbon/NSEvent for global hotkey
- CGEvent for paste simulation

Implementation follows POC-first workflow: validate end-to-end flow, then refactor, then test, then quality gates.

---

## Phase 1: Make It Work (POC)

Focus: Get a working end-to-end flow fast. Skip tests, accept hardcoded values, validate the core idea works.

### Task 1.1: Project Setup and Package.swift

- **Goal**: Create Xcode project structure and SPM dependency on mlx-audio-swift
- **Acceptance Criteria**:
  1. VoiceDock.xcodeproj exists with macOS App target
  2. Package.swift declares mlx-audio-swift dependency
  3. Project builds (may have unused import warnings)
- **Files to Create**:
  - `VoiceDock.xcodeproj/project.pbxproj`
  - `Package.swift`
  - `VoiceDockApp/VoiceDockApp.swift`
  - `VoiceDockApp/Info.plist`
- **Dependencies**: None
- **Verification**:
  ```bash
  xcodebuild -list -project VoiceDock.xcodeproj && \
  swift package dump-package | grep -q "mlx-audio-swift" && \
  echo "SETUP_PASS" || echo "SETUP_FAIL"
  ```
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' build 2>&1 | tail -5
  ```
- **Commit**: `feat(project): initial Xcode project with mlx-audio-swift dependency`
- _Requirements: FR-1.1, FR-1.3, NFR-4.3_
- _Design: File Structure section_

### Task 1.2: AudioCapture Implementation

- **Goal**: Implement microphone capture with AVAudioEngine and non-blocking tap callback
- **Acceptance Criteria**:
  1. AudioCapture class initializes AVAudioEngine
  2. Tap installed on input node with 16 kHz mono Float32 format
  3. start()/stop()/cancel() methods work
  4. Audio buffer accumulates as [Float] array
- **Files to Create**:
  - `VoiceDockApp/Audio/AudioCapture.swift`
- **Dependencies**: 1.1
- **Verification**:
  ```bash
  grep -q "installTap" VoiceDockApp/Audio/AudioCapture.swift && \
  grep -q "AVAudioEngine" VoiceDockApp/Audio/AudioCapture.swift && \
  grep -q "pcmFormatFloat32" VoiceDockApp/Audio/AudioCapture.swift && \
  echo "AUDIOCAPTURE_PASS"
  ```
- **Commit**: `feat(audio): implement AudioCapture with AVAudioEngine`
- _Requirements: FR-4.1, FR-4.2, FR-4.3, FR-4.4, AC-5.1, AC-6.1, AC-6.2, AC-6.3_
- _Design: AudioCapture component_

### Task 1.3: AudioNormalizer Implementation

- **Goal**: Implement format conversion to canonical 16 kHz mono Float32
- **Acceptance Criteria**:
  1. normalize() accepts [Float] and AVAudioPCMBuffer
  2. Returns nil for empty input (no crash)
  3. Handles interleaved to deinterleaved conversion
  4. Handles multi-channel to mono downmix
- **Files to Create**:
  - `VoiceDockApp/Audio/AudioNormalizer.swift`
- **Dependencies**: 1.2
- **Verification**:
  ```bash
  grep -q "func normalize" VoiceDockApp/Audio/AudioNormalizer.swift && \
  grep -q "guard !samples.isEmpty" VoiceDockApp/Audio/AudioNormalizer.swift && \
  echo "NORMALIZER_PASS"
  ```
- **Commit**: `feat(audio): implement AudioNormalizer format conversion`
- _Requirements: FR-5.1, FR-5.2, FR-5.3, FR-5.4, FR-5.5, AC-6.1, AC-6.2, AC-6.3, AC-6.5_
- _Design: AudioNormalizer component_

### Task 1.4: ASRProvider Protocol and MLXAudioSTT Implementation

- **Goal**: Define model-agnostic ASR protocol and implement with MLXAudioSTT
- **Acceptance Criteria**:
  1. `actor ASRProvider` protocol with load/warmup/transcribe/unload
  2. `MLXAudioSTTProvider` implements protocol
  3. Uses `GLMASRModel.fromPretrained("mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")`
  4. ASError enum with loadFailed/warmupFailed/inferenceFailed
- **Files to Create**:
  - `VoiceDockApp/ASR/ASRProvider.swift`
  - `VoiceDockApp/ASR/MLXAudioSTTProvider.swift`
  - `VoiceDockApp/ASR/ASError.swift`
- **Dependencies**: 1.3
- **Verification**:
  ```bash
  grep -q "actor.*ASRProvider" VoiceDockApp/ASR/ASRProvider.swift && \
  grep -q "fromPretrained" VoiceDockApp/ASR/MLXAudioSTTProvider.swift && \
  grep -q "nemotron" VoiceDockApp/ASR/MLXAudioSTTProvider.swift && \
  echo "ASRPROVIDER_PASS"
  ```
- **Commit**: `feat(asr): implement ASRProvider protocol with MLXAudioSTT`
- _Requirements: FR-6.1, FR-6.2, FR-6.3, FR-6.4, FR-6.5, FR-6.6, AC-7.1, AC-7.2, AC-7.4_
- _Design: ASRProvider component_

### Task 1.5: TranscriptDestination Implementation

- **Goal**: Implement clipboard copy and CGEvent paste simulation
- **Acceptance Criteria**:
  1. copyToClipboard() uses NSPasteboard
  2. simulatePaste() sends Command-V via CGEvent
  3. simulateReturn() sends Return key
  4. Accessibility check via AXIsProcessTrusted()
  5. Graceful degrade to clipboard-only if permission denied
- **Files to Create**:
  - `VoiceDockApp/Delivery/TranscriptDestination.swift`
- **Dependencies**: 1.4
- **Verification**:
  ```bash
  grep -q "NSPasteboard" VoiceDockApp/Delivery/TranscriptDestination.swift && \
  grep -q "CGEvent" VoiceDockApp/Delivery/TranscriptDestination.swift && \
  grep -q "AXIsProcessTrusted" VoiceDockApp/Delivery/TranscriptDestination.swift && \
  echo "TRANSCRIPTDEST_PASS"
  ```
- **Commit**: `feat(delivery): implement TranscriptDestination with clipboard and paste`
- _Requirements: FR-7.1, FR-7.2, FR-7.3, FR-7.4, FR-7.5, FR-7.6, AC-8.1, AC-8.2, AC-9.1, AC-9.2, AC-9.3, AC-9.6_
- _Design: TranscriptDestination component_

### Task 1.6: SessionCoordinator Implementation

- **Goal**: Implement central actor owning workflow state and coordinating all subsystems
- **Acceptance Criteria**:
  1. AppState enum with idle/loading/ready/listening/transcribing/delivering/error
  2. @Published state for SwiftUI observation
  3. startRecording()/stopRecording()/cancelRecording() methods
  4. ensureModelLoaded() serializes ASR lifecycle
  5. Dependency injection for AudioCapture, AudioNormalizer, ASRProvider, TranscriptDestination
- **Files to Create**:
  - `VoiceDockApp/Coordinator/SessionCoordinator.swift`
  - `VoiceDockApp/Coordinator/AppState.swift`
- **Dependencies**: 1.5
- **Verification**:
  ```bash
  grep -q "actor SessionCoordinator" VoiceDockApp/Coordinator/SessionCoordinator.swift && \
  grep -q "@Published" VoiceDockApp/Coordinator/SessionCoordinator.swift && \
  grep -q "startRecording" VoiceDockApp/Coordinator/SessionCoordinator.swift && \
  echo "COORDINATOR_PASS"
  ```
- **Commit**: `feat(coordinator): implement SessionCoordinator state machine`
- _Requirements: FR-1.4, FR-1.5, AC-1.3, AC-1.4_
- _Design: SessionCoordinator component_

### Task 1.7: HotKeyManager Implementation

- **Goal**: Implement global push-to-talk hotkey detection
- **Acceptance Criteria**:
  1. Carbon RegisterEventHotKey for system-wide detection
  2. Configurable hotkey (default Command+Space)
  3. Hotkey press starts recording, release stops
  4. Prevents re-entrant recording during transcription
- **Files to Create**:
  - `VoiceDockApp/HotKey/HotKeyManager.swift`
- **Dependencies**: 1.6
- **Verification**:
  ```bash
  grep -q "RegisterEventHotKey" VoiceDockApp/HotKey/HotKeyManager.swift && \
  grep -q "EventHotKeyRef" VoiceDockApp/HotKey/HotKeyManager.swift && \
  echo "HOTKEY_PASS"
  ```
- **Commit**: `feat(hotkey): implement global push-to-talk with Carbon`
- _Requirements: FR-3.1, FR-3.2, FR-3.3, FR-3.4, FR-3.5, AC-4.1, AC-4.2, AC-4.3, AC-4.4, AC-4.5_
- _Design: HotKeyManager (Technical Decisions table)_

### Task 1.8: PermissionManager Implementation

- **Goal**: Implement microphone and Accessibility permission checking with pre-permission explanation
- **Acceptance Criteria**:
  1. checkMicrophonePermission() with pre-prompt explanation
  2. checkAccessibilityPermission() with AXIsProcessTrustedWithOptions
  3. Deep link to System Settings for denied permissions
  4. PermissionStatus enum for UI feedback
- **Files to Create**:
  - `VoiceDockApp/Permissions/PermissionManager.swift`
  - `VoiceDockApp/Permissions/PermissionExplanation.swift`
- **Dependencies**: 1.7
- **Verification**:
  ```bash
  grep -q "AVCaptureDevice" VoiceDockApp/Permissions/PermissionManager.swift && \
  grep -q "AXIsProcessTrustedWithOptions" VoiceDockApp/Permissions/PermissionManager.swift && \
  echo "PERMISSIONS_PASS"
  ```
- **Commit**: `feat(permissions): implement PermissionManager with pre-permission UX`
- _Requirements: FR-2.1, FR-2.2, FR-2.3, FR-2.4, AC-2.1, AC-2.3, AC-2.4, AC-3.1, AC-3.3, AC-3.4, AC-3.5_
- _Design: Permissions (Technical Decisions)_

### Task 1.9: MenuBarView Implementation

- **Goal**: Implement SwiftUI menu bar view with state observation
- **Acceptance Criteria**:
  1. MenuBarView displays icon with state-based color/symbol
  2. States: idle/loading/ready/listening/transcribing/delivering/error
  3. StatusPopover shows detailed status and progress
  4. Quit action in popover
  5. Permission prompts with settings deep link
- **Files to Create**:
  - `VoiceDockApp/Views/MenuBarView.swift`
  - `VoiceDockApp/Views/StatusPopover.swift`
  - `VoiceDockApp/Views/Icons/MenuBarIcon.swift`
- **Dependencies**: 1.8
- **Verification**:
  ```bash
  grep -q "@ObservedObject" VoiceDockApp/Views/MenuBarView.swift && \
  grep -q "SessionCoordinator" VoiceDockApp/Views/MenuBarView.swift && \
  grep -q "case.*listening" VoiceDockApp/Views/MenuBarView.swift && \
  echo "MENUBAR_PASS"
  ```
- **Commit**: `feat(ui): implement MenuBarView with state observation`
- _Requirements: FR-1.2, FR-1.3, IF-1.1, IF-1.2, IF-1.3, IF-1.4, IF-1.5, AC-1.2, AC-1.3, AC-10.1, AC-10.2, AC-10.3, AC-10.4, AC-10.5, AC-10.6_
- _Design: MenuBarView component_

### Task 1.10: App Entry Point and Wiring

- **Goal**: Connect all components in VoiceDockApp.swift and AppDelegate
- **Acceptance Criteria**:
  1. @main VoiceDockApp with NSApplicationDelegateAdaptor
  2. AppDelegate creates NSStatusItem and NSPopover
  3. SessionCoordinator instantiated with dependencies
  4. HotKeyManager registered on launch
  5. Permission checks on first launch
- **Files to Create/Modify**:
  - `VoiceDockApp/VoiceDockApp.swift`
  - `VoiceDockApp/AppDelegate.swift`
- **Dependencies**: 1.9
- **Verification**:
  ```bash
  grep -q "@main" VoiceDockApp/VoiceDockApp.swift && \
  grep -q "NSApplicationDelegateAdaptor" VoiceDockApp/VoiceDockApp.swift && \
  grep -q "NSStatusItem" VoiceDockApp/AppDelegate.swift && \
  echo "WIRING_PASS"
  ```
- **Commit**: `feat(app): wire up all components in App entry point`
- _Requirements: FR-1.1, FR-1.2, AC-1.1, AC-1.2, AC-1.4_
- _Design: File Structure, Implementation Steps 10_

### Task 1.11: Info.plist Permissions Configuration

- **Goal**: Add required permission usage descriptions to Info.plist
- **Acceptance Criteria**:
  1. NSMicrophoneUsageDescription with clear explanation
  2. NSAppleEventsUsageDescription for Accessibility
  3. Explanations mention local processing only
- **Files to Modify**:
  - `VoiceDockApp/Info.plist`
- **Dependencies**: 1.10
- **Verification**:
  ```bash
  plutil -p VoiceDockApp/Info.plist | grep -q "NSMicrophoneUsageDescription" && \
  plutil -p VoiceDockApp/Info.plist | grep -q "NSAppleEventsUsageDescription" && \
  echo "INFOPLIST_PASS"
  ```
- **Commit**: `feat(permissions): add Info.plist usage descriptions`
- _Requirements: FR-2.1, FR-2.2, AC-2.2, AC-3.2, NFR-2.6_
- _Design: File Structure_

### Task 1.12: POC End-to-End Manual Test

- **Goal**: Verify complete PTT flow works on real hardware
- **Acceptance Criteria**:
  1. Application launches without crash
  2. Menu bar icon displays
  3. Hotkey press triggers listening state
  4. Hotkey release triggers transcribing state
  5. Transcript appears in focused application (or clipboard if no Accessibility)
- **Files**: None (manual verification)
- **Dependencies**: 1.11
- **Verification**:
  ```bash
  # Manual test evidence documented in .progress.md
  echo "POC_MANUAL_TEST_REQUIRED"
  echo "Evidence to record:"
  echo "1. Screenshot of menu bar with listening indicator"
  echo "2. Screenshot of transcript pasted into text editor"
  echo "3. Timing measurement: key release to paste complete"
  ```
- **Commit**: `feat(poc): complete push-to-talk MVP end-to-end`
- _Requirements: US-1 through US-10 (all user stories)_
- _Design: Data Flow diagram_

---

## Phase 2: Refactoring

After POC validated, clean up code structure, add error handling, and modularize.

### Task 2.1: Extract Error Types

- **Goal**: Create unified error handling across all components
- **Acceptance Criteria**:
  1. VoiceDockError enum covers all error cases
  2. LocalizedError conformance with errorDescription
  3. Recovery suggestions for each error type
- **Files to Create**:
  - `VoiceDockApp/Errors/VoiceDockError.swift`
- **Dependencies**: 1.12
- **Verification**:
  ```bash
  grep -q "enum VoiceDockError" VoiceDockApp/Errors/VoiceDockError.swift && \
  grep -q "LocalizedError" VoiceDockApp/Errors/VoiceDockError.swift && \
  echo "ERRORS_PASS"
  ```
- **Commit**: `refactor(errors): extract unified VoiceDockError enum`
- _Design: Error Handling Strategy_

### Task 2.2: Add Retry Logic

- **Goal**: Implement retry for model download and transcription failures
- **Acceptance Criteria**:
  1. Retry button in error state UI
  2. ASRProvider.load() retries on network failure
  3. Model download failure shows manual fallback instructions
- **Files to Modify**:
  - `VoiceDockApp/ASR/MLXAudioSTTProvider.swift`
  - `VoiceDockApp/Views/StatusPopover.swift`
  - `VoiceDockApp/Coordinator/SessionCoordinator.swift`
- **Dependencies**: 2.1
- **Verification**:
  ```bash
  grep -q "retry" VoiceDockApp/ASR/MLXAudioSTTProvider.swift && \
  grep -q "Retry" VoiceDockApp/Views/StatusPopover.swift && \
  echo "RETRY_PASS"
  ```
- **Commit**: `refactor(asr): add retry logic for model download and transcription`
- _Requirements: AC-10.7, AC-10.8, AC-10.9_
- _Design: Error Handling Strategy table_

### Task 2.3: Modularize Audio Pipeline

- **Goal**: Separate AudioCapture and AudioNormalizer into distinct modules with clear interfaces
- **Acceptance Criteria**:
  1. AudioCapture exposes only start/stop/cancel/setCallback
  2. AudioNormalizer is pure function (no state)
  3. Clear buffer ownership boundary
- **Files to Modify**:
  - `VoiceDockApp/Audio/AudioCapture.swift`
  - `VoiceDockApp/Audio/AudioNormalizer.swift`
- **Dependencies**: 2.2
- **Verification**:
  ```bash
  grep -q "public func" VoiceDockApp/Audio/AudioCapture.swift && \
  grep -q "struct AudioNormalizer" VoiceDockApp/Audio/AudioNormalizer.swift && \
  echo "AUDIO_MODULAR_PASS"
  ```
- **Commit**: `refactor(audio): clarify AudioCapture/AudioNormalizer boundaries`
- _Design: AudioCapture, AudioNormalizer components_

### Task 2.4: Quality Checkpoint

- **Goal**: Verify code quality after refactoring
- **Acceptance Criteria**:
  1. All components have clear single responsibility
  2. No circular dependencies
  3. Actor isolation boundaries documented
- **Verification**:
  ```bash
  find VoiceDockApp -name "*.swift" -exec grep -l "actor" {} \; | wc -l | grep -q "[1-9]" && \
  echo "REFACTOR_QUALITY_PASS"
  ```
- **Commit**: `chore(refactor): pass quality checkpoint`

---

## Phase 3: Testing

Add unit tests, integration tests, and manual verification.

### Task 3.1: AudioNormalizer Unit Tests

- **Goal**: Test format conversion logic
- **Acceptance Criteria**:
  1. testNormalize_to16kHzMonoFloat32
  2. testEmptyHandling (no crash)
  3. testInterleavedToMono (if applicable)
- **Files to Create**:
  - `VoiceDockTests/Audio/AudioNormalizerTests.swift`
- **Dependencies**: 2.4
- **Verification**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' test 2>&1 | grep -q "AudioNormalizer" && \
  echo "NORMALIZER_TESTS_PASS"
  ```
- **Commit**: `test(audio): add AudioNormalizer unit tests`
- _Design: Testing Strategy - Unit Tests table_

### Task 3.2: TranscriptDestination Unit Tests

- **Goal**: Test clipboard and paste simulation
- **Acceptance Criteria**:
  1. testCopyToClipboard
  2. testEmptyTranscriptError
  3. Mock accessibility permission for paste test
- **Files to Create**:
  - `VoiceDockTests/Delivery/TranscriptDestinationTests.swift`
- **Dependencies**: 3.1
- **Verification**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' test 2>&1 | grep -q "TranscriptDestination" && \
  echo "TRANSCRIPT_TESTS_PASS"
  ```
- **Commit**: `test(delivery): add TranscriptDestination unit tests`
- _Design: Testing Strategy - Unit Tests table_

### Task 3.3: MockASRProvider for Coordinator Tests

- **Goal**: Create mock ASR provider for SessionCoordinator testing
- **Acceptance Criteria**:
  1. StubbedResult configurable
  2. ShouldFailLoad/Warmup/Transcribe flags
  3. Call tracking (loadCalled, transcribeCalled, receivedAudio)
- **Files to Create**:
  - `VoiceDockTests/ASR/MockASRProvider.swift`
- **Dependencies**: 3.2
- **Verification**:
  ```bash
  grep -q "MockASRProvider" VoiceDockTests/ASR/MockASRProvider.swift && \
  grep -q "stubbedResult" VoiceDockTests/ASR/MockASRProvider.swift && \
  echo "MOCKASR_PASS"
  ```
- **Commit**: `test(mock): create MockASRProvider for coordinator tests`
- _Design: Testing Strategy - MockASRProvider_

### Task 3.4: SessionCoordinator Unit Tests

- **Goal**: Test state machine transitions and error handling
- **Acceptance Criteria**:
  1. testStateTransitions (idle → listening → transcribing → delivering → idle)
  2. testCancellation (clears buffer, returns to idle)
  3. testModelLoadFailure (error state)
  4. testEmptyAudioHandling (no crash)
- **Files to Create**:
  - `VoiceDockTests/Coordinator/SessionCoordinatorTests.swift`
- **Dependencies**: 3.3
- **Verification**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' test 2>&1 | grep -q "SessionCoordinator" && \
  echo "COORDINATOR_TESTS_PASS"
  ```
- **Commit**: `test(coordinator): add SessionCoordinator state machine tests`
- _Design: Testing Strategy - Unit Tests table_

### Task 3.5: Manual Verification on M1

- **Goal**: Test real-world performance on baseline hardware
- **Acceptance Criteria**:
  1. English speech transcription works (screenshot evidence)
  2. Mandarin Chinese speech transcription works (screenshot evidence)
  3. Mixed Chinese-English speech transcription works (screenshot evidence)
  4. Hotkey-to-capture latency < 100ms (timing measurement)
  5. Transcription duration for 10s speech < 5 seconds (timing measurement)
  6. Total flow time < 10 seconds (timing measurement)
  7. Memory footprint < 2 GB peak (Instruments measurement)
- **Files**: None (manual verification)
- **Dependencies**: 3.4
- **Verification**:
  ```bash
  echo "MANUAL_M1_TEST_REQUIRED"
  echo "Evidence to record in .progress.md:"
  echo "1. English speech: transcript screenshot"
  echo "2. Mandarin speech: transcript screenshot"
  echo "3. Mixed speech: transcript screenshot"
  echo "4. Latency measurements (key release to paste)"
  echo "5. Memory footprint from Instruments"
  ```
- **Commit**: `test(manual): complete M1 baseline verification`
- _Requirements: NFR-1.1 through NFR-1.7, AC-7.7, AC-7.8, AC-7.9_
- _Design: Manual Verification Checklist_

### Task 3.6: Quality Checkpoint

- **Goal**: Verify all tests pass and coverage is adequate
- **Verification**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' test 2>&1 | tee /tmp/test-result.txt && \
  grep -q "Test Suite 'All tests' passed" /tmp/test-result.txt && \
  echo "TEST_QUALITY_PASS" || echo "TEST_QUALITY_FAIL"
  ```
- **Commit**: `chore(tests): pass test quality checkpoint`

---

## Phase 4: Quality Gates

### Task 4.1: Local Quality Check

- **Goal**: Run all quality checks locally
- **Acceptance Criteria**:
  1. Build succeeds with zero errors
  2. All unit tests pass
  3. No critical warnings
- **Verification**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' clean build test 2>&1 | tee /tmp/build-result.txt && \
  ! grep -q "error:" /tmp/build-result.txt && \
  grep -q "Build Succeeded" /tmp/build-result.txt && \
  echo "LOCAL_QUALITY_PASS"
  ```
- **Commit**: `chore(quality): pass local quality gates`

### Task 4.2: Documentation - DELIVERY_REPORT.md

- **Goal**: Create delivery documentation
- **Acceptance Criteria**:
  1. Setup instructions (Xcode version, SPM dependencies, model download)
  2. Usage instructions (hotkey, permissions, paste behavior)
  3. Architecture overview (component diagram)
  4. Privacy behavior documentation
  5. Known limitations
  6. Manual test evidence references
- **Files to Create**:
  - `DELIVERY_REPORT.md`
- **Dependencies**: 4.1
- **Verification**:
  ```bash
  grep -q "Setup" DELIVERY_REPORT.md && \
  grep -q "Usage" DELIVERY_REPORT.md && \
  grep -q "Architecture" DELIVERY_REPORT.md && \
  grep -q "Privacy" DELIVERY_REPORT.md && \
  echo "DELIVERY_DOC_PASS"
  ```
- **Commit**: `docs(delivery): create DELIVERY_REPORT.md`

### Task 4.3: Documentation - README Updates

- **Goal**: Update project README with VoiceDock-specific information
- **Acceptance Criteria**:
  1. Project description and purpose
  2. Requirements (macOS 14+, arm64, M1 16GB baseline)
  3. Build instructions
  4. Permission requirements
- **Files to Modify**:
  - `README.md`
- **Dependencies**: 4.2
- **Verification**:
  ```bash
  grep -q "VoiceDock" README.md && \
  grep -q "macOS" README.md && \
  grep -q "Push-to-Talk" README.md && \
  echo "README_PASS"
  ```
- **Commit**: `docs(readme): update README for VoiceDock`

---

## Phase 5: VE (E2E Verification)

### Task VE1 [VERIFY] E2E Startup: Build and Launch

- **Do**:
  1. Run clean build: `xcodebuild clean build`
  2. Verify build artifact exists
  3. Launch application in simulator or local environment
- **Verify**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock -destination 'platform=macOS' build 2>&1 | grep -q "Build Succeeded" && \
  echo "VE1_PASS" || echo "VE1_FAIL"
  ```
- **Done when**: Build succeeds and application launches
- **Commit**: None

### Task VE2 [VERIFY] E2E Check: Permission Flow

- **Do**:
  1. Verify Info.plist contains permission descriptions
  2. Check application requests microphone permission
  3. Check application requests Accessibility permission
- **Verify**:
  ```bash
  plutil -p VoiceDockApp/Info.plist | grep -q "NSMicrophoneUsageDescription" && \
  plutil -p VoiceDockApp/Info.plist | grep -q "NSAppleEventsUsageDescription" && \
  echo "VE2_PASS" || echo "VE2_FAIL"
  ```
- **Done when**: Info.plist permissions configured correctly
- **Commit**: None

### Task VE3 [VERIFY] E2E Check: Hotkey Registration

- **Do**:
  1. Verify HotKeyManager uses RegisterEventHotKey
  2. Verify hotkey is registered on application launch
- **Verify**:
  ```bash
  grep -q "RegisterEventHotKey" VoiceDockApp/HotKey/HotKeyManager.swift && \
  echo "VE3_PASS" || echo "VE3_FAIL"
  ```
- **Done when**: Hotkey registration code verified
- **Commit**: None

### Task VE4 [VERIFY] E2E Cleanup

- **Do**:
  1. Clean build artifacts
  2. Verify no temporary files left
- **Verify**:
  ```bash
  xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock clean 2>&1 && \
  echo "VE4_PASS" || echo "VE4_FAIL"
  ```
- **Done when**: Build artifacts cleaned
- **Commit**: None

---

## Phase 6: PR Lifecycle

### Task 6.1: Final Git Review

- **Do**:
  1. Review git diff for completeness
  2. Verify .gitignore excludes DerivedData, models, credentials
  3. Verify all source files are committed
- **Verify**:
  ```bash
  git status && \
  git diff --stat && \
  echo "REVIEW_READY"
  ```
- **Commit**: `chore(git): final review before handoff`

### Task 6.2: VF [VERIFY] Goal Verification

- **Do**:
  1. Read requirements.md acceptance criteria
  2. Verify each AC is satisfied by code inspection or test evidence
  3. Document verification status in .progress.md
- **Verify**:
  ```bash
  # Automated AC checklist verification
  echo "VF_CART_READY"
  echo "Manual M1 verification evidence required for AC-7.7, AC-7.8, AC-7.9"
  ```
- **Done when**: All acceptance criteria verified
- **Commit**: None

---

## Notes

### POC Shortcuts Taken

- No unit tests in Phase 1 (deferred to Phase 3)
- Hardcoded hotkey (Command+Space) without UI for configuration
- No model download retry UI (added in Phase 2)
- Manual M1 verification deferred to Task 3.5
- No Swift 6 strict concurrency checking initially

### Production TODOs

- Swift 6 strict concurrency verification
- Code signing and notarization (if credentials provided)
- Configurable hotkey UI in preferences
- Model download progress indicator refinement
- Memory profiling on M1 16 GB baseline
- Mixed-language transcription quality validation with real samples

### Open Questions (from research.md)

1. Does `GLMASRModel.generate(audio:)` accept raw `[Float]` or require file URL? → Verify at Task 1.4
2. What is exact memory footprint on M1 16 GB? → Measure at Task 3.5
3. Does mlx-audio-swift compile with Swift 6? → Verify at Task 1.1
4. Optimal audio buffer size for latency vs CPU? → Profile at Task 3.5
5. Does Nemotron auto-detect mixed Chinese-English? → Test at Task 3.5

\-\-\-

_Acceptance Criteria referenced: AC-1.1 through AC-10.9, FR-1.1 through FR-7.6, NFR-1.1 through NFR-4.5_
_Designed from: design.md, requirements.md, research.md, AGENTS.md, VOICEDOCK_MASTER_PROMPT.md_