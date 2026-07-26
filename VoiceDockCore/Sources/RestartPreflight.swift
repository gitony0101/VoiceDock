//
//  RestartPreflight.swift
//  VoiceDock
//
//  VoiceDock 0.2 — Testable preflight for the Apply & Restart flow.
//
//  `MenuBarView.performRestart()` runs a sequence of persistence and launch
//  verifications before it is allowed to launch the restart helper and
//  terminate the current process. Earlier implementations inlined that
//  sequence inside `await MainActor.run { ... guard ... return ... }`
//  blocks, where the `return` exits only the closure — not the enclosing
//  `Task` — so a failed verification silently continued into the next step
//  and could launch the helper or terminate the app anyway. This pure
//  preflight type runs the verifications OUTSIDE any MainActor closure and
//  returns a typed outcome so the caller can `guard let result = ... else`
//  on the *Task* boundary. Deterministic tests exercise the preflight
//  directly instead of unit-testing private SwiftUI code.
//
//  Strict order (per spec):
//    1. validate selected model
//    2. write preference through the injected store
//    3. CFPreferences synchronize the suite domain, read back, verify equality
//    4. final read through the store, verify equality
//    5. verify the embedded helper exists and is executable
//
//  A helper is NEVER launched on any failed condition — the preflight does
//  not launch the helper at all; it returns `.ok` to the caller, which is the
//  only path that launches the helper and then immediately requests normal
//  termination.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "RestartPreflight")

/// Outcome of the restart preflight. `.ok` means every verification passed
/// and the caller may safely launch the helper at `helperPath` and then
/// request normal termination. `.failure(message)` means a verification
/// failed; the helper has NOT been launched and the current process must NOT
/// be terminated.
public enum RestartPreflightOutcome: Sendable, Equatable {
    case ok(helperPath: String)
    case failure(message: String)

    public var isOk: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Pure restart preflight. All Side-effecting primitives (model-install
/// check, helper existence check) are injected so tests stub them without
/// touching the real filesystem, and so no test ever launches a subprocess.
public enum RestartPreflight {

    /// Run the preflight for a pending Apply & Restart.
    ///
    /// - Parameters:
    ///   - selected: The newly selected model the user is applying.
    ///   - store: The same shared `ASRPreferenceStore` ModelStatus and the
    ///     factory read from, so persistence verification matches what the
    ///     new process will read.
    ///   - helperPath: Absolute path to the embedded restart helper.
    ///   - modelIsValid: Injected model-install check. Production passes
    ///     `{ await ModelStorage().isModelValid($0) }`; tests inject a stub.
    ///   - helperExistsAndExecutable: Injected helper presence+executability
    ///     check. Production uses `FileManager`; tests inject a stub.
    /// - Returns: `.ok(helperPath:)` when every step passed, otherwise a
    ///   `.failure(message:)` whose message is fit for UI display.
    public static func run(
        selected: ASRModelSelection,
        store: ASRPreferenceStore,
        helperPath: String,
        modelIsValid: @escaping @Sendable (QwenModelDescriptor) async -> Bool,
        helperExistsAndExecutable: @escaping @Sendable () -> Bool
    ) async -> RestartPreflightOutcome {
        // 1. Validate selected model. ASRModelSelection is a closed enum of
        //    installed descriptors, so any case is syntactically valid; the
        //    install check below is the substantive validation. Kept as an
        //    explicit step so the strict order is observable in tests.
        // (No defensive reject — every enum case is a known selection.)

        // Pre-check: the selected model must be installed locally. A missing
        // or invalid model must not be applied — the user would otherwise
        // restart into a model that cannot load.
        let isValid = await modelIsValid(selected.modelDescriptor)
        if !isValid {
            let msg = "Selected model \(selected.displayName) is not installed locally. Keeping selection; not restarting."
            logger.error("RestartPreflight: \(msg, privacy: .public)")
            return .failure(message: msg)
        }

        // 2. Write preference through the shared store, and 3. force a
        //    CFPreferences synchronize, returning the raw value read back
        //    through the same store (no in-memory cache).
        var prefs = ASRModelPreferences.load(from: store)
        prefs.selectedModel = selected
        let readBack = prefs.saveAndSynchronize(to: store)

        // 3. Read back and verify exact equality.
        if readBack != selected.rawValue {
            let msg = "Model preference verification failed: wrote \(selected.rawValue) but read back \(readBack). Not restarting to avoid loading the wrong model."
            logger.error("RestartPreflight: \(msg, privacy: .public)")
            return .failure(message: msg)
        }

        // 4. Perform a final read through the store and verify exact equality.
        //    This is the last persistence check BEFORE any helper launch — a
        //    second process reading this store immediately after must see the
        //    same value.
        let finalRead = store.rawSelectedModelValue()
        if finalRead != selected.rawValue {
            let msg = "Final persistence verification failed: stored value is \(finalRead ?? "nil"), expected \(selected.rawValue). Not restarting."
            logger.error("RestartPreflight: \(msg, privacy: .public)")
            return .failure(message: msg)
        }

        // 5. Verify the embedded helper exists and is executable.
        if !helperExistsAndExecutable() {
            let msg = "Restart helper missing or not executable at \(helperPath). Not restarting."
            logger.error("RestartPreflight: \(msg, privacy: .public)")
            return .failure(message: msg)
        }

        return .ok(helperPath: helperPath)
    }
}
