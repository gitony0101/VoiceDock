//
//  HotKeyRegistrationObservable.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Observable holder for the semantic hotkey truth.
//
//  This is the observable seam the future SwiftUI readiness checklist (0.4.4c)
//  subscribes to. It owns exactly one thing: the current
//  `HotKeyRegistrationState`, published via `ObservableObject`/`objectWillChange`
//  so a SwiftUI view re-renders when registration actually transitions — without
//  polling, reopening the popover, or inferring from Accessibility.
//
//  It performs no registration. Registration behavior remains owned by
//  `HotKeyManager`; that manager feeds this holder through `update(to:)`
//  whenever a real success, failure, or teardown occurs. Centralizing the
//  deduplication here (rather than re-emitting on every redundant write) keeps
//  the observable's emissions meaningful.
//
//  It is an `ObservableObject` and is `@MainActor`-isolated because it is
//  mutated from `HotKeyManager`, which resolves registration status on the main
//  actor. It is kept instantiable without any Carbon/NSEvent/AX/AVCapture call
//  so its semantics are deterministic in automated tests.

import Combine
import Foundation

/// An observable, deduplicating holder for `HotKeyRegistrationState`.
///
/// UI observes `$state` (or `objectWillChange`) to learn when hotkey
/// registration transitions between `.registered` and `.notRegistered`.
/// `update(to:)` is idempotent: passing a state equal to the current one emits
/// nothing, so repeated success/failure/teardown writes do not produce
/// misleadingly frequent change notifications.
@MainActor
public final class HotKeyRegistrationObservable: ObservableObject {
    /// The current semantic registration state. Read via `state`; observe via
    /// the `ObservableObject` publisher (`objectWillChange`) or `$state`.
    @Published public private(set) var state: HotKeyRegistrationState

    /// Convenience boolean reading of the current state.
    public var isRegistered: Bool {
        state.isRegistered
    }

    /// Creates an observable held at `initialState`.
    public init(initialState: HotKeyRegistrationState = .notRegistered) {
        self.state = initialState
    }

    /// Advances the observable to `newState`, deduplicating so an equal value
    /// does not republish. Call this exactly when real registration state
    /// changes; `HotKeyManager` is the sole caller in production.
    public func update(to newState: HotKeyRegistrationState) {
        if newState != state {
            state = newState
        }
    }
}