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
/// - `activeModel` is immutable for the lifetime of the app process
/// - `selectedModel` is the saved preference for the *next* launch
/// - `restartRequired` is true when selectedModel != activeModel
///
/// Usage:
/// 1. At app launch, capture the active model through `effectiveModel()`
/// 2. Query `activeModel`, `selectedModel`, `restartRequired` for UI
/// 3. When user changes selection, call `updateSelection(_:)` and refresh UI
@MainActor
public final class ModelStatus: ObservableObject {
    @Published public private(set) var activeModel: ASRModelSelection
    @Published public private(set) var selectedModel: ASRModelSelection
    @Published public private(set) var restartRequired: Bool = false
    @Published public private(set) var availability: [ASRModelSelection: ModelAvailability] = [:]

    private let modelStorage: ModelStorage
    private let stateQueue = DispatchQueue(label: "com.voicedock.ModelStatus.state", attributes: .concurrent)

    /// Initialize and capture the active model for this process lifetime.
    ///
    /// The active model is determined by:
    /// 1. Environment override (VOICEDOCK_ASR_MODEL)
    /// 2. Saved user preference
    /// 3. Quality default (qwen3-1.7b-4bit)
    ///
    /// Once captured, `activeModel` cannot change without app restart.
    public init(storage: ModelStorage? = nil) {
        self.modelStorage = storage ?? ModelStorage()

        // Capture active model at initialization time
        self.activeModel = ASRModelPreferences.effectiveModel()
        self.selectedModel = ASRModelPreferences.load().selectedModel
        self.restartRequired = false  // At launch, selected == active

        logger.info("ModelStatus initialized: activeModel=\(self.activeModel.rawValue), selectedModel=\(self.selectedModel.rawValue)")

        // Refresh availability asynchronously (non-Sendable context)
        Task { [weak self] in
            await self?.refreshAvailability()
        }
    }

    /// Initialize with explicit active and selected models (for testing)
    public init(activeModel: ASRModelSelection, selectedModel: ASRModelSelection, storage: ModelStorage? = nil) {
        self.modelStorage = storage ?? ModelStorage()
        self.activeModel = activeModel
        self.selectedModel = selectedModel
        self.restartRequired = activeModel != selectedModel

        logger.info("ModelStatus initialized (explicit): activeModel=\(self.activeModel.rawValue), selectedModel=\(self.selectedModel.rawValue), restartRequired=\(self.restartRequired)")
    }

    /// Update the selected model preference.
    ///
    /// This saves the preference and updates `restartRequired` flag.
    /// The `activeModel` remains unchanged - only a restart can change it.
    ///
    /// - Parameter newSelection: The new model selection from user
    public func updateSelection(_ newSelection: ASRModelSelection) {
        // Save the selection
        var prefs = ASRModelPreferences.load()
        prefs.selectedModel = newSelection
        prefs.save()

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

    /// Reset to default state (for testing)
    public static func reset() async {
        ASRModelPreferences.reset()
        logger.info("Model preferences reset to defaults")
    }
}