//
//  HotKeyRegistrationStateTests.swift
//  VoiceDock
//
//  VoiceDock 0.4.4a — Deterministic tests for the semantic hotkey-state seam.
//
//  These tests exercise the pure status→truth mapping only; they do not touch
//  Carbon, NSEvent, or a real global hotkey registration, and they do not read
//  Accessibility. They prove the invariant: Accessibility trust and hotkey
//  registration are independent facts.
//

import Testing
@testable import VoiceDockCore

struct HotKeyRegistrationStateTests {

    // H1: "not attempted" → not registered
    @Test("Not attempted maps to not registered")
    func notAttemptedIsNotRegistered() {
        let state = HotKeyRegistrationState(status: "not attempted")
        #expect(state.isRegistered == false)
        #expect(state == .notRegistered)
    }

    // H2: "success" → registered
    @Test("Success maps to registered")
    func successIsRegistered() {
        let state = HotKeyRegistrationState(status: "success")
        #expect(state.isRegistered == true)
        #expect(state == .registered)
    }

    // H3: "failed: ..." → not registered
    @Test("Failed maps to not registered")
    func failedIsNotRegistered() {
        #expect(HotKeyRegistrationState(status: "failed: -9878").isRegistered == false)
        #expect(HotKeyRegistrationState(status: "failed: -600").isRegistered == false)
        #expect(HotKeyRegistrationState(status: "failed: -9873 (RegisterEventHotKey)").isRegistered == false)
    }

    // H4: "unregistered" → not registered
    @Test("Unregistered maps to not registered")
    func unregisteredIsNotRegistered() {
        let state = HotKeyRegistrationState(status: "unregistered")
        #expect(state.isRegistered == false)
        #expect(state == .notRegistered)
    }

    // H4b: the NSEvent monitor-failure status also maps to not registered.
    @Test("Monitor registration failure maps to not registered")
    func monitorFailureIsNotRegistered() {
        let state = HotKeyRegistrationState(status: "monitor registration failed")
        #expect(state.isRegistered == false)
        #expect(state == .notRegistered)
    }

    // H5: Accessibility state alone does not force registered=true.
    // The mapping has no Accessibility input at all; the only non-success
    // status that could register is "success", and trust is not an input.
    @Test("Accessibility trust is not a registration signal")
    func accessibilityDoesNotForceRegistration() {
        // The seam takes only a status string. Trust (whatever its value)
        // cannot be represented, so it cannot flip the result.
        let trusted = true
        let untrusted = false
        _ = trusted
        _ = untrusted

        // Even a "trusted" environment with a failed/unattempted registration
        // must report not-registered: the mapping has no trust channel.
        #expect(HotKeyRegistrationState(status: "not attempted").isRegistered == false)
        #expect(HotKeyRegistrationState(status: "failed: -9878").isRegistered == false)
        #expect(HotKeyRegistrationState(status: "unregistered").isRegistered == false)
    }

    // Unknown statuses fail closed (treated as not registered).
    @Test("Unknown status fails closed to not registered")
    func unknownStatusFailsClosed() {
        #expect(HotKeyRegistrationState(status: "garbage").isRegistered == false)
        #expect(HotKeyRegistrationState(status: "").isRegistered == false)
    }
}