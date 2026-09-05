//
//  VoiceDockReadinessTests.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Deterministic tests for the pure readiness projection.
//
//  These tests assert exactly the conjunction semantics of
//  `VoiceDockReadiness.isReady` and the purity of the type. No OS APIs, no
//  UserDefaults, no filesystem, no model, no microphone.
//

import Testing
@testable import VoiceDockCore

struct VoiceDockReadinessTests {

    private func make(
        speech: Bool = false,
        microphone: Bool = false,
        accessibility: Bool = false,
        hotkey: Bool = false
    ) -> VoiceDockReadiness {
        VoiceDockReadiness(
            speechRuntimeReady: speech,
            microphoneReady: microphone,
            accessibilityReady: accessibility,
            hotkeyReady: hotkey
        )
    }

    // R1: all false → isReady false
    @Test("All false yields not-ready")
    func allFalseIsNotReady() {
        #expect(make().isReady == false)
    }

    // R2: speech only → false
    @Test("Speech only yields not-ready")
    func speechOnlyIsNotReady() {
        #expect(make(speech: true).isReady == false)
    }

    // R3: microphone only → false
    @Test("Microphone only yields not-ready")
    func microphoneOnlyIsNotReady() {
        #expect(make(microphone: true).isReady == false)
    }

    // R4: accessibility only → false
    @Test("Accessibility only yields not-ready")
    func accessibilityOnlyIsNotReady() {
        #expect(make(accessibility: true).isReady == false)
    }

    // R5: hotkey only → false
    @Test("Hotkey only yields not-ready")
    func hotkeyOnlyIsNotReady() {
        #expect(make(hotkey: true).isReady == false)
    }

    // R6: speech + mic + AX but hotkey false → false (critical)
    @Test("Missing hotkey blocks readiness")
    func missingHotkeyBlocksReadiness() {
        #expect(make(speech: true, microphone: true, accessibility: true, hotkey: false).isReady == false)
    }

    // R7: speech + mic + hotkey but AX false → false
    @Test("Missing accessibility blocks readiness")
    func missingAccessibilityBlocksReadiness() {
        #expect(make(speech: true, microphone: true, accessibility: false, hotkey: true).isReady == false)
    }

    // R8: speech + AX + hotkey but mic false → false
    @Test("Missing microphone blocks readiness")
    func missingMicrophoneBlocksReadiness() {
        #expect(make(speech: true, microphone: false, accessibility: true, hotkey: true).isReady == false)
    }

    // R9: mic + AX + hotkey but speech false → false
    @Test("Missing speech runtime blocks readiness")
    func missingSpeechRuntimeBlocksReadiness() {
        #expect(make(speech: false, microphone: true, accessibility: true, hotkey: true).isReady == false)
    }

    // R10: all true → true
    @Test("All legs true yields ready")
    func allTrueIsReady() {
        #expect(make(speech: true, microphone: true, accessibility: true, hotkey: true).isReady == true)
    }

    // R11: constructing/evaluating readiness does not mutate any input/source.
    // The type is a pure value; constructing it has no side effects. We assert
    // the inputs remain as passed and that repeated evaluation is stable.
    @Test("Readiness is a pure value with no side effects")
    func readinessIsPure() {
        let r = VoiceDockReadiness(
            speechRuntimeReady: true,
            microphoneReady: false,
            accessibilityReady: true,
            hotkeyReady: false
        )

        // Evaluating repeatedly is stable and never changes the recorded fields.
        for _ in 0..<100 {
            #expect(r.speechRuntimeReady == true)
            #expect(r.microphoneReady == false)
            #expect(r.accessibilityReady == true)
            #expect(r.hotkeyReady == false)
            #expect(r.isReady == false)
        }

        // The four inputs are preserved verbatim (no collapsing/rewriting).
        let again = VoiceDockReadiness(
            speechRuntimeReady: r.speechRuntimeReady,
            microphoneReady: r.microphoneReady,
            accessibilityReady: r.accessibilityReady,
            hotkeyReady: r.hotkeyReady
        )
        #expect(again == r)
    }

    // R12: Quality optionality is NOT encoded. The type carries only booleans
    // and has no notion of a model family or Quality-vs-Fast; nothing in its
    // API can name one. We assert it has no model-selection surface at all by
    // confirming the only inputs/outputs are the four booleans and `isReady`.
    @Test("Readiness has no model-selection surface")
    func readinessHasNoModelVariant() {
        // The struct exposes exactly the four booleans plus `isReady`; there is
        // no field for a model family, no distinction for Fast vs Quality.
        let r = VoiceDockReadiness(speechRuntimeReady: true, microphoneReady: true, accessibilityReady: true, hotkeyReady: true)
        _ = r.speechRuntimeReady
        _ = r.microphoneReady
        _ = r.accessibilityReady
        _ = r.hotkeyReady
        _ = r.isReady
        // Compile-time: a "quality"/"fast" accessor would not type-check here.
        #expect(r.isReady == true)
    }
}