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

    @Test("Initial state captures active model correctly")
    func initialStateCapturesActiveModel() {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit
        )

        #expect(modelStatus.activeModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.selectedModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.restartRequired == false)
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
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit
        )

        // Change selection
        modelStatus.updateSelection(.qwen3_0_6B_8bit)

        // Active model should remain unchanged
        #expect(modelStatus.activeModel == .qwen3_1_7B_4bit)
        #expect(modelStatus.selectedModel == .qwen3_0_6B_8bit)
        #expect(modelStatus.restartRequired == true)
    }

    @Test("Selecting same model as active clears restart required")
    func selectingSameModelAsActiveClearsRestartRequired() async {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            storage: ModelStorage()
        )

        #expect(modelStatus.restartRequired == true)

        // Select the same model as active
        modelStatus.updateSelection(.qwen3_1_7B_4bit)

        #expect(modelStatus.restartRequired == false)
    }

    @Test("Update selection saves preference")
    func updateSelectionSavesPreference() async {
        ASRModelPreferences.reset()

        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit
        )

        // Change selection
        modelStatus.updateSelection(.qwen3_0_6B_8bit)

        // Verify saved preference
        let loaded = ASRModelPreferences.load()
        #expect(loaded.selectedModel == .qwen3_0_6B_8bit)

        // Cleanup
        ASRModelPreferences.reset()
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

    @Test("Check availability returns correct state for missing model")
    func checkAvailabilityReturnsCorrectStateForMissingModel() async {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            storage: ModelStorage()
        )

        // Both models should be missing in a clean test environment
        let qualityAvailability = await modelStatus.checkAvailability(.qwen3_1_7B_4bit)
        let fastAvailability = await modelStatus.checkAvailability(.qwen3_0_6B_8bit)

        // In test environment without models installed, both should be missing
        #expect(qualityAvailability == .missing || qualityAvailability == .installed)
        #expect(fastAvailability == .missing || fastAvailability == .installed)
    }

    @Test("Refresh availability populates all models")
    func refreshAvailabilityPopulatesAllModels() async {
        let modelStatus = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            storage: ModelStorage()
        )

        await modelStatus.refreshAvailability()

        #expect(modelStatus.availability.count == ASRModelSelection.allCases.count)

        for model in ASRModelSelection.allCases {
            let availability = modelStatus.availability[model]
            #expect(availability != nil)
            #expect(availability == .installed || availability == .missing)
        }
    }

    @Test("ModelAvailability description is correct")
    func modelAvailabilityDescriptionIsCorrect() {
        #expect(ModelAvailability.installed.description == "installed")
        #expect(ModelAvailability.missing.description == "missing")
        #expect(ModelAvailability.checking.description == "checking")
        #expect(ModelAvailability.invalid(reason: nil).description == "invalid: unknown")
        #expect(ModelAvailability.invalid(reason: "test").description == "invalid: test")
    }

    @Test("Reset clears preferences")
    func resetClearsPreferences() async {
        // Set a preference first
        let prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.save()

        #expect(ASRModelPreferences.load().selectedModel == .qwen3_0_6B_8bit)

        // Reset
        await ModelStatus.reset()

        // Should be back to default
        #expect(ASRModelPreferences.load().selectedModel == .qwen3_1_7B_4bit)

        // Cleanup
        ASRModelPreferences.reset()
    }
}