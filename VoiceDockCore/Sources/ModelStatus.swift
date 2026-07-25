//
//  ModelStatus.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP - Model Selection State Management
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ModelStatus")

/// Model availability state for UI display
public enum ModelAvailability: Equatable, Sendable, CustomStringConvertible {
    case installed
    case missing
    case checking
    case invalid(reason: String?)

    public var description: String {
        switch self {
        case .installed:
            return "installed"
        case .missing:
            return "missing"
        case .checking:
            return "checking"
        case .invalid(reason: let reason):
            return "invalid: \(reason ?? "unknown")"
        }
    }
}

/// Tracks model selection state across app lifetime.
///
/// Key invariants:
/// - `activeModel` is set exactly once from `ASRProviderFactoryResult.selection`
///   via `captureActive(_:)`. No other write path may assign `activeModel`,
///   so it can never silently fall back to Quality.
/// - `selectedModel` is the saved preference for the *next* launch.
/// - `restartRequired` is true when selectedModel != activeModel.
/// - Production uses a single shared `ASRPreferenceStore` instance; tests inject
///   isolated UUID suites.
@MainActor
public final class ModelStatus: ObservableObject {
    @Published public private(set) var activeModel: ASRModelSelection
    @Published public private(set) var selectedModel: ASRModelSelection
    @Published public private(set) var restartRequired: Bool = false
    @Published public private(set) var availability: [ASRModelSelection: ModelAvailability] = [:]

    /// A visible provider-load error for the active selection. Surfaced to the
    /// UI so a Fast load failure is reported rather than silently swallowed
    /// in favor of Quality.
    @Published public private(set) var lastLoadError: String?

    /// The repoID of the descriptor resolved for the active provider. Derived,
    /// not inferred.
    @Published public private(set) var activeDescriptorRepoID: String = ""

    /// True once `captureActive(_:)` has run for this process. Used to refuse
    /// any later write path that would otherwise overwrite `activeModel`.
    private var activeCaptured: Bool = false

    private let modelStorage: ModelStorage
    public let preferenceStore: ASRPreferenceStore

    /// Production initializer. Captures the active model for this process
    /// lifetime from `ASRModelPreferences.effectiveModel(from:)` read through
    /// the shared store; `selectedModel` is read through the same store.
    /// `activeModel` is set here only so it has a defined value before the
    /// provider is created; `captureActive(_:)` re-asserts it from the real
    /// factory result so the final value is never inferred from the picker or
    /// saved preference alone.
    public init(storage: ModelStorage? = nil, preferenceStore: ASRPreferenceStore = .production) {
        self.modelStorage = storage ?? ModelStorage()
        self.preferenceStore = preferenceStore

        // Record preference-suite provenance before reading.
        let raw = preferenceStore.rawSelectedModelValue()
        ModelLaunchRecorder.shared.recordPreferenceState(
            suiteName: preferenceStore.suiteName,
            rawSelectedModel: raw
        )

        let effective = ASRModelPreferences.effectiveModel(from: preferenceStore)
        // Provisional active model — captureActive will overwrite with the
        // real factory result. Mark activeCaptured=false so the overwrite is
        // permitted.
        self.activeModel = effective
        self.activeDescriptorRepoID = effective.modelDescriptor.repoID
        self.selectedModel = ASRModelPreferences.load(from: preferenceStore).selectedModel
        self.restartRequired = false  // At launch, selected == active

        ModelLaunchRecorder.shared.recordModelStatusInit(selected: self.selectedModel, effective: effective)

        logger.info("ModelStatus initialized: activeModel(provisional)=\(self.activeModel.rawValue), selectedModel=\(self.selectedModel.rawValue) suite=\(preferenceStore.suiteName)")

        // Refresh availability asynchronously (non-Sendable context)
        Task { [weak self] in
            await self?.refreshAvailability()
        }
    }

    /// Initialize with explicit active and selected models (legacy/tests).
    /// Uses an isolated UUID suite as the preference store so tests never
    /// touch production preferences.
    public init(activeModel: ASRModelSelection, selectedModel: ASRModelSelection, storage: ModelStorage? = nil, preferenceStore: ASRPreferenceStore? = nil) {
        self.modelStorage = storage ?? ModelStorage()
        self.preferenceStore = preferenceStore ?? .isolate()
        self.activeModel = activeModel
        self.selectedModel = selectedModel
        self.activeDescriptorRepoID = activeModel.modelDescriptor.repoID
        self.restartRequired = activeModel != selectedModel

        logger.info("ModelStatus initialized (explicit): activeModel=\(self.activeModel.rawValue), selectedModel=\(self.selectedModel.rawValue), restartRequired=\(self.restartRequired)")
    }

    /// Capture the active model from an `ASRProviderFactoryResult`.
    ///
    /// The active model must always come from the descriptor of the provider
    /// actually created, not from the picker or saved preference. Call this
    /// once during launch, immediately after
    /// `ASRProviderFactory.createProviderWithMetadata()`.
    public func captureActive(_ result: ASRProviderFactoryResult) {
        // captureActive is the one and only writer of activeModel after init.
        // We do not guard on activeCaptured here (init's provisional assignment
        // must be over-writable); instead we set activeCaptured=true so any
        // later assignment path is refused by setActiveFromFactory guarded
        // with activeCaptured. This method is the single allowed writer.
        self.activeModel = result.selection
        self.activeDescriptorRepoID = result.descriptor.repoID
        self.restartRequired = (selectedModel != result.selection)
        self.activeCaptured = true
        logger.info("captureActive: activeModel=\(result.selection.rawValue) descriptor=\(result.descriptor.repoID)")
    }

    /// Update the selected model preference.
    ///
    /// This saves the preference (through the shared store in production) and
    /// updates `restartRequired`. The `activeModel` remains unchanged — only a
    /// restart can change it.
    ///
    /// - Parameters:
    ///   - newSelection: The new model selection from user
    ///   - defaults: Legacy/test entry point passing a raw UserDefaults instance.
    public func updateSelection(_ newSelection: ASRModelSelection, to defaults: UserDefaults? = nil) {
        if let defaults = defaults {
            // Legacy/test path: write to the supplied isolated defaults.
            var prefs = ASRModelPreferences.load(from: defaults)
            prefs.selectedModel = newSelection
            prefs.save(to: defaults)
        } else {
            // Production path: write through the shared preference store
            // and force a cfprefs synchronization.
            var prefs = ASRModelPreferences.load(from: preferenceStore)
            prefs.selectedModel = newSelection
            prefs.saveAndSynchronize(to: preferenceStore)
        }

        self.selectedModel = newSelection
        self.restartRequired = newSelection != self.activeModel

        logger.info("Model selection updated: selectedModel=\(newSelection.rawValue), restartRequired=\(self.restartRequired)")
    }

    /// Check availability of a specific model asynchronously
    nonisolated public func checkAvailability(_ model: ASRModelSelection) async -> ModelAvailability {
        logger.info("Checking availability for: \(model.rawValue)")

        let descriptor = model.modelDescriptor
        let isValid = await modelStorage.isModelValid(descriptor)

        if isValid {
            return .installed
        } else {
            return .missing
        }
    }

    /// Refresh availability state for all models
    public func refreshAvailability() async {
        logger.info("Refreshing model availability...")

        var newAvailability: [ASRModelSelection: ModelAvailability] = [:]

        for model in ASRModelSelection.allCases {
            let availability = await checkAvailability(model)
            newAvailability[model] = availability
            logger.info("Model \(model.rawValue): \(availability.description)")
        }

        self.availability = newAvailability
    }

    /// Get the availability state for display
    public func availabilityFor(_ model: ASRModelSelection) -> ModelAvailability {
        availability[model] ?? .checking
    }

    /// Record a visible provider-load error for the active selection.
    public func recordLoadError(_ message: String) {
        self.lastLoadError = message
        logger.error("ModelStatus load error: \(message)")
    }

    /// Clear the visible provider-load error.
    public func clearLoadError() {
        self.lastLoadError = nil
    }

    /// Reset to default state (for testing).
    /// Use `reset(to:)` with an isolated `UserDefaults` suite to avoid touching
    /// the owner's production preferences.
    public static func reset() async {
        ASRModelPreferences.reset()
        logger.info("Model preferences reset to defaults")
    }

    /// Reset to default state on an explicit (usually isolated) `UserDefaults`
    /// instance. Use this in tests so production preferences are not affected.
    public static func reset(to defaults: UserDefaults) async {
        ASRModelPreferences.reset(to: defaults)
        logger.info("Model preferences reset to defaults on explicit defaults")
    }
}
