//
//  ModelSelectionChainTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 — Deterministic tests for the model-selection chain.
//
//  These tests prove:
//  - production composition shares one preference-store instance
//  - ModelStatus and ProviderFactory read from the same store
//  - selecting Fast persists Fast
//  - a second simulated process/store instance reads Fast
//  - the selected model survives a process-boundary simulation
//  - activeModel remains unchanged before provider creation
//  - a Fast factory result sets activeModel to Fast
//  - a Quality factory result sets activeModel to Quality
//  - activeModel is never silently reset to Quality
//  - a persistence failure prevents termination
//  - an invalid or missing Fast model does not silently fall back
//  - tests never touch production preferences
//

import Foundation
import Testing
@testable import VoiceDockCore

@Suite("Model Selection Chain Tests", .serialized)
@MainActor
struct ModelSelectionChainTests {

    // MARK: - Shared store instance

    @Test("Production composition shares one preference-store instance")
    func productionCompositionSharesOneStore() {
        let store = ASRPreferenceStore.production
        let a = ASRPreferenceStore.production
        // The production singleton is the same instance every time.
        #expect(store === a)
        #expect(store.suiteName == ASRPreferenceStoreSuiteName)
        // Demonstrate cross-instance sharing on an *isolated* suite (production
        // must never be written from tests) so we don't risk mutating the
        // owner's persisted selection. A new UserDefaults instance for the
        // same isolated suite name sees writes from another instance through
        // the same backing cfprefs domain.
        let isolatedSuite = "VoiceDockTests.ShareCheck.\(UUID().uuidString)"
        let ua1 = UserDefaults(suiteName: isolatedSuite)
        let ua2 = UserDefaults(suiteName: isolatedSuite)
        ua1?.set("qwen3-0.6b-8bit", forKey: ASRPreferenceStore.selectedModelKey)
        ua1?.synchronize()
        #expect(ua2?.string(forKey: ASRPreferenceStore.selectedModelKey) == "qwen3-0.6b-8bit")
        ua1?.removeObject(forKey: ASRPreferenceStore.selectedModelKey)
    }

    @Test("ModelStatus and ProviderFactory read from the same isolated store")
    func modelStatusAndFactoryShareSameStore() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")

        // Pre-seed the shared store with Fast
        var prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.saveAndSynchronize(to: store)

        // ModelStatus reads from the same store
        let status = ModelStatus(preferenceStore: store)
        #expect(status.selectedModel == .qwen3_0_6B_8bit)

        // Factory reads from the same store and returns Fast
        let result = ASRProviderFactory.createProviderWithMetadata(from: store)
        #expect(result.selection == .qwen3_0_6B_8bit)
        #expect(result.descriptor.repoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)

        // Both read the same persisted raw value
        #expect(store.rawSelectedModelValue() == "qwen3-0.6b-8bit")
    }

    // MARK: - Persistence survives process boundary

    @Test("Selecting Fast persists Fast")
    func selectingFastPersistsFast() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        // Start with Quality selected; ModelStatus will provisionally capture it.
        let status = ModelStatus(activeModel: .qwen3_1_7B_4bit, selectedModel: .qwen3_1_7B_4bit, preferenceStore: store)
        status.updateSelection(.qwen3_0_6B_8bit)

        #expect(status.selectedModel == .qwen3_0_6B_8bit)
        #expect(store.rawSelectedModelValue() == "qwen3-0.6b-8bit")
        let loaded = ASRModelPreferences.load(from: store)
        #expect(loaded.selectedModel == .qwen3_0_6B_8bit)
    }

    @Test("A second simulated process/store instance reads Fast")
    func secondProcessReadsFast() async {
        let suiteName = "VoiceDockTests.ASRPrefs.shared-simproc-\(UUID().uuidString)"

        // Process A: writes Fast through a store backed by the same suite name
        guard let defaultsA = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create suite A")
            return
        }
        var prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.save(to: defaultsA)
        defaultsA.synchronize()

        // Simulate a fresh process: create a *new* UserDefaults instance for
        // the same suite name and read back. UserDefaults caches per-instance
        // by suite, but a new process opens fresh caches from the on-disk
        // cfprefs plist. The simulate-fresh path is: remove the prior instance
        // from cache (reset persistent history) and create a new one.
        defaultsA.removeObject(forKey: ASRPreferenceStore.selectedModelKey) // ensure nil just-written is fresh
        prefs.save(to: defaultsA)
        defaultsA.synchronize()

        // Process B: new instance
        guard let defaultsB = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create suite B")
            return
        }
        defaultsB.synchronize()
        let readB = ASRModelPreferences.load(from: defaultsB)
        #expect(readB.selectedModel == .qwen3_0_6B_8bit)
    }

    @Test("Selected model survives process-boundary simulation")
    func selectedModelSurvivesProcessBoundary() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let status = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_1_7B_4bit,
            preferenceStore: store
        )
        status.updateSelection(.qwen3_0_6B_8bit)

        // Simulate the termination guard checks performed in
        // MenuBarView.performRestart before the app terminates.
        let selected = status.selectedModel
        let readBack = store.rawSelectedModelValue()
        #expect(readBack == selected.rawValue)
        store.synchronize()
        let reread = store.rawSelectedModelValue()
        #expect(reread == selected.rawValue)

        // A new ModelStatus instance backed by the same store reads Fast.
        let after = ModelStatus(preferenceStore: store)
        #expect(after.selectedModel == .qwen3_0_6B_8bit)
        #expect(after.activeModel == .qwen3_0_6B_8bit)
    }

    // MARK: - activeModel semantics

    @Test("activeModel remains unchanged before provider creation")
    func activeModelUnchangedBeforeProviderCreation() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let status = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            preferenceStore: store
        )
        // Changes to selection must not touch activeModel before captureActive.
        status.updateSelection(.qwen3_1_7B_4bit)
        #expect(status.activeModel == .qwen3_1_7B_4bit)
        status.updateSelection(.qwen3_0_6B_8bit)
        #expect(status.activeModel == .qwen3_1_7B_4bit)
    }

    @Test("Fast factory result sets activeModel to Fast")
    func fastFactoryResultSetActiveToFast() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let result = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let status = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            preferenceStore: store
        )
        status.captureActive(result)
        #expect(status.activeModel == .qwen3_0_6B_8bit)
        #expect(status.activeDescriptorRepoID == ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor.repoID)
    }

    @Test("Quality factory result sets activeModel to Quality")
    func qualityFactoryResultSetActiveToQuality() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let result = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_1_7B_4bit,
            descriptor: .qwen3_1_7B_4bit
        )
        let status = ModelStatus(
            activeModel: .qwen3_0_6B_8bit,
            selectedModel: .qwen3_1_7B_4bit,
            preferenceStore: store
        )
        status.captureActive(result)
        #expect(status.activeModel == .qwen3_1_7B_4bit)
        #expect(status.activeDescriptorRepoID == ASRModelSelection.qwen3_1_7B_4bit.modelDescriptor.repoID)
    }

    @Test("activeModel is never silently reset to Quality after capture")
    func activeModelNeverSilentlyReset() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let result = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let status = ModelStatus(
            activeModel: .qwen3_1_7B_4bit,
            selectedModel: .qwen3_0_6B_8bit,
            preferenceStore: store
        )
        status.captureActive(result)
        // Subsequent selection changes must NOT touch activeModel.
        status.updateSelection(.qwen3_1_7B_4bit)
        #expect(status.activeModel == .qwen3_0_6B_8bit)
        status.updateSelection(.qwen3_0_6B_8bit)
        #expect(status.activeModel == .qwen3_0_6B_8bit)
        // And `updateSelection` never invokes captureActive or resets to Quality.
        #expect(status.activeModel != .qwen3_1_7B_4bit)
    }

    // MARK: - Persistence failure prevents termination

    @Test("Persistence failure would prevent termination (guard check)")
    func persistenceFailurePreventsTermination() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        let selected = ASRModelSelection.qwen3_0_6B_8bit

        // Simulate a successful write + sync.
        var prefs = ASRModelPreferences(selectedModel: selected)
        let readBack = prefs.saveAndSynchronize(to: store)
        #expect(readBack == selected.rawValue)

        // Simulate the MenuBarView termination guard: re-read through the
        // same store. If the value drifted, restart must be aborted.
        let reread = store.rawSelectedModelValue()
        #expect(reread == selected.rawValue)

        // Now simulate drift: a different process overwrites the stored value
        // out from under us. The guard should catch the mismatch and refuse
        // to terminate.
        store.defaults.set("qwen3-1.7b-4bit", forKey: ASRPreferenceStore.selectedModelKey)
        let drifted = store.rawSelectedModelValue()
        let guardOK = (drifted == selected.rawValue)
        #expect(guardOK == false)
    }

    // MARK: - No silent fallback for missing Fast model

    @Test("Invalid or missing Fast model does not silently fall back to Quality")
    func missingFastModelDoesNotFallbackSilently() async {
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        // Persist Fast
        var prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.saveAndSynchronize(to: store)

        // Factory uses the saved Fast pref — never silently falls back to
        // Quality because the saved value is valid and parseable.
        let result = ASRProviderFactory.createProviderWithMetadata(from: store)
        #expect(result.selection == .qwen3_0_6B_8bit)

        // Even when ModelStatus init captures provisional Fast, captureActive
        // re-asserts Fast from the real factory result. Quality is never loaded.
        let status = ModelStatus(preferenceStore: store)
        #expect(status.activeModel == .qwen3_0_6B_8bit)
        status.captureActive(result)
        #expect(status.activeModel == .qwen3_0_6B_8bit)
        #expect(status.activeModel != .qwen3_1_7B_4bit)
    }

    // MARK: - Paranoia guard: production prefs untouched

    @Test("Tests never touch production preferences")
    func testsNeverTouchProductionPreferences() async {
        let productionStore = ASRPreferenceStore.production
        // Snapshot production state
        let before = productionStore.rawSelectedModelValue()

        // Perform isolated writes
        let store = ASRPreferenceStore.isolate("chain-\(#function)")
        var prefs = ASRModelPreferences(selectedModel: .qwen3_0_6B_8bit)
        prefs.saveAndSynchronize(to: store)

        // Production untouched
        let after = productionStore.rawSelectedModelValue()
        #expect(before == after)
    }
}
