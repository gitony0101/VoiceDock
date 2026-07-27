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
/// - `activeModel` is `nil` until a provider has actually been created, then
///   set exactly once from `ASRProviderFactoryResult.selection` via
///   `captureActive(_:)`. No other write path may assign `activeModel`,
///   so the saved preference can never be presented as Active before provider
///   creation, and `activeModel` can never silently fall back to Quality.
/// - `selectedModel` is the saved preference for the *next* launch, loaded
///   through the shared `ASRPreferenceStore`.
/// - `restartRequired` is true when `selectedModel != activeModel` (nil
///   activeModel ⇒ restart not yet meaningful ⇒ false).
/// - Production uses a single shared `ASRPreferenceStore` instance; tests inject
///   isolated UUID suites.
@MainActor
public final class ModelStatus: ObservableObject {
    @Published public private(set) var activeModel: ASRModelSelection?
    @Published public private(set) var selectedModel: ASRModelSelection
    @Published public private(set) var restartRequired: Bool = false
    @Published public private(set) var availability: [ASRModelSelection: ModelAvailability] = [:]

    /// A visible provider-load error for the active selection. Surfaced to the
    /// UI so a Fast load failure is reported rather than silently swallowed
    /// in favor of Quality.
    @Published public private(set) var lastLoadError: String?

    /// The repoID of the descriptor resolved for the active provider. Derived,
    /// not inferred. Empty until `captureActive(_:)`.
    @Published public private(set) var activeDescriptorRepoID: String = ""

    /// True once `captureActive(_:)` has run for this process. Used to refuse
    /// any later call to `captureActive(_:)` (exactly-once enforcement) and to
    /// refuse any other write path that would overwrite `activeModel`.
    /// Starts `false` even when an explicit `activeModel` is passed to the
    /// test initializer — a presenter's stand-in is not equivalent to a real
    /// capture, so the first real `captureActive(_:)` call always wins and
    /// overwrites the stand-in.
    private var activeCaptured: Bool = false

    /// Injectable duplicate-capture assertion hook. Production defaults to
    /// `assertionFailure` (a debug-only trap); tests inject a no-op (or a
    /// recorder) so a second `captureActive(_:)` does not crash the suite but
    /// is still observable through the returned `Bool`.
    public var duplicateCaptureHandler: (String) -> Void = { message in
        assertionFailure(message)
    }

    private let modelStorage: ModelStorage
    public let preferenceStore: ASRPreferenceStore
    /// Injectable per-launch diagnostic recorder. Production composition
    /// passes `ModelLaunchRecorder.shared`; tests pass an independent
    /// `FakeModelLaunchRecorder` (or a temp-dir `ModelLaunchRecorder`) so
    /// `ModelStatus` never mutates the production singleton or writes to the
    /// owner's `~/Library/Application Support/VoiceDock/Diagnostics` file.
    private let recorder: ModelLaunchDiagnosticRecording

    /// Production initializer. Loads `selectedModel` from the shared preference
    /// store. `activeModel` starts `nil` and is set exactly once by
    /// `captureActive(_:)` after the provider is created. The saved preference
    /// is never presented as Active before provider creation.
    public init(
        storage: ModelStorage? = nil,
        preferenceStore: ASRPreferenceStore = .production,
        recorder: ModelLaunchDiagnosticRecording = ModelLaunchRecorder.shared
    ) {
        self.modelStorage = storage ?? ModelStorage()
        self.preferenceStore = preferenceStore
        self.recorder = recorder

        // Record preference-suite provenance before reading.
        let raw = preferenceStore.rawSelectedModelValue()
        self.recorder.recordPreferenceState(
            suiteName: preferenceStore.suiteName,
            rawSelectedModel: raw
        )

        // selectedModel comes from the shared store. activeModel is nil until
        // captureActive — the saved preference must never be presented as the
        // Active model before the provider is actually created.
        self.activeModel = nil
        self.activeDescriptorRepoID = ""
        self.selectedModel = ASRModelPreferences.load(from: preferenceStore).selectedModel
        self.restartRequired = false  // activeModel is nil; not yet meaningful

        // activeModel is nil here, so the "effective before provider" state is
        // notCreated, NOT the saved preference — the saved selection is never
        // reported as a real effective selection before the provider exists.
        self.recorder.recordModelStatusInit(selected: self.selectedModel, effective: nil)

        logger.info("ModelStatus initialized: activeModel=nil (pending provider), selectedModel=\(self.selectedModel.rawValue) suite=\(preferenceStore.suiteName)")

        // Refresh availability asynchronously (non-Sendable context)
        Task { [weak self] in
            await self?.refreshAvailability()
        }
    }

    /// Initialize with an explicit *selected* model and `activeModel = nil`
    /// (the default), simulating the production pre-provider-creation state.
    /// Uses an isolated UUID suite as the preference store so tests never
    /// touch production preferences. Pass a non-nil `activeModel:` to seed a
    /// pre-capture presenter state for tests; that stand-in is NOT treated as
    /// captured — the first real `captureActive(_:)` call always wins and
    /// overwrites it. The recorder parameter has no default: tests that take
    /// this path must pass a `FakeModelLaunchRecorder` (in-memory test fakes
    /// live in the test-support file shared by SwiftPM and Xcode test targets)
    /// or `ModelLaunchRecorder.shared` so the production singleton is never
    /// mutated implicitly.
    public init(
        activeModel: ASRModelSelection? = nil,
        selectedModel: ASRModelSelection,
        storage: ModelStorage? = nil,
        preferenceStore: ASRPreferenceStore? = nil,
        recorder: ModelLaunchDiagnosticRecording
    ) {
        self.modelStorage = storage ?? ModelStorage()
        self.preferenceStore = preferenceStore ?? .isolate()
        self.recorder = recorder
        self.activeModel = activeModel
        self.selectedModel = selectedModel
        // A non-nil activeModel passed here is a test stand-in, not a real
        // capture; restartRequired reflects the stand-in only for display, and
        // activeCaptured stays false so the first captureActive() returns true.
        self.activeDescriptorRepoID = activeModel?.modelDescriptor.repoID ?? ""
        self.restartRequired = (activeModel.map { $0 != selectedModel }) ?? false
        self.activeCaptured = false

        logger.info("ModelStatus initialized (explicit): activeModel=\(self.activeModel?.rawValue ?? "nil") (stand-in), selectedModel=\(self.selectedModel.rawValue), restartRequired=\(self.restartRequired)")
    }

    /// Capture the active model from an `ASRProviderFactoryResult`.
    ///
    /// The active model must always come from the descriptor of the provider
    /// actually created, not from the picker or saved preference. Call this
    /// exactly once during launch, immediately after
    /// `ASRProviderFactory.createProviderWithMetadata()`.
    ///
    /// A second call is a programming error: it is a no-op for state, records
    /// an assertion/diagnostic, and does not mutate `activeModel` or the
    /// descriptor repo ID. Returns `true` on the first call (state assigned)
    /// and `false` on any subsequent call, so deterministic tests can observe
    /// the no-mutation postcondition without an `assertionFailure` trapping
    /// the suite. Production still surfaces a debug trap through the injectable
    /// `duplicateCaptureHandler`.
    @discardableResult
    public func captureActive(_ result: ASRProviderFactoryResult) -> Bool {
        if activeCaptured {
            let msg = "captureActive called more than once: ignoring duplicate; existing activeModel=\(self.activeModel?.rawValue ?? "nil") descriptor=\(self.activeDescriptorRepoID), attempted=\(result.selection.rawValue)"
            logger.error("\(msg, privacy: .public)")
            duplicateCaptureHandler(msg)
            self.recorder.recordDuplicateCaptureActive(
                attemptedSelection: result.selection,
                existingActive: self.activeModel
            )
            return false
        }
        self.activeModel = result.selection
        self.activeDescriptorRepoID = result.descriptor.repoID
        self.restartRequired = (selectedModel != result.selection)
        self.activeCaptured = true
        logger.info("captureActive: activeModel=\(result.selection.rawValue) descriptor=\(result.descriptor.repoID)")
        return true
    }

    /// Update the selected model preference.
    ///
    /// This saves the preference (through the shared store in production) and
    /// updates `restartRequired`. The `activeModel` remains unchanged — only a
    /// restart can change it. Before provider creation (`activeModel == nil`)
    /// `restartRequired` stays false: there is nothing yet to restart away from.
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
        // restartRequired is only meaningful once a provider is active.
        self.restartRequired = (activeModel.map { $0 != newSelection }) ?? false

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
