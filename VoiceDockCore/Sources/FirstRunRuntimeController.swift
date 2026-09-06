//
//  FirstRunRuntimeController.swift
//  VoiceDock
//
//  VoiceDock 0.4.4b — First-run setup/recovery orchestration.
//
//  The 0.4.4B audit established two first-run defects:
//
//    D1 — a fresh install whose selected model is missing/invalid pushes
//         SessionCoordinator into `.failed` after it repeatedly attempts a
//         provider load that can never succeed.
//    D5 — once the model is downloaded, nothing invokes a controlled
//         recovery, so the runtime stays failed until relaunch.
//
//  This type fixes both WITHOUT introducing a general application state
//  machine. Its single responsibility is the *setup-required-vs-runtime-load*
//  boundary:
//
//    - it decides, from authoritative `ModelStorage.isModelValid`, whether the
//      selected/required speech model exists before a provider load may begin;
//    - when the model is missing, it represents that as a normal setup
//      prerequisite (`modelRequired`), and never constructs/loads a provider;
//    - when the model becomes valid (either at launch or after a successful
//      download), it starts the runtime exactly once through the injected
//      coordinator factory, and then derives a UI-facing speech-runtime phase
//      from the coordinator's own authoritative `.state`.
//
//  Ownership rules (per spec):
//
//    - SessionCoordinator remains the sole lifecycle authority. This type
//      never issues provider.load(), never mutates coordinator authority, and
//      never bypasses `retry()` for genuine failure recovery.
//    - ModelAcquisitionController remains the download owner. This type only
//      receives an authoritative "installed" notice through
//      `handleInstalled(model:)` and re-validates against storage before
//      acting, so a cancelled/failed/stale acquisition can never start a
//      spurious recovery.
//    - This type owns nothing about microphone/hotkey/accessibility; it is
//      only the speech-runtime leg of the vertical slice.
//
//  `speechRuntimePhase` and `speechRuntimeReady` are DERIVED and UI-facing,
//  not a lifecycle owner. `speechRuntimeReady` deliberately equals "required
//  model valid AND coordinator state == .ready" — never `activeModel != nil`
//  (the audit showed activeModel can be set even when a load failed).
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "FirstRunRuntimeController")

/// A derived, UI-facing representation of where the speech runtime is on the
/// first-run boundary. This is NOT a state machine and owns no lifecycle; it
/// is computed from two authoritative inputs: whether the required model is
/// validly installed, and the coordinator's current `.state`.
public enum SpeechRuntimePhase: Equatable, Sendable {
    /// The selected/required speech model is authoritatively missing or
    /// invalid. This is a normal setup prerequisite, not a runtime failure.
    case modelRequired
    /// The model is valid and the runtime is starting/loading (or a start is
    /// pending). Includes `.starting`/`.loadingModel` and the transient window
    /// before the coordinator has been constructed.
    case runtimeLoading
    /// The coordinator reached `.ready` with a valid model.
    case runtimeReady
    /// The coordinator reached `.failed` with a valid model — a genuine
    /// load/warmup failure, distinct from a missing model.
    case runtimeFailed
}

/// Orchestrates the first-run speech-runtime boundary: gates provider load on
/// authoritative model validity, starts the runtime exactly once when the
/// required model is (or becomes) valid, and derives a speech-runtime phase
/// from the coordinator's own state.
@MainActor
public final class FirstRunRuntimeController: ObservableObject {

    /// Authoritative validity of the selected/required model, as last read
    /// from `ModelStorage`. `false` means "setup prerequisite", not failure.
    @Published public private(set) var requiredModelValid: Bool = false

    /// The constructed coordinator, or nil until the required model was valid
    /// and `startIfRequiredModelValid()` ran.
    @Published public private(set) var coordinator: SessionCoordinator?

    /// Derived UI-facing speech-runtime phase.
    @Published public private(set) var speechRuntimePhase: SpeechRuntimePhase = .modelRequired

    /// Derived boolean fed to `VoiceDockReadiness.speechRuntimeReady`.
    /// Equals "required model valid AND coordinator state == .ready".
    public var speechRuntimeReady: Bool {
        requiredModelValid && coordinator?.state == .ready
    }

    private let storage: ModelStorage
    /// Current selected model (the "required" model). Never written by this type.
    private let selectedModelProvider: @MainActor () -> ASRModelSelection
    /// Constructs a SessionCoordinator. Invoked at most once, only after the
    /// required model is authoritatively valid.
    private let coordinatorProvider: @MainActor () -> SessionCoordinator?

    /// Exactly-once start authority. Ensures repeated/completed install
    /// notices never start overlapping runtimes.
    private var started = false
    /// Subscription driving phase recomputation from coordinator state.
    private var coordinatorStateCancellable: AnyCancellable?

    public init(
        storage: ModelStorage,
        selectedModelProvider: @escaping @MainActor () -> ASRModelSelection,
        coordinatorProvider: @escaping @MainActor () -> SessionCoordinator?
    ) {
        self.storage = storage
        self.selectedModelProvider = selectedModelProvider
        self.coordinatorProvider = coordinatorProvider
    }

    // MARK: - Launch / authoritative check

    /// Re-read authoritative validity for the selected/required model and
    /// refresh the derived phase. Call at launch. Never constructs a provider.
    public func checkRequiredModel() async {
        requiredModelValid = await storage.isModelValid(selectedModelProvider().modelDescriptor)
        recomputePhase()
    }

    /// Start the runtime if (and only if) the required model is authoritative
    /// valid. Returns true when a start was initiated or was already started;
    /// false when the model is missing/invalid — in which case NO provider is
    /// constructed and no load is attempted.
    @discardableResult
    public func startIfRequiredModelValid() -> Bool {
        guard requiredModelValid else {
            recomputePhase()
            return false
        }
        startCoordinatorIfNeeded()
        return true
    }

    // MARK: - Post-download recovery

    /// Handle an authoritative "model installed" notice. Only the selected
    /// (required) model matters; a Quality install while Fast is selected is a
    /// no-op that never disturbs a running (or pending) Fast runtime. The
    /// notice is re-validated against storage before any start, and the
    /// exactly-once `started` authority prevents overlapping starts.
    public func handleInstalled(_ model: ASRModelSelection) {
        // Fast/Quality boundary: only the currently required model may start.
        guard model == selectedModelProvider() else {
            logger.info("Installed \(model.rawValue, privacy: .public) is not the selected model; ignoring for runtime start")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Re-confirm selection and authoritative validity at the moment of
            // action; a download does not change selection, but this is the
            // single authority point that refuses a stale/failed install.
            let selected = self.selectedModelProvider()
            guard selected == model else { return }
            self.requiredModelValid = await self.storage.isModelValid(selected.modelDescriptor)
            guard self.requiredModelValid else {
                self.recomputePhase()
                return
            }
            self.startCoordinatorIfNeeded()
        }
    }

    // MARK: - Private

    private func startCoordinatorIfNeeded() {
        guard !started else { return }
        started = true
        let newCoordinator = coordinatorProvider()
        coordinator = newCoordinator
        // Drive phase recomputation from the coordinator's state. The `$state`
        // publisher emits on `willSet` (before `state` is actually assigned),
        // so we must use the emitted value, not re-read the stored property
        // (which would be stale at emission time).
        coordinatorStateCancellable = newCoordinator?.$state.sink { [weak self] newState in
            self?.recomputePhase(coordinatorState: newState)
        }
        recomputePhase(coordinatorState: newCoordinator?.state ?? .starting)
    }

    private func recomputePhase(coordinatorState: SessionCoordinator.State? = nil) {
        guard requiredModelValid else {
            speechRuntimePhase = .modelRequired
            return
        }
        guard let coordinator else {
            speechRuntimePhase = .runtimeLoading
            return
        }
        let state = coordinatorState ?? coordinator.state
        switch state {
        case .ready:
            speechRuntimePhase = .runtimeReady
        case .failed:
            speechRuntimePhase = .runtimeFailed
        default:
            speechRuntimePhase = .runtimeLoading
        }
    }
}