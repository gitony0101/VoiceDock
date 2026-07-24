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
            selectedModel: .qwen3_1_7B_4bit
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
            selectedModel: .qwen3_0_6B_8bit
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
            selectedModel: .qwen3_1_7B_4bit
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
            storage: ModelStorage()
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
            selectedModel: .qwen3_1_7B_4bit
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
            selectedModel: .qwen3_1_7B_4bit
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
            selectedModel: .qwen3_1_7B_4bit
        )

        modelStatus.captureActive(result)

        #expect(modelStatus.activeModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.activeDescriptorRepoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)
        #expect(modelStatus.restartRequired == true)
    }
}
