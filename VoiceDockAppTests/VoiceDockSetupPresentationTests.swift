//
//  VoiceDockSetupPresentationTests.swift
//  VoiceDock
//
//  VoiceDock 0.4.4c1 — Deterministic tests for the pure setup presentation model.
//
//  These tests pin the strict-conjunction readiness, the per-mandatory-leg row
//  states, the model-row state machine (M1–M8), and the selection-aware
//  behavior (SEL1–SEL4) defined in the 0.4.4c1 specification. They exercise only
//  pure value mapping — no OS APIs, no UserDefaults, no filesystem, no model,
//  no microphone, no hotkey registration.
//

import Testing
@testable import VoiceDockCore

struct VoiceDockSetupPresentationTests {

    // MARK: - Test fixtures

    private func make(
        selectedModel: ASRModelSelection = .qwen3_0_6B_8bit,   // Fast (clean default)
        selectedModelValid: Bool = false,
        acquisition: ModelAcquisitionState = .idle,
        coordinatorState: SessionCoordinator.State = .starting,
        microphone: VoiceDockMicrophoneState = .notDetermined,
        accessibilityTrusted: Bool = false,
        hotkeyRegistration: HotKeyRegistrationState = .notRegistered
    ) -> VoiceDockSetupPresentation {
        VoiceDockSetupPresentation(
            selectedModel: selectedModel,
            selectedModelValid: selectedModelValid,
            selectedModelAcquisition: acquisition,
            coordinatorState: coordinatorState,
            microphone: microphone,
            accessibilityTrusted: accessibilityTrusted,
            hotkeyRegistration: hotkeyRegistration
        )
    }

    /// A fully-ready fixture: Fast selected, valid, coordinator ready, mic
    /// granted, AX trusted, hotkey registered.
    private func makeReady() -> VoiceDockSetupPresentation {
        make(
            selectedModel: .qwen3_0_6B_8bit,
            selectedModelValid: true,
            acquisition: .installed,
            coordinatorState: .ready,
            microphone: .granted,
            accessibilityTrusted: true,
            hotkeyRegistration: .registered
        )
    }

    // MARK: - Speech runtime invariant

    @Test("Speech runtime ready requires selected model valid AND coordinator ready")
    func speechRuntimeInvariant() {
        // Valid but coordinator not ready → not ready.
        let a = make(selectedModelValid: true, acquisition: .installed, coordinatorState: .loadingModel,
                     microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(a.readiness.speechRuntimeReady == false)

        // Coordinator ready but model not valid → not ready.
        let b = make(selectedModelValid: false, acquisition: .idle, coordinatorState: .ready,
                     microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(b.readiness.speechRuntimeReady == false)

        // Both → ready leg.
        let c = makeReady()
        #expect(c.readiness.speechRuntimeReady == true)
    }

    // MARK: - Overall readiness (P1–P10)

    @Test("P1 all false → not ready")
    func p1_allFalse() {
        #expect(make().isReady == false)
    }

    @Test("P2 model only → not ready")
    func p2_modelOnly() {
        #expect(makeReady().isReady == true) // sanity: full fixture is ready
        let onlyModel = make(
            selectedModelValid: true, acquisition: .installed, coordinatorState: .ready,
            microphone: .notDetermined, accessibilityTrusted: false, hotkeyRegistration: .notRegistered
        )
        #expect(onlyModel.isReady == false)
    }

    @Test("P3 microphone only → not ready")
    func p3_micOnly() {
        let r = make(
            selectedModelValid: false, acquisition: .idle, coordinatorState: .starting,
            microphone: .granted, accessibilityTrusted: false, hotkeyRegistration: .notRegistered
        )
        #expect(r.isReady == false)
    }

    @Test("P4 Accessibility only → not ready")
    func p4_accessibilityOnly() {
        let r = make(
            selectedModelValid: false, acquisition: .idle, coordinatorState: .starting,
            microphone: .notDetermined, accessibilityTrusted: true, hotkeyRegistration: .notRegistered
        )
        #expect(r.isReady == false)
    }

    @Test("P5 hotkey only → not ready")
    func p5_hotkeyOnly() {
        let r = make(
            selectedModelValid: false, acquisition: .idle, coordinatorState: .starting,
            microphone: .notDetermined, accessibilityTrusted: false, hotkeyRegistration: .registered
        )
        #expect(r.isReady == false)
    }

    @Test("P6 model + mic + AX, hotkey false → not ready")
    func p6_missingHotkeyBlocksReady() {
        let r = make(
            selectedModelValid: true, acquisition: .installed, coordinatorState: .ready,
            microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .notRegistered
        )
        #expect(r.isReady == false)
        #expect(r.hotkey.isComplete == false)
    }

    @Test("P7 all true → ready")
    func p7_allTrue() {
        #expect(makeReady().isReady == true)
    }

    @Test("P8 ready then microphone revoked → not ready")
    func p8_microphoneRevoked() {
        let revoked = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true, acquisition: .installed,
            coordinatorState: .ready, microphone: .denied,
            accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        #expect(revoked.isReady == false)
        #expect(revoked.readiness.speechRuntimeReady == true)
        #expect(revoked.microphone.isComplete == false)
    }

    @Test("P9 ready then coordinator failed → speechRuntimeReady false → not ready")
    func p9_coordinatorFailed() {
        let failed = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true, acquisition: .installed,
            coordinatorState: .failed("boom"), microphone: .granted,
            accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        #expect(failed.readiness.speechRuntimeReady == false)
        #expect(failed.isReady == false)
        #expect(failed.header == .runtimeError)
    }

    @Test("P10 Fast selected ready + Quality missing → still ready")
    func p10_fastReadyQualityMissing() {
        // Quality missing is orthogonal: the selected (Fast) model is ready.
        let r = makeReady() // Fast selected, ready
        #expect(r.isReady == true)
    }

    // MARK: - Model row states (M1–M8)

    @Test("M1 selected model missing → incomplete Download")
    func m1_missing() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: false, acquisition: .idle,
                     coordinatorState: .starting, microphone: .granted,
                     accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .downloadSelectedModel)
    }

    @Test("M2 selected model downloading → progress Cancel")
    func m2_downloading() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: false,
                     acquisition: .downloading(progress: 0.5), coordinatorState: .loadingModel,
                     microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .cancelModelDownload)
    }

    @Test("M3 download failed → Retry")
    func m3_failed() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: false,
                     acquisition: .failed(message: nil), coordinatorState: .loadingModel,
                     microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .retryModelDownload)
    }

    @Test("M4 valid + coordinator nil/loading → incomplete Loading")
    func m4_loading() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true, acquisition: .installed,
                     coordinatorState: .loadingModel, microphone: .granted,
                     accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .none)
    }

    @Test("M5 valid + coordinator failed → incomplete Runtime error")
    func m5_runtimeError() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true, acquisition: .installed,
                     coordinatorState: .failed("load failed"), microphone: .granted,
                     accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .none)
        #expect(r.header == .runtimeError)
    }

    @Test("M6 valid + coordinator ready → complete")
    func m6_complete() {
        let r = makeReady()
        #expect(r.speechModel == .complete)
    }

    @Test("M7 Fast selected + Quality missing → does not affect ready")
    func m7_fastSelectedQualityStateIrrelevant() {
        // Fast selected & ready; Quality acquisition irrelevant to readiness.
        let r = makeReady()
        #expect(r.isReady == true)
        #expect(r.speechModel == .complete)
    }

    @Test("M8 Quality selected + missing → incomplete, Quality required, recoverable")
    func m8_qualityMissing() {
        let r = make(
            selectedModel: .qwen3_1_7B_4bit, selectedModelValid: false, acquisition: .idle,
            coordinatorState: .starting, microphone: .granted,
            accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        #expect(r.speechModel.isComplete == false)
        // Download is the surfaced action; the future UI also offers a switch
        // back to Fast (Recommended), but that is not forced here.
        #expect(r.speechModel.action == .downloadSelectedModel)
        // Quality is now the required model → speech runtime not ready.
        #expect(r.isReady == false)
    }

    // MARK: - Model-validity / acquisition independence (V1–V4)

    // `selectedModelValid` is authoritative and independent of
    // `ModelAcquisitionState`. Acquisition state is a UI/install-lifecycle
    // concern; it must never manufacture validity nor redefine an already-valid
    // runtime.

    @Test("V1 valid model + checking acquisition still runtime-ready")
    func testV1_validModelCheckingAcquisitionStillRuntimeReady() {
        let r = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true,
            acquisition: .checking, coordinatorState: .ready,
            microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        // Validity is the authoritative truth; `.checking` is incidental.
        #expect(r.readiness.speechRuntimeReady == true)
        #expect(r.isReady == true)
    }

    @Test("V2 valid model + idle acquisition still runtime-ready")
    func testV2_validModelIdleAcquisitionStillRuntimeReady() {
        let r = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true,
            acquisition: .idle, coordinatorState: .ready,
            microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        #expect(r.readiness.speechRuntimeReady == true)
        #expect(r.isReady == true)
    }

    @Test("V3 invalid model + installed acquisition cannot become ready")
    func testV3_invalidModelInstalledAcquisitionCannotBecomeReady() {
        let r = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: false,
            acquisition: .installed, coordinatorState: .ready,
            microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        // Acquisition `.installed` must NOT manufacture validity: the model is
        // still invalid, so the speech runtime is not ready.
        #expect(r.readiness.speechRuntimeReady == false)
        #expect(r.isReady == false)
        // The speech-model row stays incomplete, failing safely toward
        // authoritative validity (not the misleading acquisition state).
        #expect(r.speechModel.isComplete == false)
    }

    @Test("V4 valid + ready runtime ignores acquisition failure for readiness")
    func testV4_validReadyRuntimeIgnoresAcquisitionFailureForReadiness() {
        let r = make(
            selectedModel: .qwen3_0_6B_8bit, selectedModelValid: true,
            acquisition: .failed(message: "synthetic acquisition failure"),
            coordinatorState: .ready,
            microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        // An acquisition failure must NOT redefine an already-valid,
        // already-ready runtime.
        #expect(r.readiness.speechRuntimeReady == true)
        #expect(r.isReady == true)
    }

    // MARK: - Microphone row (MIC1–MIC3)

    @Test("MIC1 notDetermined → allowMicrophone")
    func mic1_notDetermined() {
        let r = make(microphone: .notDetermined)
        #expect(r.microphone.isComplete == false)
        #expect(r.microphone.action == .allowMicrophone)
    }

    @Test("MIC2 denied → openMicrophoneSettings")
    func mic2_denied() {
        let r = make(microphone: .denied)
        #expect(r.microphone.isComplete == false)
        #expect(r.microphone.action == .openMicrophoneSettings)
    }

    @Test("MIC3 granted → complete")
    func mic3_granted() {
        let r = make(microphone: .granted)
        #expect(r.microphone == .complete)
    }

    // MARK: - Accessibility row (AX1–AX2)

    @Test("AX1 not trusted → incomplete grant action")
    func ax1_notTrusted() {
        let r = make(accessibilityTrusted: false)
        #expect(r.accessibility.isComplete == false)
        #expect(r.accessibility.action == .grantOrOpenAccessibility)
    }

    @Test("AX2 trusted → complete")
    func ax2_trusted() {
        let r = make(accessibilityTrusted: true)
        #expect(r.accessibility == .complete)
    }

    // MARK: - Hotkey row (HK1–HK4)

    @Test("HK1 AX false + notRegistered → Waiting for Accessibility")
    func hk1_axFalseNotRegistered() {
        let r = make(accessibilityTrusted: false, hotkeyRegistration: .notRegistered)
        #expect(r.hotkey.isComplete == false)
        #expect(r.hotkey.action == .grantOrOpenAccessibility)
        #expect(r.hotkey.status.contains("Accessibility"))
    }

    @Test("HK2 AX true + notRegistered → Hotkey not registered")
    func hk2_axTrueNotRegistered() {
        let r = make(accessibilityTrusted: true, hotkeyRegistration: .notRegistered)
        #expect(r.hotkey.isComplete == false)
        #expect(r.hotkey.action == .none)
        #expect(r.hotkey.status.contains("not registered"))
    }

    @Test("HK3 AX true + registered → complete")
    func hk3_axTrueRegistered() {
        let r = make(accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.hotkey == .complete)
    }

    @Test("HK4 AX true must NOT imply registered")
    func hk4_axTrueDoesNotImplyRegistered() {
        let r = make(accessibilityTrusted: true, hotkeyRegistration: .notRegistered)
        // Critical: Accessibility trust alone does not make the hotkey ready.
        #expect(r.hotkey.isComplete == false)
        #expect(r.readiness.hotkeyReady == false)
        // hotkeyReady derives only from the registered state (false here),
        // never from Accessibility (which is true here).
    }

    // MARK: - Selection-aware (SEL1–SEL4)

    @Test("SEL1 clean/default Fast missing → Fast row required")
    func sel1_fastMissingRequired() {
        let r = make(selectedModel: .qwen3_0_6B_8bit, selectedModelValid: false, acquisition: .idle,
                     coordinatorState: .starting)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .downloadSelectedModel)
        #expect(r.isReady == false)
    }

    @Test("SEL2 Quality missing → Quality row required → not ready")
    func sel2_qualityMissingNotReady() {
        let r = make(selectedModel: .qwen3_1_7B_4bit, selectedModelValid: false, acquisition: .idle,
                     coordinatorState: .starting, microphone: .granted,
                     accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.speechModel.isComplete == false)
        #expect(r.speechModel.action == .downloadSelectedModel)
        #expect(r.isReady == false)
    }

    @Test("SEL3 Quality ready → Quality satisfies speechRuntimeReady")
    func sel3_qualityReadySatisfiesSpeechRuntime() {
        let r = make(
            selectedModel: .qwen3_1_7B_4bit, selectedModelValid: true, acquisition: .installed,
            coordinatorState: .ready, microphone: .granted,
            accessibilityTrusted: true, hotkeyRegistration: .registered
        )
        #expect(r.readiness.speechRuntimeReady == true)
        #expect(r.isReady == true)
        #expect(r.speechModel == .complete)
    }

    @Test("SEL4 Quality missing while Fast selected & ready → does NOT block readiness")
    func sel4_qualityMissingDoesNotBlock() {
        // Fast is the selected model and is ready; Quality being missing is
        // completely irrelevant to readiness (Quality is optional).
        let r = makeReady()
        #expect(r.isReady == true)
    }

    // MARK: - Header

    @Test("Header maps all-ready → VoiceDock Ready")
    func headerReady() {
        #expect(makeReady().header == .ready)
        #expect(makeReady().header.displayName == "VoiceDock Ready")
    }

    @Test("Header maps not-ready without runtime failure → Setup Required")
    func headerSetupRequired() {
        let r = make()
        #expect(r.header == .setupRequired)
        #expect(r.header.displayName == "Setup Required")
    }

    @Test("Header maps runtime failure → Runtime Error")
    func headerRuntimeError() {
        let r = make(selectedModelValid: true, acquisition: .installed, coordinatorState: .failed("x"),
                     microphone: .granted, accessibilityTrusted: true, hotkeyRegistration: .registered)
        #expect(r.header == .runtimeError)
        #expect(r.header.displayName == "Runtime Error")
    }
}