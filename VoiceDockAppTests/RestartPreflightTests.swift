//
//  RestartPreflightTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 — Deterministic tests for the restart preflight.
//
//  These tests exercise `RestartPreflight.run(...)` directly with injected
//  stubs so no helper subprocess is ever launched and no real model install
//  check hits the disk. They assert the strict order (helper is NOT launched
//  on any failed condition) and the exact equality verifications.
//

import Testing
import Foundation
@testable import VoiceDockCore

/// Thread-safe mutable counter so `@Sendable` preflight stubs can record call
/// counts without capturing mutable Swift locals (forbidden by Swift 6's
/// `SendableClosureCaptures` diagnostic). All access goes through a
/// `DispatchQueue.sync` so reads after the preflight are deterministic.
private final class Counter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "voicedock.test.counter")
    private var value = 0
    func increment() { queue.sync { value += 1 } }
    func get() -> Int { queue.sync { value } }
}

@Suite("Restart Preflight Tests")
struct RestartPreflightTests {

    /// Isolated preference store per test (UUID suite, never touches
    /// production preferences).
    private func makeStore() -> ASRPreferenceStore {
        ASRPreferenceStore.isolate("preflight-\(UUID().uuidString)")
    }

    @Test("All-pass preflight returns ok with the helper path")
    func allClearReturnsOk() async {
        let store = makeStore()
        let helperPath = "/tmp/voicedock-restart-helper"

        let outcome = await RestartPreflight.run(
            selected: .qwen3_0_6B_8bit,
            store: store,
            helperPath: helperPath,
            modelIsValid: { _ in true },
            helperExistsAndExecutable: { true }
        )

        if case .ok(let path) = outcome {
            #expect(path == helperPath)
        } else {
            Issue.record("Expected .ok, got \(outcome)")
        }
    }

    @Test("Missing model install fails preflight before any preference write is considered")
    func missingModelFails() async {
        let store = makeStore()
        let modelChecked = Counter()
        let helperChecked = Counter()

        let outcome = await RestartPreflight.run(
            selected: .qwen3_0_6B_8bit,
            store: store,
            helperPath: "/tmp/helper",
            modelIsValid: { _ in
                modelChecked.increment()
                return false
            },
            helperExistsAndExecutable: {
                helperChecked.increment()
                return true
            }
        )

        if case .failure(let msg) = outcome {
            #expect(msg.lowercased().contains("not installed"))
        } else {
            Issue.record("Expected .failure on missing model")
        }
        // The model-install check is the FIRST substantive verification.
        #expect(modelChecked.get() == 1)
        // A missing precondition must abort BEFORE the helper check.
        #expect(helperChecked.get() == 0)
    }

    @Test("Persisted preference round-trips through the store on the success path")
    func persistedPreferenceRoundTripsAndReachesHelperStage() async {
        let store = makeStore()
        let helperChecked = Counter()

        let outcome = await RestartPreflight.run(
            selected: .qwen3_0_6B_8bit,
            store: store,
            helperPath: "/tmp/helper",
            modelIsValid: { _ in true },
            helperExistsAndExecutable: {
                helperChecked.increment()
                return true
            }
        )

        if case .ok = outcome {
            #expect(helperChecked.get() == 1)
        } else {
            Issue.record("Expected .ok on a clean preflight")
        }
        // The final persisted value across the store matches the selection.
        #expect(store.rawSelectedModelValue() == "qwen3-0.6b-8bit")
    }

    @Test("Missing helper fails preflight after persistence checks pass")
    func missingHelperFails() async {
        let store = makeStore()

        let outcome = await RestartPreflight.run(
            selected: .qwen3_0_6B_8bit,
            store: store,
            helperPath: "/nonexistent/voice-dock-restart-helper",
            modelIsValid: { _ in true },
            helperExistsAndExecutable: { false }
        )

        if case .failure(let msg) = outcome {
            #expect(msg.lowercased().contains("helper"))
        } else {
            Issue.record("Expected .failure on missing helper")
        }
        // Persistence must have succeeded (the store now reflects Fast).
        #expect(store.rawSelectedModelValue() == "qwen3-0.6b-8bit")
    }

    @Test("Selection is persisted through the shared store on the success path")
    func selectionPersistedOnSuccess() async {
        let store = makeStore()

        _ = await RestartPreflight.run(
            selected: .qwen3_0_6B_8bit,
            store: store,
            helperPath: "/tmp/helper",
            modelIsValid: { _ in true },
            helperExistsAndExecutable: { true }
        )

        #expect(store.rawSelectedModelValue() == "qwen3-0.6b-8bit")
    }

    @Test("Quality selection persists Quality through the store")
    func qualitySelectionPersists() async {
        let store = makeStore()

        _ = await RestartPreflight.run(
            selected: .qwen3_1_7B_4bit,
            store: store,
            helperPath: "/tmp/helper",
            modelIsValid: { _ in true },
            helperExistsAndExecutable: { true }
        )

        #expect(store.rawSelectedModelValue() == "qwen3-1.7b-4bit")
    }
}
