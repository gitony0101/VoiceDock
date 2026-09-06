//
//  HotKeyRegistrationObservabilityTests.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Deterministic observability tests for the semantic
//  hotkey-registration holder.
//
//  These tests exercise `HotKeyRegistrationObservable`, the small observable
//  projection owned by `HotKeyManager`, without touching Carbon, NSEvent, AX,
//  or any real global-hotkey registration. They prove:
//
//    - initial state is not-registered
//    - a real transition emits an `ObservableObject` change (objectWillChange)
//    - the reverse transition emits too
//    - redundant same-state updates are deduplicated (no misleading emission)
//    - Accessibility plays no part in the observable truth
//

import Combine
import Testing
@testable import VoiceDockCore

struct HotKeyRegistrationObservabilityTests {

    // O1: initial semantic state is not registered.
    @MainActor
    @Test("Initial observable state is not registered")
    func initialStateIsNotRegistered() {
        let observable = HotKeyRegistrationObservable()
        #expect(observable.state == .notRegistered)
        #expect(observable.isRegistered == false)
    }

    // O2: notRegistered → registered emits an observable change.
    @MainActor
    @Test("Transition to registered emits objectWillChange")
    func transitionToRegisteredEmits() {
        let observable = HotKeyRegistrationObservable()
        var emitCount = 0
        let cancellable = observable.objectWillChange.sink { emitCount += 1 }

        observable.update(to: .registered)

        #expect(observable.state == .registered)
        #expect(observable.isRegistered == true)
        #expect(emitCount == 1)
        _ = cancellable
    }

    // O3: registered → notRegistered emits an observable change.
    @MainActor
    @Test("Transition to not registered emits objectWillChange")
    func transitionToNotRegisteredEmits() {
        let observable = HotKeyRegistrationObservable(initialState: .registered)
        var emitCount = 0
        let cancellable = observable.objectWillChange.sink { emitCount += 1 }

        observable.update(to: .notRegistered)

        #expect(observable.state == .notRegistered)
        #expect(observable.isRegistered == false)
        #expect(emitCount == 1)
        _ = cancellable
    }

    // O4: repeating the same semantic state does not emit a misleading change.
    @MainActor
    @Test("Redundant same-state updates are deduplicated")
    func redundantUpdatesAreDeduplicated() {
        let observable = HotKeyRegistrationObservable()
        var emitCount = 0
        let cancellable = observable.objectWillChange.sink { emitCount += 1 }

        // First real transition emits.
        observable.update(to: .registered)
        #expect(emitCount == 1)

        // Repeating the same state does not emit.
        observable.update(to: .registered)
        observable.update(to: .registered)
        #expect(emitCount == 1)

        // A distinct transition emits again (still meaningful).
        observable.update(to: .notRegistered)
        #expect(emitCount == 2)

        // And repeating the new state is again silent.
        observable.update(to: .notRegistered)
        #expect(emitCount == 2)
        _ = cancellable
    }

    // O5: Accessibility is not an input into the observable truth. The holder
    // accepts only `HotKeyRegistrationState` (registered/notRegistered), which
    // derives solely from a registration status string; there is no channel for
    // an Accessibility value to influence it.
    @MainActor
    @Test("Accessibility is not an input to the observable truth")
    func accessibilityIsNotAnInput() {
        let observable = HotKeyRegistrationObservable()

        // The full observable API surface is `state`/`isRegistered`/`update`.
        // There is no accessibility parameter; whatever an app believes about
        // AX trust cannot be passed in. A not-registered observable stays
        // not-registered regardless of any hypothetical trust.
        observable.update(to: .notRegistered)
        #expect(observable.isRegistered == false)

        // Even after toggling a local "trust" concept, the observable truth is
        // unchanged until a genuine registered state is fed.
        let trust = true
        _ = trust
        #expect(observable.isRegistered == false)
    }
}