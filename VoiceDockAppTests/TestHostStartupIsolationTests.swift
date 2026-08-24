//
//  TestHostStartupIsolationTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 RC1 — Test-host model-resource isolation regression tests.
//
//  Proven defect (see audit at f797ccdc): the TEST_HOST's
//  applicationDidFinishLaunching → fullInitialize → makeCoordinator chain
//  constructed a real Qwen3ASRProvider against production ModelStorage,
//  loading ~1.5 GB of the owner's model weights and running a real MLX
//  warmup inside every `xcodebuild test` run (~37 minutes total), with
//  tokenizer-artifact writes possible in the production model directory.
//
//  The fix: fullInitialize returns before makeCoordinator when
//  VoiceDockRuntimeComposition.current.isTestHost is true.
//
//  These tests prove, inside the hosted process:
//    1. the composition selected by the no-argument AppDelegate init is the
//       test-host variant (so the guard is active in this exact process);
//    2. a no-argument AppDelegate created here has NO coordinator wired by
//       host startup (the production coordinator creation count is zero);
//    3. the guard is observable: /tmp/voicedock-ui-diagnostics.log contains
//       the host's "fullInitialize_skipped_test_host" marker once startup has
//       run — removing or weakening the guard makes this fail.
//

import AppKit
import Foundation
import Testing
@testable import VoiceDock
@testable import VoiceDockCore

@Suite("Test Host Startup Isolation", .serialized)
@MainActor
struct TestHostStartupIsolationTests {

    @Test("Host AppDelegate composes the test-host runtime composition")
    func hostAppDelegateComposesTestHostComposition() throws {
        let appDelegate = AppDelegate()

        #expect(VoiceDockRuntimeComposition.current.isTestHost == true,
                "These tests only assert behavior inside the Xcode TEST_HOST")
        #expect(appDelegate.composedPreferenceSuiteName.hasPrefix("VoiceDockTestHost-"))
        let tempRoot = (NSTemporaryDirectory() as NSString).standardizingPath
        let recorderDir = (appDelegate.composedRecorderOutputDirectory as NSString).standardizingPath
        #expect(recorderDir.hasPrefix(tempRoot),
                "Host recorder must stay under NSTemporaryDirectory(); got \(recorderDir)")
    }

    @Test("Host startup does not create a production coordinator/provider (count == 0)")
    func hostStartupCreatesNoProductionCoordinator() async throws {
        // Drive the same scheduled startup path applicationDidFinishLaunching
        // uses, on this instance. With the guard in place it must return
        // before makeCoordinator() constructs AudioCapture, the provider, or
        // the SessionCoordinator.
        let appDelegate = AppDelegate()
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification, object: nil)
        )

        // Allow the asyncAfter(+0.1) scheduled fullInitialize to fire.
        try await Task.sleep(nanoseconds: 400_000_000)

        // The observable invariant: host-startup coordinator creation count == 0.
        // The coordinator is private to AppDelegate; its absence is proven by
        // the public diagnostic marker the guard writes instead of wiring.
        let log = try String(contentsOfFile: "/tmp/voicedock-ui-diagnostics.log", encoding: .utf8)
        #expect(log.contains("fullInitialize_skipped_test_host"),
                "TEST_HOST guard did not run; host startup attempted production initialization")
        #expect(log.contains("makeCoordinator_start") == false,
                "makeCoordinator ran inside TEST_HOST; production provider would be constructed")
    }
}
