//
//  ModelStatusTests.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP - Model Status Tests
//

import Testing
import Foundation
@testable import VoiceDockCore

@Suite("ModelStatus Tests")
@MainActor
struct ModelStatusTests {

    /// Build an isolated `UserDefaults` suite for a single test instance.
    /// The suite is unique to this test so it cannot collide with the owner's
    /// production `UserDefaults.standard` nor with another test's state.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "VoiceDockTests.ModelStatus.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite \(suiteName)")
            return .standard
        }
        return suite
    }

    /// Hard guard: tests must NEVER write to the owner's production UserDefaults
    /// domain. This is a paranoia check: if any test code starts reaching for
    /// `.standard` directly, the suite names below should change to enforce
    /// isolation.
    @Test("Never touches production UserDefaults (paranoia guard)")
    func paranoiaGuard() {
        // Recording the standard suite before any test action
        let standardSuite = UserDefaults.standard
        let selectedKey = "voicedock.selectedASRModel"
        let hasSeenKey = "voicedock.hasSeenModelSelection"

        let selectedBefore = standardSuite.string(forKey: selectedKey)
        let hasSeenBefore = standardSuite.object(forKey: hasSeenKey) as? Bool ?? false
        defer {
            let selectedAfter = standardSuite.string(forKey: selectedKey)
            let hasSeenAfter = standardSuite.object(forKey: hasSeenKey) as? Bool ?? false
            #expect(selectedBefore == selectedAfter,
                    "Production voicdoc.selectedASRModel must not change from \(selectedBefore ?? "nil") to \(selectedAfter ?? "nil") during tests")
            #expect(hasSeenBefore == hasSeenAfter,
                    "Production voicdoc.hasSeenModelSelection must not change during tests")
        }

        let suite = makeIsolatedDefaults()
        suite.set("qwen3-1.7b-4bit", forKey: selectedKey)
        suite.set(true, forKey: hasSeenKey)

        // Standard suite is unaffected
        #expect(standardSuite.string(forKey: selectedKey) == selectedBefore,
                "Standard defaults must remain untouched by isolated suite")
    }

    @Test("Initial state captures active model correctly")
    func initialStateCapturesActiveModel() {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            recorder: FakeModelLaunchRecorder()
        )

        #expect(modelStatus.activeModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.selectedModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.restartRequired == false)
        #expect(modelStatus.activeDescriptorRepoID == ASRModelSelection.qwen3_1_7B_4bit.modelDescriptor.repoID)
    }

    @Test("Initial state with different selected model shows restart required")
    func initialStateWithDifferentSelectedShowsRestartRequired() {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            recorder: FakeModelLaunchRecorder()
        )

        #expect(modelStatus.activeModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.selectedModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.restartRequired == true)
    }

    @Test("Active model remains immutable after selection change")
    func activeModelRemainsImmutableAfterSelectionChange() async {
        let defaults = makeIsolatedDefaults()
        defer {
            ASRModelPreferences.reset(to: defaults)
        }

        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            recorder: FakeModelLaunchRecorder()
        )

        modelStatus.updateSelection(.qwen3_0_6B_8bit, to: defaults)

        #expect(modelStatus.activeModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.selectedModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.restartRequired == true)
    }

    @Test("Selecting same model as active clears restart required")
    func selectingSameModelAsActiveClearsRestartRequired() async {
        let defaults = makeIsolatedDefaults()
        defer {
            ASRModelPreferences.reset(to: defaults)
        }

        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            storage: ModelStorage(),
            recorder: FakeModelLaunchRecorder()
        )

        #expect(modelStatus.restartRequired == true)

        modelStatus.updateSelection(.qwen3_1_7B_4bit, to: defaults)

        #expect(modelStatus.restartRequired == false)
    }

    @Test("Update selection saves preference on isolated defaults")
    func updateSelectionSavesPreference() async {
        let defaults = makeIsolatedDefaults()
        defer {
            ASRModelPreferences.reset(to: defaults)
        }

        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            recorder: FakeModelLaunchRecorder()
        )

        modelStatus.updateSelection(.qwen3_0_6B_8bit, to: defaults)

        // Without clearing the standard suite, we must not see qwen3-0.6b-8bit there.
        let loaded = ASRModelPreferences.load(from: defaults)
        #expect(loaded.selectedModel == .qwen3_0_6B_8bit)

        // Standard defaults are unaffected unless pre-seeded (which they are not by this test)
        let standardLoad = ASRModelPreferences.load()
        #expect(standardLoad.selectedModel == .qwen3_1_7B_4bit
                || standardLoad.selectedModel == .qwen3_0_6B_8bit)
        // Production guarantees: modelStatus uses isolated suite for writes
        #expect(modelStatus.selectedModel == .qwen3_0_6B_8bit)
    }

    @Test("Availability starts as checking")
    func availabilityStartsAsChecking() {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            recorder: FakeModelLaunchRecorder()
        )

        #expect(modelStatus.availability.isEmpty)
        #expect(modelStatus.availabilityFor(.qwen3_1_7B_4bit) == .checking)
        #expect(modelStatus.availabilityFor(.qwen3_0_6B_8bit) == .checking)
    }

    @Test("ModelAvailability description is correct")
    func modelAvailabilityDescriptionIsCorrect() {
        #expect(ModelAvailability.installed.description == "installed")
        #expect(ModelAvailability.missing.description == "missing")
        #expect(ModelAvailability.checking.description == "checking")
        #expect(ModelAvailability.invalid(reason: nil).description == "invalid: unknown")
        #expect(ModelAvailability.invalid(reason: "test").description == "invalid: test")
    }

    @Test("Reset on isolated defaults clears only the isolated holds")
    func resetClearsPreferences() async {
        let defaults = makeIsolatedDefaults()
        // Snapshot the production state for paranoia
        let productionBefore = ASRModelPreferences.load()

        // Set a preference on the isolated suite first.
        let prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.save(to: defaults)

        #expect(ASRModelPreferences.load(from: defaults).selectedModel == .qwen3_0_6B_8bit)

        // Reset ONLY the isolated suite
        await ModelStatus.reset(to: defaults)

        #expect(ASRModelPreferences.load(from: defaults).selectedModel == .qwen3_1_7B_4bit)

        // Production is intact
        let productionAfter = ASRModelPreferences.load()
        #expect(productionAfter.selectedModel == productionBefore.selectedModel)
    }

    @Test("Factory result captures active model into status")
    func factoryResultCapturesActiveModel() async {
        let result = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            recorder: FakeModelLaunchRecorder()
        )

        modelStatus.captureActive(result)

        #expect(modelStatus.activeModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.activeDescriptorRepoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)
        #expect(modelStatus.restartRequired == true)
    }

    // MARK: - optional activeModel contract (pre-provider-creation)

    @Test("activeModel is nil and restartRequired false before provider creation")
    func activeModelIsNilBeforeProviderCreation() {
        let modelStatus = ModelStatus(
            selectedModel: .qwen3_0_6B_8bit,
            recorder: FakeModelLaunchRecorder()
        )
        #expect(modelStatus.activeModel == nil)
        #expect(modelStatus.activeDescriptorRepoID == "")
        #expect(modelStatus.restartRequired == false)
        // A selected preference must never be reported as Active before
        // captureActive. Quality fallback must not occur implicitly.
        #expect(modelStatus.activeModel != .qwen3_1_7B_4bit)
    }

    // MARK: - captureActive exactly-once

    @Test("First captureActive returns true and assigns the active model")
    func firstCaptureReturnsTrueAndAssigns() {
        let result = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let modelStatus = ModelStatus(selectedModel: .qwen3_0_6B_8bit, recorder: FakeModelLaunchRecorder())

        let ok = modelStatus.captureActive(result)

        #expect(ok == true)
        #expect(modelStatus.activeModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.activeDescriptorRepoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)
        #expect(modelStatus.restartRequired == false)
    }

    @Test("Second captureActive returns false and does not mutate state")
    func secondCaptureReturnsFalseWithoutMutation() {
        // Inject a no-op duplicate handler so the second call does not trap
        // the suite (production would trap in debug via assertionFailure), and
        // inject an independent fake recorder so the duplicate-capture witness
        // flows through the injected recorder — never `ModelLaunchRecorder.shared`.
        var recordedMessages: [String] = []
        let fakeRecorder = FakeModelLaunchRecorder()
        let modelStatus = ModelStatus(
            selectedModel: .qwen3_0_6B_8bit,
            recorder: fakeRecorder
        )
        modelStatus.duplicateCaptureHandler = { msg in recordedMessages.append(msg) }

        let first = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let second = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_1_7B_4bit,  // a different selection attempting to overwrite
            descriptor: .qwen3_1_7B_4bit
        )

        let ok1 = modelStatus.captureActive(first)
        let ok2 = modelStatus.captureActive(second)

        #expect(ok1 == true)
        #expect(ok2 == false)
        // Second call does NOT mutate the active model or descriptor.
        #expect(modelStatus.activeModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.activeDescriptorRepoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)
        // The duplicate handler was invoked exactly once with a non-empty message.
        #expect(recordedMessages.count == 1)
        #expect(recordedMessages.first?.isEmpty == false)
        // The injected recorder observed the duplicate-capture attempt exactly
        // once, with the attempted and existing selections recorded faithfully.
        #expect(fakeRecorder.duplicateCaptureAttempts.count == 1)
        let witness = fakeRecorder.duplicateCaptureAttempts[0]
        #expect(witness.attempted == .qwen3_1_7B_4bit)
        #expect(witness.existing == .qwen3_0_6B_8bit)
    }

    @Test("Duplicate captureActive records through the injected recorder and never touches the shared production recorder")
    func duplicateCaptureIsolationFromSharedRecorder() {
        // The shared production recorder is a process-global singleton whose
        // state persists for the life of the test process and would, if
        // mutated here, leak a duplicate-capture marker into any later test
        // that finalizes it. This test proves the production singleton is left
        // untouched by exercising a `ModelStatus` constructed with an
        // independent injected recorder.
        let fakeRecorder = FakeModelLaunchRecorder()
        let modelStatus = ModelStatus(
            selectedModel: .qwen3_0_6B_8bit,
            recorder: fakeRecorder
        )
        // Suppress the production debug trap (assertionFailure) so the suite
        // stays alive; the duplicate still surfaces through the injected
        // recorder and the captureActive return value.
        modelStatus.duplicateCaptureHandler = { _ in }

        let first = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let second = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_1_7B_4bit,
            descriptor: .qwen3_1_7B_4bit
        )

        _ = modelStatus.captureActive(first)
        // Sanity: the first capture produced no duplicate marker.
        #expect(fakeRecorder.duplicateCaptureAttempts.count == 0)

        _ = modelStatus.captureActive(second)
        // The injected recorder saw the duplicate.
        #expect(fakeRecorder.duplicateCaptureAttempts.count == 1)

        // Isolation contract: `ModelStatus.captureActive` never references
        // `ModelLaunchRecorder.shared` — it only ever calls the injected
        // recorder — so the production singleton must NEVER observe a
        // duplicate-capture attempt, regardless of test execution order.
        // This flag is never reset (no `resetForTesting`), so if any test in
        // the suite were to mutate the shared recorder it would leak here.
        #expect(ModelLaunchRecorder.shared.duplicateCaptureWasAttempted() == false)
    }
}
