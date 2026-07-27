//
//  VoiceDockRuntimeComposition.swift
//  VoiceDock
//
//  VoiceDock 0.2 — Single runtime composition surface for the app.
//
//  VoiceDock is a native macOS menu bar application. In production it shares one
//  `ASRPreferenceStore` (`.production`) and one per-launch diagnostic recorder
//  (`ModelLaunchRecorder.shared`) across every component: AppDelegate,
//  ASRProviderFactory, Qwen3ASRProvider, ModelStatus, and the model picker. No
//  component below the composition root may reach for a different default store
//  or recorder directly.
//
//  The Xcode test bundle uses `VoiceDock.app` as its TEST_HOST. The host app's
//  `@main` (`@NSApplicationDelegateAdaptor(AppDelegate.self)`) constructs
//  `AppDelegate()` (the no-argument initializer) *before* any XCTest method can
//  inject dependencies. If the host AppDelegate ever bound itself to the
//  production preference suite and the shared per-launch recorder, the test
//  host would append rows to the owner's
//  `~/Library/Application Support/VoiceDock/Diagnostics/model-launch.jsonl`
//  and write the host process's selected model into the production
//  `com.voicedock.app.asr-prefs` UserDefaults domain.
//
//  This file is the single switch. The host AppDelegate's no-argument init, the
//  factory, and the provider resolve their preference store and per-launch
//  recorder through `VoiceDockRuntimeComposition.current`. The composition is
//  selected once, at process start, by `ProcessInfo.processInfo.environment`:
//
//    VOICEDOCK_TEST_MODE == "1"  →  isolated test-host composition
//      - a fresh `ASRPreferenceStore` suite namespaced by the process PID and a
//        one-time UUID, distinct from `com.voicedock.app.asr-prefs` and from
//        `UserDefaults.standard`;
//      - a `ModelLaunchRecorder` writing under `NSTemporaryDirectory()`, in a
//        directory namespaced by the same PID and UUID, never inside the
//        production diagnostics directory (the recorder's own hard path guard
//        still refuses that, defence in depth);
//      - the production `ModelLaunchRecorder.shared` singleton is never
//        referenced, never mutated, and never flushed from this path.
//
//    not set / any other value     →  production composition (`.production` and
//      `.shared`). The Release application that ships to the owner never sets
//      `VOICEDOCK_TEST_MODE`, so it cannot reach the test-host branch.
//
//  Tests do not infer test mode through XCTest class detection, NSClassFromString,
//  Bundle.module, or hosting-process introspection. The mode is the explicit
//  `VOICEDOCK_TEST_MODE` environment variable that the Xcode test action sets on
//  the TEST_HOST process before `AppDelegate.init()` runs. The composition is
//  read once and cached in a process-wide local, so repeated `current` lookups
//  return the same `preferenceStore` / `launchRecorder` pair for the entire host
//  process lifetime.
//
//  Direct `ModelLaunchRecorder.shared` references are allowed only in the
//  production composition root below and in a deliberate SwiftUI `#Preview`.
//

import Foundation
import os.log

private let compositionLogger = Logger(
    subsystem: "com.voicedock.core",
    category: "VoiceDockRuntimeComposition"
)

/// Environment variable name that selects the isolated test-host runtime
/// composition. The Xcode test action sets this to `"1"` on the TEST_HOST
/// process so the host `AppDelegate()` binds to a temporary, PID+UUID-namespaced
/// preference suite and per-launch recorder instead of the production singletons.
/// The shipping Release application never sets this variable.
public let VOICEDOCK_TEST_MODE_ENV = "VOICEDOCK_TEST_MODE"

/// Single runtime composition surface. Carries the two objects the model-selection
/// chain shares — a preference store and a per-launch diagnostic recorder — and
/// nothing else. Components resolve both through `VoiceDockRuntimeComposition.current`
/// rather than reaching for `ASRPreferenceStore.production` or
/// `ModelLaunchRecorder.shared` directly, so the test-host isolation switch has
/// exactly one place to act.
public struct VoiceDockRuntimeComposition: Sendable {
    /// The ASR-model preference store. Production: `.production` (the canonical
    /// `com.voicedock.app.asr-prefs` suite). Test host: an isolated UUID+PID
    /// suite under `VoiceDockTestHost-<pid>-<uuid>`.
    public let preferenceStore: ASRPreferenceStore

    /// The per-launch diagnostic recorder. Production: `ModelLaunchRecorder.shared`.
    /// Test host: an independent recorder writing under `NSTemporaryDirectory()`
    /// in a `VoiceDockTestHost-<pid>-<uuid>/Diagnostics` directory, never inside
    /// the canonical Application Support path.
    public let launchRecorder: ModelLaunchRecorder

    /// True iff this composition is the isolated test-host variant. Used by the
    /// deterministic host-isolation tests to assert the host bound itself away
    /// from production singletons.
    public let isTestHost: Bool

    /// Read-only path of the directory this composition's recorder writes its
    /// JSONL rows into. Surfaced so tests can assert the host's recorder
    /// directory is *not* the canonical production diagnostics directory and
    /// is inside `NSTemporaryDirectory()`.
    public var outputDirectoryForDiagnostics: String {
        launchRecorder.outputDirectoryForDiagnostics.path
    }

    /// Read-only suite name of this composition's preference store. Surfaced so
    /// tests can assert the host's suite is not the production
    /// `com.voicedock.app.asr-prefs` and is not the registration domain.
    public var suiteName: String {
        preferenceStore.suiteName
    }

    /// Production composition: the canonical preference suite and the shared
    /// per-launch recorder. Reached only when `VOICEDOCK_TEST_MODE` is not
    /// `"1"`. The reference to `.shared` lives here and nowhere else in the
    /// app/factory/provider/test paths.
    private static let production: VoiceDockRuntimeComposition = {
        VoiceDockRuntimeComposition(
            preferenceStore: .production,
            launchRecorder: .shared,
            isTestHost: false
        )
    }()

    /// Process-wide cached composition. Resolved exactly once on first access.
    /// `NSApplicationDelegateAdaptor` constructs `AppDelegate()` before any
    /// XCTest method runs, so the cache resolves during host launch (reading
    /// the Xcode test-action environment variable) and every later
    /// `current` lookup — from AppDelegate, the factory, the provider, or tests
    /// — returns the same pair.
    private static let currentComposition: VoiceDockRuntimeComposition = {
        resolve()
    }()

    /// Resolve the runtime composition from the environment, exactly once.
    /// Reading `ProcessInfo.processInfo.environment` here means the Xcode test
    /// action's `VOICEDOCK_TEST_MODE=1` (set on the TEST_HOST process before
    /// `@main` runs) selects the isolated branch. The shipping Release app
    /// never sets the variable, so it always resolves to production.
    private static func resolve() -> VoiceDockRuntimeComposition {
        let env = ProcessInfo.processInfo.environment
        let isTestHost = env[VOICEDOCK_TEST_MODE_ENV] == "1"
        if isTestHost {
            return makeTestHostComposition()
        }
        return production
    }

    /// Construct the isolated test-host composition. Both the preference suite
    /// and the recorder directory are namespaced by the running process's PID
    /// and a single per-process UUID, so two concurrent test-host processes (or
    /// two launches of the host app inside one `xcodebuild test`) never collide,
    /// and the suite and recorder for one host launch are trivially paired.
    private static func makeTestHostComposition() -> VoiceDockRuntimeComposition {
        let pid = ProcessInfo.processInfo.processIdentifier
        let uuid = UUID().uuidString
        let identity = "VoiceDockTestHost-\(pid)-\(uuid)"

        // Isolated preference suite: a unique name distinct from the production
        // suite and from UserDefaults.standard. Cleared to a deterministic
        // starting state so a host AppDelegate that reads the "saved" model
        // always sees Quality (the default), never a stray value from a prior
        // run or from the owner's production preferences.
        let suiteName = identity + ".asr-prefs"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            // A test-host process that cannot construct an isolated suite must
            // fail loudly rather than fall back to .standard or .production.
            compositionLogger.error("TestHost: failed to create isolated suite \(suiteName, privacy: .public); refusing to fall back to production")
            fatalError("VoiceDockRuntimeComposition: failed to create isolated test-host suite \(suiteName)")
        }
        defaults.dictionaryRepresentation().keys.forEach { defaults.removeObject(forKey: $0) }
        let preferenceStore = ASRPreferenceStore(suiteName: suiteName, defaults: defaults)

        // Isolated recorder directory under the system temporary directory, in
        // a per-host-launch namespaced folder. The recorder's own hard path
        // guard refuses any directory inside the canonical production
        // diagnostics path, so a misconfigured temp base cannot collide with
        // the owner's file.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(identity, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            compositionLogger.error("TestHost: failed to create isolated recorder dir \(base.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            fatalError("VoiceDockRuntimeComposition: failed to create isolated test-host recorder directory \(base.path): \(error.localizedDescription)")
        }

        // A single ISO-8601 timestamp captured once for the host process so the
        // recorder's row is deterministic per launch (the recorder would
        // otherwise stamp a fresh Date() itself; passing the same stamp keeps
        // the host's single row stable across the exactly-once finalizer).
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601 = formatter.string(from: Date())

        let execPath = Bundle.main.bundlePath + "/Contents/MacOS/"
            + (ProcessInfo.processInfo.processName.isEmpty ? "VoiceDock" : ProcessInfo.processInfo.processName)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.voicedock.test-host"

        let launchRecorder: ModelLaunchRecorder
        do {
            launchRecorder = try ModelLaunchRecorder(
                outputDir: base,
                pid: pid,
                executablePath: execPath,
                bundleIdentifier: bundleID,
                iso8601: iso8601
            )
        } catch {
            // The injectable init only throws `productionPathBlocked`. A temp
            // directory cannot be inside the production path, so this is a
            // genuine configuration error.
            compositionLogger.error("TestHost: recorder refused isolated dir \(base.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            fatalError("VoiceDockRuntimeComposition: test-host recorder refused the isolated directory \(base.path): \(error.localizedDescription)")
        }

        compositionLogger.info("TestHost composition resolved suite=\(suiteName, privacy: .public) recorderDir=\(base.path, privacy: .public) pid=\(pid)")
        return VoiceDockRuntimeComposition(
            preferenceStore: preferenceStore,
            launchRecorder: launchRecorder,
            isTestHost: true
        )
    }

    /// The process-wide runtime composition. Read once at first access (which,
    /// in the host app, is the no-argument `AppDelegate.init()` before any
    /// XCTest method runs) and cached for the process lifetime. Every component
    /// below resolves its preference store and per-launch recorder through
    /// this accessor instead of reaching for `ASRPreferenceStore.production` or
    /// `ModelLaunchRecorder.shared` directly.
    public static var current: VoiceDockRuntimeComposition {
        currentComposition
    }
}
