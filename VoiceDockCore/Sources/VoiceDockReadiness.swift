//
//  VoiceDockReadiness.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Derived, read-only readiness projection.
//
//  A pure value type that answers one question for a caller: "is the whole
//  speech-input vertical slice ready to use right now?" It is a *projection*:
//  it receives four already-derived booleans from an authoritative source and
//  derives a single `isReady` from them. It owns nothing and does nothing.
//
//  The four inputs are kept deliberately distinct because the 0.4.4A audit
//  proved they do not collapse into one another:
//
//    - `speechRuntimeReady` is NOT `selected == active`, and it is NOT
//      `activeModel != nil`. The audit showed `activeModel` can be set even
//      when a model load failed, so "active" and "loaded and ready" are
//      different truths. The caller composes `speechRuntimeReady` from the
//      authoritative runtime truth (Installed → Selected → Active → Loaded
//      → Ready); this type accepts only the final boolean.
//
//    - `hotkeyReady` is NOT derived from `accessibilityReady`. Accessibility
//      being trusted does not mean the hotkey actually registered (Carbon can
//      still fail, or fall back). The two are independent.
//
//    - `microphoneReady` is independent of everything else as well.
//
//  This type must never:
//
//    - own tasks, register hotkeys, request permissions, or download models
//    - mutate ModelStatus or SessionCoordinator
//    - read UserDefaults or the filesystem
//    - call AX or AVCapture APIs
//
//  It is a pure value with a pure computed property.

import Foundation

/// A derived, read-only snapshot of whether each leg of the VoiceDock
/// push-to-talk vertical slice is ready, and whether the whole slice is ready.
///
/// Constructed only from booleans the caller has already derived from
/// authoritative runtime state. `isReady` requires all four.
public struct VoiceDockReadiness: Sendable, Equatable {
    /// The speech runtime (active Qwen3-ASR model) is loaded and ready to
    /// transcribe. This is NOT "a model is selected/active"; the provider must
    /// actually have loaded successfully.
    public let speechRuntimeReady: Bool

    /// Microphone capture is available and usable.
    public let microphoneReady: Bool

    /// The application is trusted for Accessibility (paste delivery).
    public let accessibilityReady: Bool

    /// The global push-to-talk hotkey is actually registered right now.
    public let hotkeyReady: Bool

    /// Creates a readiness snapshot from four independently-derived booleans.
    /// The struct has no logic beyond `isReady`; it records truth, it does not
    /// compute or own it.
    public init(
        speechRuntimeReady: Bool,
        microphoneReady: Bool,
        accessibilityReady: Bool,
        hotkeyReady: Bool
    ) {
        self.speechRuntimeReady = speechRuntimeReady
        self.microphoneReady = microphoneReady
        self.accessibilityReady = accessibilityReady
        self.hotkeyReady = hotkeyReady
    }

    /// True only when every leg of the vertical slice is ready.
    ///
    /// This is a strict conjunction: any single false leg forces `false`,
    /// and there is no notion of "mostly ready".
    public var isReady: Bool {
        speechRuntimeReady
            && microphoneReady
            && accessibilityReady
            && hotkeyReady
    }
}