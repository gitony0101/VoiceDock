//
//  ModelAcquisitionController.swift
//  VoiceDock
//
//  VoiceDock 0.4.3 — Model download UI controller.
//
//  A minimal, UI-facing controller over the hardened `ModelInstaller` /
//  `ModelStorage` backend. It lets a normal user view install state, download a
//  missing model, observe normalized progress, cancel, and retry — without
//  putting async installation orchestration into SwiftUI view code.
//
//  Separation it enforces:
//  - *downloaded / installed* (authoritative `ModelStorage.isModelValid`) is
//    tracked here and is NOT the same as *selected / active* (owned by
//    `ModelStatus`). Downloading a model never changes the selected model.
//  - This controller owns the single in-flight install `Task`. It uses a
//    monotonically-rising generation so a stale/retired task can never overwrite
//    the state of a newer operation (cancel → retry preserves authority).
//

import Foundation
import os.log
import Combine

private let logger = Logger(subsystem: "com.voicedock.core", category: "ModelAcquisitionController")

/// UI-facing acquisition state for a single model.
public enum ModelAcquisitionState: Equatable, Sendable {
    /// Not installed and no operation is running (present `[Download]`).
    case idle
    /// Initial / refresh validity check is in flight.
    case checking
    /// A download is running with normalized `0.0 ... 1.0` progress.
    case downloading(progress: Double)
    /// The model is validly installed (authoritative storage validation).
    case installed
    /// A download failed; user-facing generic message only (never a raw dump).
    case failed(message: String?)

    /// Is an operation currently active for this model's row?
    public var isActive: Bool {
        switch self {
        case .downloading:
            return true
        case .idle, .checking, .installed, .failed:
            return false
        }
    }
}

/// Owns the download task and per-model acquisition state.
///
/// Intentionally *not* a general application state machine, and deliberately
/// separate from `SessionCoordinator` (speech lifecycle). It injects the
/// installer + storage + preference store so deterministic tests exercise real
/// transaction semantics against temp-dir storage with no network access.
@MainActor
public final class ModelAcquisitionController: ObservableObject {

    /// Per-model acquisition state keyed by selection.
    @Published public private(set) var states: [ASRModelSelection: ModelAcquisitionState] = [:]

    /// The selection currently owned by an in-flight task, if any.
    @Published public private(set) var activeOperation: ASRModelSelection?

    /// Product-first ordering: Fast (recommended) before Quality (optional).
    public static let presentationOrder: [ASRModelSelection] = [
        .qwen3_0_6B_8bit,  // Fast — recommended / default
        .qwen3_1_7B_4bit,  // Quality — optional
    ]

    /// Product display metadata keyed by selection: recommended (Fast) vs
    /// optional (Quality). Exposed so the UI renders `Recommended` / `Optional`
    /// and the unit tests can assert the product-first policy (T12).
    public static let isRecommended: [ASRModelSelection: Bool] = [
        .qwen3_0_6B_8bit: true,   // Fast — default / recommended
        .qwen3_1_7B_4bit: false,  // Quality — optional
    ]

    private let installer: ModelInstaller
    private let storage: ModelStorage
    /// Reference to the selection source (used only to prove download does not
    /// mutate selection, and surfaced for T10). Never written by this type.
    public let selectedModelProvider: () -> ASRModelSelection

    private var downloadTask: Task<Void, Never>?
    /// Monotonic generation. Bumped on every `download`/`retry`/`cancel` start;
    /// a task that finishes under an older generation is stale and cannot
    /// mutate state.
    private var generation: UInt64 = 0

    /// Authoritative install completion notice. Invoked exactly once per
    /// successful, non-stale, non-cancelled install — only after
    /// `storage.isModelValid` confirms the model is installed, and only under
    /// the still-current generation. A cancelled/failed/stale operation never
    /// fires this. This is the single signal a composition layer uses to
    /// start/recover the speech runtime after a first-run download. The
    /// controller owns its own lifecycle; this type never reaches into
    /// SessionCoordinator.
    public var onInstalled: (@MainActor (ASRModelSelection) -> Void)?

    public init(
        installer: ModelInstaller,
        storage: ModelStorage,
        selectedModelProvider: @escaping @MainActor () -> ASRModelSelection
    ) {
        self.installer = installer
        self.storage = storage
        self.selectedModelProvider = selectedModelProvider
        states = Dictionary(uniqueKeysWithValues: Self.presentationOrder.map {
            ($0, ModelAcquisitionState.checking)
        })
    }

    /// Convenience initializer: production app wiring passes the model status
    /// supplier. Tests pass an isolated `ModelStatus` or a fixed closure.
    public convenience init(
        installer: ModelInstaller,
        storage: ModelStorage,
        modelStatus: ModelStatus
    ) {
        self.init(
            installer: installer,
            storage: storage,
            selectedModelProvider: { modelStatus.selectedModel }
        )
    }

    // MARK: - Install state

    /// Re-read authoritative validity for every model. This is the single
    /// source of truth for "installed" — never a previously-clicked button,
    /// never "download reached 100%". Call on launch / popover open.
    public func refreshInstalled() async {
        var next: [ASRModelSelection: ModelAcquisitionState] = [:]
        for model in Self.presentationOrder {
            // Keep an in-flight download untouched during refresh; otherwise
            // converge from authoritative storage validation.
            if case .downloading = states[model] {
                next[model] = states[model]
                continue
            }
            let valid = await storage.isModelValid(model.modelDescriptor)
            next[model] = valid ? .installed : .idle
        }
        states = next
    }

    /// The state for a single model, defaulting to `.checking` before refresh.
    public func state(for model: ASRModelSelection) -> ModelAcquisitionState {
        states[model] ?? .checking
    }

    // MARK: - Actions

    /// Start (or restart) a download for `model`. Cancels any prior operation
    /// and bumps the generation so the retired task cannot overwrite this one.
    public func download(_ model: ASRModelSelection) {
        startInstall(model)
    }

    /// Retry a previously failed download for `model`.
    public func retry(_ model: ASRModelSelection) {
        startInstall(model)
    }

    /// Cancel the currently owned operation. Cancelling is never an error:
    /// the owned task is cancelled, ownership is cleared, and — unless the
    /// model was already valid before the operation — the row returns to
    /// `.idle` (Not Installed → [Download]).
    public func cancel() {
        guard let task = downloadTask else { return }
        generation &+= 1            // retire the current operation
        let retiredGen = generation
        let wasModel = activeOperation
        task.cancel()
        downloadTask = nil
        activeOperation = nil

        // Re-read authoritative validity for the model that was active: if it
        // was already valid before the cancelled op, show Installed; else Idle.
        if let model = wasModel {
            Task { [weak self] in
                guard let self else { return }
                let valid = await self.storage.isModelValid(model.modelDescriptor)
                guard self.generation == retiredGen else { return }
                self.states[model] = valid ? .installed : .idle
            }
        }
    }

    // MARK: - Private orchestration

    private func startInstall(_ model: ASRModelSelection) {
        // Retire any currently owned task: it must not mutate state.
        downloadTask?.cancel()
        generation &+= 1
        let myGeneration = generation

        states[model] = .downloading(progress: 0)
        activeOperation = model

        let descriptor = model.modelDescriptor
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runInstallTask(model: model, descriptor: descriptor, generation: myGeneration)
        }
        downloadTask = task
    }

    private func runInstallTask(
        model: ASRModelSelection,
        descriptor: QwenModelDescriptor,
        generation myGeneration: UInt64
    ) async {
        do {
            // Normalize backend progress (0…0.9 during download, 1.0 on mark).
            let installed = try await installer.install(descriptor) { [weak self] progress in
                guard let self else { return }
                let clamped = min(max(progress, 0), 1)
                // Only apply while this generation is still the owner.
                Task { @MainActor [weak self] in
                    guard let self, self.generation == myGeneration else { return }
                    if case .downloading = self.states[model] {
                        self.states[model] = .downloading(progress: clamped)
                    }
                }
            }

            guard self.generation == myGeneration else { return }  // stale

            // Authoritative re-validation: only report Installed after real
            // storage validation succeeds, never from "install returned true".
            let valid = await storage.isModelValid(descriptor)
            guard self.generation == myGeneration else { return }
            states[model] = valid ? .installed : .failed(message: "Download failed. Try again.")
            if !valid {
                logger.error("Install reported success but validation failed for \(descriptor.repoID, privacy: .public)")
            } else {
                // Authoritative install completion, exactly once, under the
                // still-current generation. This is the only recovery signal
                // emitted by acquisition.
                onInstalled?(model)
            }
            activeOperation = nil
            downloadTask = nil
        } catch is CancellationError {
            guard self.generation == myGeneration else { return }
            // Cancellation is not an error — converge back to authoritative
            // install state with no red error.
            let valid = await storage.isModelValid(descriptor)
            guard self.generation == myGeneration else { return }
            states[model] = valid ? .installed : .idle
            activeOperation = nil
            downloadTask = nil
        } catch {
            guard self.generation == myGeneration else { return }
            logger.error("Download failed for \(descriptor.repoID, privacy: .public): \(error.localizedDescription)")
            // Generic user-facing text only; detailed cause stays in the log.
            states[model] = .failed(message: "Download failed. Try again.")
            activeOperation = nil
            downloadTask = nil
        }
    }
}