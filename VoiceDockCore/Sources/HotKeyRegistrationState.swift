//
//  HotKeyRegistrationState.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Semantic truth for global push-to-talk registration.
//
//  `HotKeyManager` (in the app target) owns the actual Carbon/NSEvent
//  registration algorithm. This file contributes only a *pure mapping* from
//  the status strings HotKeyManager already produces to a single boolean
//  semantic truth the rest of the app can read:
//
//      "is the hotkey actually registered right now?"
//
//  The mapping is the entire seam. It must never perform registration, touch
//  Carbon/NSEvent, read Accessibility state, or reach for any OS API — that
//  keeps it deterministic and testable without a real hotkey registration.
//
//  The mapping is deliberately strict and deliberately does NOT look at
//  Accessibility. Accessibility being trusted is a different fact from the
//  hotkey being registered, and the 0.4.4A audit requires the two remain
//  independent. Only the values that mean "registration succeeded right now"
//  map to `true`.
//
//  Status vocabulary (mirrors HotKeyManager's `registrationStatus`):
//
//    - "success"                        → registered (Carbon or NSEvent)
//    - "not attempted"                  → not registered
//    - "failed: <code>"                 → not registered
//    - "failed: <code> (<stage>)"       → not registered
//    - "monitor registration failed"    → not registered (NSEvent path)
//    - "unregistered"                   → not registered (was, but torn down)
//
//  Any unrecognized status is treated as not-registered (fail-closed).

import Foundation

/// The pure semantic state of push-to-talk hotkey registration.
///
/// This is a projection of `HotKeyManager`'s status strings, not the
/// registration itself. It carries only `isRegistered`, so callers (and the
/// future readiness checklist in 0.4.4c) read one stable boolean rather than
/// string-matching status text.
public enum HotKeyRegistrationState: Sendable, Equatable {
    /// The hotkey is registered and active right now.
    case registered

    /// The hotkey is not registered right now (never attempted, failed, or
    /// torn down).
    case notRegistered

    /// Whether the hotkey is registered right now.
    public var isRegistered: Bool {
        switch self {
        case .registered:
            return true
        case .notRegistered:
            return false
        }
    }

    /// Derives the semantic state from a `HotKeyManager` status string.
    ///
    /// Pure: no OS APIs, no state, fully deterministic. Only `"success"` maps
    /// to `.registered`; every other value — including anything unrecognized —
    /// maps to `.notRegistered` (fail-closed).
    public init(status: String) {
        switch status {
        case "success":
            self = .registered
        default:
            self = .notRegistered
        }
    }
}