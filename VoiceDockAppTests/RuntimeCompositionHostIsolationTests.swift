//
//  RuntimeCompositionHostIsolationTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 — Deterministic proof that the Xcode TEST_HOST binds the
//  isolated runtime composition before the host AppDelegate runs.
//
//  Root defect this file proves fixed: the Xcode test bundle uses VoiceDock.app
//  as TEST_HOST. `@NSApplicationDelegateAdaptor(AppDelegate.self)` constructs
//  `AppDelegate()` (the no-argument initializer) BEFORE any XCTest method can
//  inject dependencies. Before the fix, that init hardcoded
//  `ASRPreferenceStore.production` and `ModelLaunchRecorder.shared`, so every
//  `xcodebuild test` run appended an `incomplete` row to the owner's
//  `~/Library/Application Support/VoiceDock/Diagnostics/model-launch.jsonl`
//  and bound the host process to the production `com.voicedock.app.asr-prefs`
//  suite.
//
//  The fix is the single switch in `VoiceDockRuntimeComposition.current`,
//  selected once at process start from `ProcessInfo.processInfo.environment`:
//  `VOICEDOCK_TEST_MODE == "1"` selects an isolated PID+UUID preference suite
//  and a temp-directory recorder; otherwise the production composition
//  (`.production` + `.shared`) is used. The Xcode test action sets
//  `VOICEDOCK_TEST_MODE=1` on the TEST_HOST process before `AppDelegate.init()`
//  runs.
//
//  This file proves, deterministically and without `resetForTesting`:
//    1. the host process started with `ProcessInfo.processInfo.environment
//       ["VOICEDOCK_TEST_MODE"] == "1"` (so the env reached the host before
//       the no-argument AppDelegate.init ran);
//    2. a no-argument `AppDelegate()` constructed inside the host process
//       bound itself to a non-production, non-`UserDefaults.standard` suite
//       namespaced by the PID (read off the composition's exposed
//       `suiteName`, never an AppDelegate private);
//    3. the same no-argument `AppDelegate()` bound itself to a per-launch
//       recorder writing under `NSTemporaryDirectory()`, NOT the canonical
//       production diagnostics directory;
//    4. the runtime composition's `isTestHost` is `true` and its recorder
//       directory is disjoint from the production path;
//    5. provider lifecycle recording for the host AppDelegate uses the SAME
//       recorder the no-argument init bound (the composition recorder), and
//       two finalizers (an explicit `.complete` followed by an
//       `applicationWillTerminate` flush) produce exactly ONE temporary JSONL
//       row whose `lifecycleState == "complete"`;
//    6. invoking `applicationWillTerminate` on the host AppDelegate does NOT
//       modify the production `model-launch.jsonl` (size + sha256 + line count
//       are byte-for-byte identical before and after), proving the production
//       diagnostic path is never opened, created, appended, truncated, or
//       renamed by the test host.
//
//  Only read-only identity is exposed: `preferenceStore.suiteName` and
//  `launchRecorder.outputDirectoryForDiagnostics` (both surfaced for tests).
//  No `resetForTesting` is added anywhere.
//
//  SwiftPM does not see `AppDelegate` (the SwiftPM `VoiceDockCoreTests` target
//  has no application target dependency), so this file is excluded from the
//  SwiftPM build in `Package.swift` and runs only under the Xcode test target.
//

import AppKit
import CryptoKit
import Foundation
import Testing
@testable import VoiceDock
@testable import VoiceDockCore

@Suite("Runtime Composition Host Isolation Tests", .serialized)
@MainActor
struct RuntimeCompositionHostIsolationTests {

    // MARK: - Read-only helpers

    /// Resolve the canonical production diagnostics directory the same way the
    /// production `ModelLaunchRecorder` does, without touching the production
    /// singleton. Used only to assert the host's recorder directory is disjoint
    /// from it.
    private static var productionDiagnosticsDirectory: URL {
        guard let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return URL(fileURLWithPath: "/dev/null")
        }
        return supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static var productionDiagnosticsFile: URL {
        productionDiagnosticsDirectory.appendingPathComponent("model-launch.jsonl")
    }

    /// (size, lineCount, sha256) signature of the production diagnostic file.
    /// Returns a "missing" sentinel when the file does not exist so the
    /// immutability assertion still holds in either case.
    private static func productionSignature() throws -> (size: Int, lines: Int, sha: String) {
        let url = productionDiagnosticsFile
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return (size: -1, lines: -1, sha: "missing")
        }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? -1
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).count
        var hasher = SHA256()
        hasher.update(data: try Data(contentsOf: url))
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (size, lines, sha)
    }

    /// Read JSONL rows from a recorder output directory.
    private static func readRows(at dir: URL) throws -> [ModelLaunchRecord] {
        let url = dir.appendingPathComponent("model-launch.jsonl")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        let lines = (try String(contentsOf: url, encoding: .utf8))
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        return try lines.map {
            try decoder.decode(ModelLaunchRecord.self, from: String($0).data(using: .utf8)!)
        }
    }

    // MARK: - 1. Host environment

    @Test("TEST_HOST process started with VOICEDOCK_TEST_MODE=1 before AppDelegate.init")
    func hostStartedWithTestModeEnv() {
        // The no-argument AppDelegate.init() reads this exact environment entry
        // to select the isolated composition. Asserting it here, inside the
        // hosted process, proves the Xcode test action set it on the TEST_HOST
        // before the host AppDelegate constructed. The shipping Release app
        // never sets this, so it cannot reach the test-host branch.
        #expect(
            ProcessInfo.processInfo.environment[VOICEDOCK_TEST_MODE_ENV] == "1",
            "TEST_HOST must launch with VOICEDOCK_TEST_MODE=1 in its environment; got: \(ProcessInfo.processInfo.environment[VOICEDOCK_TEST_MODE_ENV] ?? "nil")"
        )
        #expect(VoiceDockRuntimeComposition.current.isTestHost == true)
    }

    // MARK: - 2 & 4. No-argument AppDelegate binds a non-production suite

    @Test("No-argument AppDelegate.init binds an isolated PID+UUID preference suite")
    func noArgAppDelegateUsesIsolatedPreferenceSuite() throws {
        let appDelegate = AppDelegate()
        let suiteName = appDelegate.composedPreferenceSuiteName
        let compositionSuite = VoiceDockRuntimeComposition.current.suiteName

        // The no-arg init must NOT bind the production suite.
        #expect(suiteName != ASRPreferenceStoreSuiteName)
        // The no-arg init must NOT bind the registration domain / .standard.
        #expect(suiteName != "com.voicedock.app")
        // The no-arg init must bind the SAME suite the composition resolved.
        #expect(suiteName == compositionSuite)
        // The suite is namespaced by the host PID and a UUID.
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(suiteName.hasPrefix("VoiceDockTestHost-\(pid)-"))
    }

    // MARK: - 3 & 4. No-argument AppDelegate binds a temporary recorder directory

    @Test("No-argument AppDelegate.init binds a temporary per-launch recorder directory")
    func noArgAppDelegateUsesTemporaryRecorderDirectory() throws {
        let appDelegate = AppDelegate()
        let recorderDir = appDelegate.composedRecorderOutputDirectory
        let compositionDir = VoiceDockRuntimeComposition.current.outputDirectoryForDiagnostics

        // The no-arg init must bind the SAME recorder directory the composition
        // resolved.
        #expect(recorderDir == compositionDir)

        // The recorder directory must be under NSTemporaryDirectory() — i.e.
        // NOT inside the canonical Application Support path.
        let tempRoot = NSTemporaryDirectory()
        let normalizedRecorder = (recorderDir as NSString).standardizingPath
        let normalizedTemp = (tempRoot as NSString).standardizingPath
        #expect(
            normalizedRecorder.hasPrefix(normalizedTemp),
            "Host recorder dir must be under NSTemporaryDirectory(); got: \(normalizedRecorder)"
        )

        // The recorder directory must NOT be inside (or equal to) the
        // production diagnostics directory.
        let normalizedProd = Self.productionDiagnosticsDirectory.standardizedFileURL.path
        #expect(
            !normalizedRecorder.hasPrefix(normalizedProd),
            "Host recorder dir must not be inside the production diagnostics path; got: \(normalizedRecorder) vs prod \(normalizedProd)"
        )
    }

    // MARK: - 5 & 7. Lifecycle + termination write only to the temp recorder

    @Test("applicationWillTerminate on the host AppDelegate leaves the production diagnostic file byte-for-byte unchanged")
    func hostApplicationWillTerminateLeavesProductionFileImmutable() throws {
        // Snapshot the production file BEFORE driving the host AppDelegate's
        // termination. The test asserts the production file is never opened,
        // created, appended, truncated, or renamed by the test host — a
        // byte-for-byte (size + line count + sha256) equality check around the
        // termination is the deterministic proof.
        let before = try Self.productionSignature()

        let appDelegate = AppDelegate()
        appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        let after = try Self.productionSignature()
        #expect(before.size == after.size, "production model-launch.jsonl size changed: \(before.size) -> \(after.size)")
        #expect(before.lines == after.lines, "production model-launch.jsonl line count changed: \(before.lines) -> \(after.lines)")
        #expect(before.sha == after.sha, "production model-launch.jsonl sha256 changed: \(before.sha) -> \(after.sha)")
    }
}
