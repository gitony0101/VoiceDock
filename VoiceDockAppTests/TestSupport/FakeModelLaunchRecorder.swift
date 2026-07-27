//
//  FakeModelLaunchRecorder.swift
//  VoiceDockAppTests/TestSupport
//
//  VoiceDock 0.2 — Shared test-only recorder for `ModelStatus`.
//
//  This file is in the test-support directory shared by SwiftPM
//  (`VoiceDockCoreTests`) and Xcode (`VoiceDockTests`). Production never
//  imports it; the production framework (`VoiceDockCore`) only sees the
//  `ModelLaunchDiagnosticRecording` protocol.
//

import Foundation
@testable import VoiceDockCore

/// In-memory recorder conforming to `ModelLaunchDiagnosticRecording` for use
/// in `ModelStatus` unit tests. Stores only what the protocol records; never
/// writes to disk and never references `ModelLaunchRecorder.shared`. A test
/// that needs to assert a duplicate-capture attempt reached the recorder reads
/// `duplicateCaptureAttempts`; a test that needs to prove the production
/// recorder stayed untouched inspects `ModelLaunchRecorder.shared` independently.
public final class FakeModelLaunchRecorder: ModelLaunchDiagnosticRecording {
    public private(set) var preferenceSuiteNames: [String] = []
    public private(set) var preferenceRawSelectedModels: [String?] = []
    public private(set) var modelStatusInitSelected: [ASRModelSelection] = []
    public private(set) var modelStatusInitEffective: [ASRModelSelection?] = []
    public private(set) var duplicateCaptureAttempts: [(attempted: ASRModelSelection, existing: ASRModelSelection?)] = []

    public init() {}

    public func recordPreferenceState(suiteName: String, rawSelectedModel: String?) {
        preferenceSuiteNames.append(suiteName)
        preferenceRawSelectedModels.append(rawSelectedModel)
    }

    public func recordModelStatusInit(selected: ASRModelSelection, effective: ASRModelSelection?) {
        modelStatusInitSelected.append(selected)
        modelStatusInitEffective.append(effective)
    }

    public func recordDuplicateCaptureActive(
        attemptedSelection: ASRModelSelection,
        existingActive: ASRModelSelection?
    ) {
        duplicateCaptureAttempts.append((attempted: attemptedSelection, existing: existingActive))
    }
}
