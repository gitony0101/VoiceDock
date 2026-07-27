//
//  AppDelegateTestSupport.swift
//  VoiceDockAppTests/TestSupport
//
//  VoiceDock 0.2 — Helper for assembling an isolated `AppDelegate` for tests
//  in the Xcode `VoiceDockTests` target.
//
//  SwiftPM's `VoiceDockCoreTests` target cannot see `VoiceDock.AppDelegate`
//  (the app target does not exist as a SwiftPM product), so ApplePlatform
//  tests for AppDelegate live in the Xcode test bundle only. This file is
//  excluded from the SwiftPM build via `Package.swift`.
//

import AppKit
import Foundation
@testable import VoiceDock
@testable import VoiceDockCore

/// Helper for assembling an isolated `AppDelegate` for tests. Returns the
/// delegate, the isolated `ASRPreferenceStore` it was bound to, and the
/// injectable recorder it was bound to. Tests that previously wrote to
/// `AppDelegate()` with production defaults must use this helper so the
/// production preference suite, the `ModelLaunchRecorder.shared` singleton,
/// and the owner's `~/Library/Application Support/VoiceDock/Diagnostics`
/// file are never touched from the test process.
///
/// The helper pairs a fresh temporary recorder directory under
/// `NSTemporaryDirectory()/VoiceDockTests/Diagnostics/<UUID>` with the
/// injectable `ModelLaunchRecorder.init(outputDir:pid:...)`. The recorder
/// hard-refuses any path inside the production diagnostics directory, so even
/// a misconfigured path cannot collide with the owner's file.
@MainActor
public enum AppDelegateTestSupport {
    public struct IsolatedBundle {
        public let appDelegate: AppDelegate
        public let preferenceStore: ASRPreferenceStore
        public let recorder: ModelLaunchRecorder
        public let recorderDir: URL
    }

    /// Build an isolated AppDelegate for one test invocation.
    public static func makeIsolatedAppDelegate() throws -> IsolatedBundle {
        let store = ASRPreferenceStore.isolate()
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoiceDockTests", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let recorder = try ModelLaunchRecorder(
            outputDir: base,
            pid: Int32.random(in: 100_000...999_999),
            executablePath: "/tmp/VoiceDock.tests",
            bundleIdentifier: "com.voicedock.tests.appext",
            iso8601: "2026-07-25T00:00:00Z"
        )
        let delegate = AppDelegate(preferenceStore: store, launchRecorder: recorder)
        return IsolatedBundle(
            appDelegate: delegate,
            preferenceStore: store,
            recorder: recorder,
            recorderDir: base
        )
    }

    /// Remove a previously created isolated recorder directory. Safe to call
    /// from `defer` blocks even when the directory does not exist.
    public static func cleanup(_ bundle: IsolatedBundle) {
        try? FileManager.default.removeItem(at: bundle.recorderDir)
    }
}
