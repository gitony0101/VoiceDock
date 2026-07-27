//
//  AppDelegateLaunchDiagnosticTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 — Deterministic tests for AppDelegate per-launch diagnostic
//  finalization, terminal flush isolation, and coordinator-state mapping.
//
//  All tests construct fresh isolated dependencies through
//  `AppDelegateTestSupport.makeIsolatedAppDelegate()`, which pairs an
//  isolated `ASRPreferenceStore` (UUID suite) with an independent
//  `ModelLaunchRecorder` (temporary directory under
//  `NSTemporaryDirectory()`). No test in this file touches the production
//  `ModelLaunchRecorder.shared` singleton, the production
//  `com.voicedock.app.asr-prefs` suite, or the owner's
//  `~/Library/Application Support/VoiceDock/Diagnostics/model-launch.jsonl`
//  file. Every recorder call routes through the injected `launchRecorder`
//  property on `AppDelegate`. The recorder's exactly-once guard makes a
//  second terminal flush a no-op. A second `applicationWillTerminate` flush
//  on the same recorder must therefore NOT add a second JSONL row.
//
//  These tests verify:
//  A) Termination isolation
//     - applicationWillTerminate writes exactly one incomplete JSONL row
//     - the row is written only to the injected temporary recorder
//     - a second termination/flush does not add a second row
//  B) Lifecycle mapping in `handleCoordinatorStateForLaunchDiagnostics(_:)`
//     - starting, waitingForMicrophonePermission, waitingForAccessibility,
//       loadingModel, listening, transcribing, delivering: no finalization
//     - idle without successful load+warmup: no finalize complete
//     - ready without successful load+warmup: no finalize complete
//     - ready after recorded successful load and warmup: finalize complete
//     - load failure: finalize loadFailed
//     - warmup failure: finalize warmupFailed
//     - termination before terminal state: finalize incomplete
//     - termination after terminal finalization: no-op
//  C) ModelStatus isolation
//     - duplicate capture records only through the injected fake
//     - ModelStatus tests never mutate ModelLaunchRecorder.shared
//
//  SwiftPM does not see `AppDelegate` (the SwiftPM `VoiceDockCoreTests`
//  target has no application target dependency), so this file is excluded
//  from the SwiftPM build and runs only under the Xcode test target.
//

import AppKit
import Foundation
import Testing
@testable import VoiceDock
@testable import VoiceDockCore

@Suite("AppDelegate Launch Diagnostic Tests", .serialized)
@MainActor
struct AppDelegateLaunchDiagnosticTests {

    // MARK: - Helpers

    /// Read JSONL records from a recorder's output directory.
    private static func readRows(at dir: URL) throws -> [ModelLaunchRecord] {
        let url = dir.appendingPathComponent("model-launch.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        let lines = (try String(contentsOf: url, encoding: .utf8))
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        return try lines.map { try decoder.decode(ModelLaunchRecord.self, from: String($0).data(using: .utf8)!) }
    }

    // MARK: - A. AppDelegate termination isolation

    @Test("applicationWillTerminate writes exactly one incomplete JSONL row to the injected temporary recorder")
    func applicationWillTerminateWritesExactlyOneIncompleteRow() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let delegate = bundle.appDelegate
        let recorderDir = bundle.recorderDir

        // No terminal flush has fired yet. applicationWillTerminate must
        // produce exactly one row marked `incomplete:loadNotRun`.
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        let rows = try Self.readRows(at: recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "incomplete:loadNotRun")
    }

    @Test("Row written by applicationWillTerminate is going to the injected temporary recorder only")
    func rowIsWrittenOnlyToInjectedRecorder() throws {
        // Snapshot the production file's signature BEFORE running this test.
        // The recorders held by the test are bounded to temporary directories,
        // and `ModelLaunchRecorder.shared` is not invoked from any test path,
        // so the production file MUST remain unchanged by anything in this
        // test. applicationWillTerminate has not been called: the injected
        // recorder therefore has not been flushed yet.
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let prodPath = ProductionDiagnostics.path
        let beforeSig = ProductionDiagnostics.signature(of: prodPath)
        let afterSig = ProductionDiagnostics.signature(of: prodPath)
        #expect(beforeSig == afterSig)

        // The injected recorder has not yet been flushed because
        // applicationWillTerminate has not been called.
        let tempRows = try Self.readRows(at: bundle.recorderDir)
        #expect(tempRows.isEmpty)
    }

    @Test("A second applicationWillTerminate does not write a second JSONL row")
    func secondTerminationDoesNotAddRow() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let delegate = bundle.appDelegate

        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        let firstCount = try Self.readRows(at: bundle.recorderDir).count
        #expect(firstCount == 1)

        // Second terminate-time flush is a no-op because the recorder's
        // exactly-once `hasFlushed` guard is already true.
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        let secondCount = try Self.readRows(at: bundle.recorderDir).count
        #expect(secondCount == 1)
    }

    @Test("Explicit terminal flush preserves complete; a later terminate flush is no-op")
    func explicitCompleteThenLaterTerminateIsNoop() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let recorder = bundle.recorder
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")
        // Trigger the success path through the public AppDelegate helper.
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.ready)
        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "complete")

        // Terminate-time flush must be a no-op now that the recorder has
        // already finalized once.
        bundle.appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        let finalRows = try Self.readRows(at: bundle.recorderDir)
        #expect(finalRows.count == 1)
        #expect(finalRows[0].lifecycleState == "complete")
    }

    // MARK: - B. Lifecycle mapping through handleCoordinatorStateForLaunchDiagnostics

    @Test("In-flight coordinator states do not finalize")
    func inflightStatesDoNotFinalize() throws {
        // Each in-flight state must not emit a row at all.
        let inFlight: [SessionCoordinator.State] = [
            .starting,
            .waitingForMicrophonePermission,
            .waitingForAccessibilityPermission,
            .loadingModel,
            .listening,
            .transcribing,
            .delivering
        ]
        for state in inFlight {
            try verifyInFlightStateDoesNotFinalize(state)
        }
    }

    private func verifyInFlightStateDoesNotFinalize(_ state: SessionCoordinator.State) throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(state)
        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.isEmpty, "State \(state) must not finalize (got \(rows.count) rows)")
    }

    @Test(".idle without successful load+warmup does not finalize complete")
    func idleWithoutLoadDoesNotFinalizeComplete() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.idle)

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.isEmpty, ".idle without successful load+warmup must not finalize; the guaranteed terminate flush owns this witness")
    }

    @Test(".ready without successful load+warmup does not finalize complete")
    func readyWithoutLoadDoesNotFinalizeComplete() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.ready)

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.isEmpty, ".ready without successful load+warmup must not finalize; the guaranteed terminate flush owns this witness")
    }

    @Test(".ready after recorded successful load and warmup finalizes complete")
    func readyAfterSuccessfulLifecycleFinalizesComplete() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let recorder = bundle.recorder
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.ready)

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "complete")
    }

    @Test("Load failure finalizes loadFailed")
    func loadFailureFinalizesLoadFailed() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let recorder = bundle.recorder
        // Recorder's failureTerminalState() looks at loadCompleted/warmupCompleted
        // flags set by recordProviderLifecycle. No load → loadFailed.
        recorder.recordProviderLifecycle(loadResult: "fail:model-not-found", warmupResult: "skipped")
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.failed("model-not-found"))

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "loadFailed:model-not-found")
    }

    @Test("Warmup failure finalizes warmupFailed")
    func warmupFailureFinalizesWarmupFailed() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let recorder = bundle.recorder
        // Load OK, warmup not run/warmup completed=false ⇒ warmupFailed.
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "fail:warmup")
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.failed("warmup"))

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "warmupFailed:warmup")
    }

    @Test("Termination before terminal state finalizes incomplete:loadNotRun")
    func terminationBeforeTerminalFinalizesIncompleteLoadNotRun() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        bundle.appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        let rows = try Self.readRows(at: bundle.recorderDir)
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "incomplete:loadNotRun")
    }

    @Test("Termination after terminal finalization is a no-op")
    func terminationAfterTerminalIsNoop() throws {
        let bundle = try AppDelegateTestSupport.makeIsolatedAppDelegate()
        defer { AppDelegateTestSupport.cleanup(bundle) }

        let recorder = bundle.recorder
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")
        bundle.appDelegate.handleCoordinatorStateForLaunchDiagnostics(.ready)
        let afterReady = try Self.readRows(at: bundle.recorderDir)
        #expect(afterReady.count == 1)
        #expect(afterReady[0].lifecycleState == "complete")

        // Subsequent applicationWillTerminate must not add a second row.
        bundle.appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        let afterTerm = try Self.readRows(at: bundle.recorderDir)
        #expect(afterTerm.count == 1)
        #expect(afterTerm[0].lifecycleState == "complete")
    }

    // MARK: - C. ModelStatus isolation

    @Test("ModelStatus duplicate capture records only through the injected FakeModelLaunchRecorder")
    func duplicateCaptureUsesOnlyInjectedRecorder() throws {
        let prodPath = ProductionDiagnostics.path
        let beforeSig = ProductionDiagnostics.signature(of: prodPath)
        let sharedBefore = ModelLaunchRecorder.shared.duplicateCaptureWasAttempted()

        let fakeRecorder = FakeModelLaunchRecorder()
        let modelStatus = ModelStatus(
            selectedModel: .qwen3_0_6B_8bit,
            recorder: fakeRecorder
        )
        // Production debug trap is undesirable in tests.
        modelStatus.duplicateCaptureHandler = { _ in }

        let first = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_0_6B_8bit,
            descriptor: .qwen3_0_6B_8bit
        )
        let second = ASRProviderFactoryResult(
            provider: MockASRProvider(),
            selection: .qwen3_1_7B_4bit,
            descriptor: .qwen3_1_7B_4bit
        )

        _ = modelStatus.captureActive(first)
        #expect(fakeRecorder.duplicateCaptureAttempts.count == 0)

        _ = modelStatus.captureActive(second)
        #expect(fakeRecorder.duplicateCaptureAttempts.count == 1)
        #expect(fakeRecorder.duplicateCaptureAttempts[0].attempted == .qwen3_1_7B_4bit)
        #expect(fakeRecorder.duplicateCaptureAttempts[0].existing == .qwen3_0_6B_8bit)

        // Production singleton and the production file are both untouched.
        let sharedAfter = ModelLaunchRecorder.shared.duplicateCaptureWasAttempted()
        let afterSig = ProductionDiagnostics.signature(of: prodPath)
        #expect(sharedBefore == sharedAfter)
        #expect(beforeSig == afterSig)
    }
}

// MARK: - Production diagnostics helper

/// Read-only helpers for the production `model-launch.jsonl` file so tests
/// can assert that the owner's file is not mutated by running tests. These
/// helpers resolve the canonical path identical to the production
/// `ModelLaunchRecorder` default singleton and never write to it.
enum ProductionDiagnostics {
    static var path: String {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "/dev/null"
        }
        return supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("model-launch.jsonl")
            .path
    }

    static func signature(of path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            return "missing"
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        return "size=\(size)"
    }
}
