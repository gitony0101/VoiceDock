//
//  VoiceDockSetupPresentation.swift
//  VoiceDock
//
//  VoiceDock 0.4.4c1 — Pure setup / readiness presentation model.
//
//  The presentation-truth for the future persistent Setup UI. This type maps
//  already-resolved *value states* (selected model, its validity, acquisition
//  state, coordinator state, microphone status, Accessibility trust, hotkey
//  registration) into a single derived presentation: per-leg row states, action
//  semantics, and one strict overall readiness.
//
//  It is a PURE, value-semantic, side-effect-free mapping. It deliberately does
//  NOT:
//
//    - own tasks, ModelStorage, or SessionCoordinator
//    - read the filesystem, UserDefaults, or any preference store
//    - subscribe to publishers or create AppKit objects
//    - request permissions, download models, register hotkeys
//    - mutate any source of truth
//
//  0.4.4c2 will wire the action enums produced here to the existing owners
//  (ModelAcquisitionController, PermissionManager, HotKeyManager, etc.). This
//  slice establishes only the pure mapping so the UI can render from a stable,
//  deterministic, tested surface.

import Foundation

/// UI-relevant action semantics computed by the presentation model.
///
/// These are ENUM VALUES ONLY — no closures, no side effects. 0.4.4c2 maps each
/// case onto an existing owner's method. `none` means no safe recovery action
/// belongs in this pure layer for the given state (e.g. requires restart).
public enum VoiceDockSetupAction: String, Sendable, Equatable, CaseIterable {
    case downloadSelectedModel
    case cancelModelDownload
    case retryModelDownload
    case allowMicrophone
    case openMicrophoneSettings
    case grantOrOpenAccessibility
    case useFast
    case retryHotkey
    case none
}

/// The completeness of a single readiness leg, plus the action semantics that
/// can advance it. Pure and Equatable.
public enum VoiceDockSetupRowState: Sendable, Equatable {
    /// The leg is satisfied. No action required.
    case complete
    /// The leg is not yet satisfied. Carries the action semantic the future UI
    /// will wire, and a stable, user-facing status string.
    case incomplete(status: String, action: VoiceDockSetupAction)

    /// Whether the leg is satisfied.
    public var isComplete: Bool {
        switch self {
        case .complete: return true
        case .incomplete: return false
        }
    }

    /// The action semantic, if any, the UI should present.
    public var action: VoiceDockSetupAction {
        switch self {
        case .complete: return .none
        case .incomplete(_, let action): return action
        }
    }

    /// A stable, human-readable status, empty when complete.
    public var status: String {
        switch self {
        case .complete: return ""
        case .incomplete(let status, _): return status
        }
    }
}

/// The microphone semantic state, as already resolved by the caller from the
/// OS authorization status.
public enum VoiceDockMicrophoneState: Sendable, Equatable {
    case notDetermined
    case denied
    case granted
}

/// The overall presentation: every leg, action surfaced per leg, and one strict
/// readiness derived from the four mandatory legs.
///
/// VoiceDock Ready is a strict conjunction over exactly:
///   - speech runtime
///   - microphone
///   - Accessibility
///   - hotkey
///
/// Quality is optional: it participates only through the *selected* model row
/// and never affects readiness on its own.
public struct VoiceDockSetupPresentation: Sendable, Equatable {

    // MARK: - Row presentations

    /// The speech-model setup row (about the CURRENT SELECTED model).
    public let speechModel: VoiceDockSetupRowState

    /// The microphone setup row.
    public let microphone: VoiceDockSetupRowState

    /// The Accessibility setup row.
    public let accessibility: VoiceDockSetupRowState

    /// The hotkey setup row.
    public let hotkey: VoiceDockSetupRowState

    /// Compact header / setup status, derived from the four legs.
    public let header: VoiceDockHeader

    /// The strict overall readiness: true ONLY when all four mandatory legs
    /// are complete. This is the single source of "is the app ready".
    public let readiness: VoiceDockReadiness

    /// Convenience: `readiness.isReady`.
    public var isReady: Bool { readiness.isReady }

    /// Maps already-resolved input truths into the pure presentation.
    ///
    /// All parameters are values the caller has already resolved from its own
    /// authoritative sources (ModelStatus, coordinator, PermissionManager,
    /// hotkey observable). This type fetches nothing and triggers nothing.
    ///
    /// - Parameters:
    ///   - selectedModel: The currently selected model (saved preference for
    ///     the next launch; Fast on a clean install, or Quality if persisted).
    ///   - selectedModelValid: Whether the selected model is validly installed.
    ///   - selectedModelAcquisition: The acquisition/install state for the
    ///     selected model (drives Downloading / Retry / Cancel semantics).
    ///   - coordinatorState: The active session coordinator state, used ONLY
    ///     to derive speech-runtime readiness (`.ready` vs anything else).
    ///   - microphone: The already-resolved microphone semantic state.
    ///   - accessibilityTrusted: Whether the app is trusted for Accessibility.
    ///   - hotkeyRegistration: The already-resolved hotkey registration state.
    public init(
        selectedModel: ASRModelSelection,
        selectedModelValid: Bool,
        selectedModelAcquisition: ModelAcquisitionState,
        coordinatorState: SessionCoordinator.State,
        microphone: VoiceDockMicrophoneState,
        accessibilityTrusted: Bool,
        hotkeyRegistration: HotKeyRegistrationState
    ) {
        // Speech runtime readiness is the established invariant:
        //   selectedModelValid AND coordinator.state is operational for setup
        //
        // "Operational for setup" means the runtime has genuinely left admission
        // and is listening, transcribing, or delivering — not merely that a model
        // is selected/active. The currently selected model is the required model:
        // Fast on a clean install, or Quality when the persisted selection is
        // Quality, until selection changes.
        //
        // A persistent Setup UI must NOT regress to "Setup Required" while the
        // user is actively speaking; admission states (starting / waiting /
        // loading / cleaning / idle) and `.failed` stay non-operational.
        let speechRuntimeReady =
            selectedModelValid && Self.isOperationalForSetup(coordinatorState)

        self.readiness = VoiceDockReadiness(
            speechRuntimeReady: speechRuntimeReady,
            microphoneReady: microphone == .granted,
            accessibilityReady: accessibilityTrusted,
            hotkeyReady: hotkeyRegistration == .registered
        )

        self.speechModel = Self.presentSpeechModel(
            selectedModel: selectedModel,
            selectedModelValid: selectedModelValid,
            acquisition: selectedModelAcquisition,
            coordinatorState: coordinatorState
        )

        self.microphone = Self.presentMicrophone(microphone)

        self.accessibility = Self.presentAccessibility(accessibilityTrusted)

        self.hotkey = Self.presentHotkey(
            accessibilityTrusted: accessibilityTrusted,
            hotkeyRegistration: hotkeyRegistration
        )

        self.header = VoiceDockHeader(
            isReady: self.readiness.isReady,
            hasRuntimeFailure: {
                switch coordinatorState {
                case .failed: return true
                default: return false
                }
            }()
        )
    }

    // MARK: - Speech model row (M1–M8)

    /// Whether a given coordinator state means the speech runtime is
    /// operationally live for setup completeness. The active speech states
    /// (`.ready`, `.listening`, `.transcribing`, `.delivering`) qualify; every
    /// admission / teardown / failure state does not.
    ///
    /// This is the single semantic used for both the speech-runtime leg and the
    /// speech-model row, so the two can never drift apart.
    private static func isOperationalForSetup(_ state: SessionCoordinator.State) -> Bool {
        switch state {
        case .ready, .listening, .transcribing, .delivering:
            return true
        case .starting,
             .waitingForMicrophonePermission,
             .waitingForAccessibilityPermission,
             .loadingModel,
             .failed,
             .cleaningUp,
             .idle:
            return false
        }
    }

    private static func presentSpeechModel(
        selectedModel: ASRModelSelection,
        selectedModelValid: Bool,
        acquisition: ModelAcquisitionState,
        coordinatorState: SessionCoordinator.State
    ) -> VoiceDockSetupRowState {
        // When the selected model is validly installed, acquisition state is
        // secondary; the runtime / coordinator state decides completeness.
        if selectedModelValid {
            if Self.isOperationalForSetup(coordinatorState) {
                // M6: installed + operational (ready/listening/transcribing/
                // delivering) → complete.
                return .complete
            }
            if case .failed = coordinatorState {
                // M5: installed + failed → runtime error, restart required.
                return .incomplete(status: Self.modelName(selectedModel) + " runtime error", action: .none)
            }
            // M4: installed + coordinator non-operational (starting/loading/
            // waiting/cleaning/idle) → Loading.
            return .incomplete(status: "Loading " + Self.modelName(selectedModel), action: .none)
        }

        // Selected model is NOT validly installed.
        switch acquisition {
        case .downloading:
            // M2: downloading → progress + Cancel.
            return .incomplete(status: "Downloading " + Self.modelName(selectedModel), action: .cancelModelDownload)
        case .failed:
            // M3: download failed → Retry.
            return .incomplete(status: Self.modelName(selectedModel) + " download failed", action: .retryModelDownload)
        case .idle, .checking, .installed:
            // M1/M8: missing (and M8: Quality selected but missing).
            // If Quality is selected but missing AND Fast is the other model,
            // surface "Use Fast" as an alternative recovery action.
            // NOTE: The pure presentation layer doesn't know Fast's install state.
            // The UI layer will refine this based on authoritative ModelStatus validity.
            if selectedModel == .qwen3_1_7B_4bit {
                // Quality selected but not validly installed.
                // Return a special state that UI can refine to "Use Fast" if Fast is installed.
                return .incomplete(status: "Quality not installed", action: .useFast)
            }
            // Fast selected or other → Download.
            return .incomplete(status: Self.modelName(selectedModel) + " not installed", action: .downloadSelectedModel)
        }
    }

    // MARK: - Microphone row (MIC1–MIC3)

    private static func presentMicrophone(_ microphone: VoiceDockMicrophoneState) -> VoiceDockSetupRowState {
        switch microphone {
        case .granted:
            return .complete
        case .notDetermined:
            return .incomplete(status: "Microphone permission required", action: .allowMicrophone)
        case .denied:
            return .incomplete(status: "Microphone access denied", action: .openMicrophoneSettings)
        }
    }

    // MARK: - Accessibility row (AX1–AX2)

    private static func presentAccessibility(_ trusted: Bool) -> VoiceDockSetupRowState {
        if trusted {
            return .complete
        }
        return .incomplete(status: "Accessibility permission required", action: .grantOrOpenAccessibility)
    }

    // MARK: - Hotkey row (HK1–HK4)

    private static func presentHotkey(
        accessibilityTrusted: Bool,
        hotkeyRegistration: HotKeyRegistrationState
    ) -> VoiceDockSetupRowState {
        // Never infer hotkey registration from Accessibility: the two are
        // independent truths. AX being false is a *precondition* signal but does
        // not substitute for (or imply) registration state.
        switch hotkeyRegistration {
        case .registered:
            // HK3: AX true + registered → complete. (Registration implies AX.)
            return .complete
        case .notRegistered:
            if !accessibilityTrusted {
                // HK1: AX false + notRegistered → waiting for Accessibility.
                return .incomplete(status: "Waiting for Accessibility", action: .grantOrOpenAccessibility)
            }
            // HK2: AX true + notRegistered → genuinely not registered.
            return .incomplete(status: "Hotkey not registered", action: .retryHotkey)
        }
    }

    private static func modelName(_ selection: ASRModelSelection) -> String {
        switch selection {
        case .qwen3_0_6B_8bit: return "Fast"
        case .qwen3_1_7B_4bit: return "Quality"
        }
    }

    // MARK: - Pure Render Decision Helpers

    /// Determines whether the Model Downloads section should show the acquisition
    /// row for a given model.
    ///
    /// This is a PURE render-decision helper — no lifecycle, task, state ownership,
    /// or side effects. It encapsulates the duplicate acquisition suppression rule:
    /// when Setup's speech model row is incomplete (showing acquisition UI), the
    /// normal Model Downloads section must suppress the same selected-model row.
    ///
    /// - Parameters:
    ///   - model: The model being considered for display in Model Downloads.
    ///   - selectedModel: The currently selected model (from ModelStatus).
    ///   - setupSpeechModelIncomplete: Whether Setup's speech model row is incomplete.
    /// - Returns: true if the row should be shown, false if it should be suppressed.
    public static func shouldShowAcquisitionRow(
        model: ASRModelSelection,
        selectedModel: ASRModelSelection,
        setupSpeechModelIncomplete: Bool
    ) -> Bool {
        // If Setup's speech model row is incomplete, suppress the selected model's
        // row in Model Downloads to avoid duplicate acquisition UI.
        if setupSpeechModelIncomplete && model == selectedModel {
            return false
        }
        // Otherwise show the row (for non-selected models, or when Setup is complete)
        return true
    }
}

/// The compact header/setup status. Intentionally small: three meaningful
/// states, not a full state machine.
public enum VoiceDockHeader: Sendable, Equatable {
    /// Every mandatory leg is ready.
    case ready

    /// At least one mandatory leg is not ready.
    case setupRequired

    /// At least one mandatory leg is not ready AND an authoritative speech
    /// runtime failure exists (coordinator entered `.failed`).
    case runtimeError

    public init(isReady: Bool, hasRuntimeFailure: Bool) {
        if isReady {
            self = .ready
        } else if hasRuntimeFailure {
            self = .runtimeError
        } else {
            self = .setupRequired
        }
    }

    /// Stable user-facing header text.
    public var displayName: String {
        switch self {
        case .ready: return "VoiceDock Ready"
        case .setupRequired: return "Setup Required"
        case .runtimeError: return "Runtime Error"
        }
    }
}