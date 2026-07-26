//
//  ModelLaunchRecorderTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.2 — Deterministic tests for the per-launch recorder.
//
//  Each test constructs an INDEPENDENT recorder via the injectable init
//  pointing at a temporary output directory (under NSTemporaryDirectory),
//  with a synthetic PID/executable/bundle identity and an injected ISO
//  timestamp. Tests never touch the production `~/Library/Application
//  Support/VoiceDock/Diagnostics` file: a hard path guard inside the
//  injectable init refuses any output dir underneath that path, and a test
//  below asserts the guard.
//

import Testing
import Foundation
@testable import VoiceDockCore

@Suite("Model Launch Recorder Tests")
struct ModelLaunchRecorderTests {

    /// A fresh temporary directory per test instance, removed afterward.
    private func makeTempDir() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoiceDockRecorderTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("Complete lifecycle writes exactly one row marked complete")
    func completeWritesOneCompleteRow() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4242,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        recorder.recordPreferenceState(suiteName: "VoiceDockTests.X", rawSelectedModel: "qwen3-0.6b-8bit")
        recorder.recordModelStatusInit(selected: .qwen3_0_6B_8bit, effective: nil)
        recorder.recordFactoryResult(selection: .qwen3_0_6B_8bit, descriptorRepoID: "repo/fast", resolvedModelDirectory: "/tmp/m", activeAfterCapture: .qwen3_0_6B_8bit)
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")

        recorder.finalizeAndFlush(.complete)
        // second finalizer is a no-op
        recorder.finalizeAndFlush(.incomplete)
        recorder.flush()

        #expect(recorder.hasFinalized() == true)

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        let row = rows[0]
        #expect(row.pid == 4242)
        #expect(row.bundleIdentifier == "com.voicedock.test")
        #expect(row.executablePath == "/tmp/VoiceDock")
        #expect(row.preferenceSuiteName == "VoiceDockTests.X")
        #expect(row.persistedRawSelectedModel == "qwen3-0.6b-8bit")
        #expect(row.modelStatusSelectedAfterInit == "qwen3-0.6b-8bit")
        #expect(row.modelStatusEffectiveBeforeProvider == "notCreated")
        #expect(row.factorySelection == "qwen3-0.6b-8bit")
        #expect(row.factoryDescriptorRepoID == "repo/fast")
        #expect(row.modelStatusActiveAfterCapture == "qwen3-0.6b-8bit")
        #expect(row.providerLoadResult == "ok:/tmp/m")
        #expect(row.providerWarmupResult == "ok")
        #expect(row.lifecycleState == "complete")
    }

    @Test("Load failure finalizes as loadFailed")
    func loadFailedRow() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4243,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        recorder.recordProviderLifecycle(loadResult: "fail:model-not-found", warmupResult: "skipped")
        recorder.finalizeAndFlush(.loadFailed, reason: "model-not-found")

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "loadFailed:model-not-found")
    }

    @Test("Warmup failure finalizes as warmupFailed")
    func warmupFailedRow() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4244,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "skipped:no-model")
        recorder.finalizeAndFlush(.warmupFailed, reason: "no-model")

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "warmupFailed:no-model")
    }

    @Test("Terminate before any lifecycle finalizes as incomplete:loadNotRun")
    func incompleteLoadNotRunRow() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4245,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        // No provider lifecycle recorded; terminate-time flush path.
        recorder.flush()

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "incomplete:loadNotRun")
    }

    @Test("Duplicate captureAttempted overrides lifecycle state")
    func duplicateCaptureAttemptOverridesLifecycle() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4246,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        recorder.recordDuplicateCaptureActive(attemptedSelection: .qwen3_1_7B_4bit, existingActive: .qwen3_0_6B_8bit)
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")
        recorder.finalizeAndFlush(.complete)

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        // duplicateCaptureAttempted wins over .complete
        #expect(rows[0].lifecycleState == "duplicateCaptureAttempted")
    }

    @Test("Explicit complete beats a later incomplete flush (exactly-once, no lost success)")
    func exactOnceDoesNotLoseSuccess() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = try ModelLaunchRecorder(
            outputDir: dir,
            pid: 4247,
            executablePath: "/tmp/VoiceDock",
            bundleIdentifier: "com.voicedock.test",
            iso8601: "2026-07-25T00:00:00Z"
        )
        recorder.recordProviderLifecycle(loadResult: "ok:/tmp/m", warmupResult: "ok")
        recorder.finalizeAndFlush(.complete)             // success flush fires first
        recorder.finalizeAndFlush(.incomplete)          // later terminate flush is a no-op
        recorder.flush()

        let rows = try Self.readRows(at: dir.appendingPathComponent("model-launch.jsonl"))
        #expect(rows.count == 1)
        #expect(rows[0].lifecycleState == "complete")
    }

    @Test("Hard path guard refuses a recorder bound to the production diagnostics dir")
    func productionPathGuardRefuses() throws {
        let prodDiag = ModelLaunchRecorder.shared
        // The production diagnostics directory path is private; reach it via
        // the canonical location the recorder writes to. We construct a URL
        // directly underneath the owner's support directory. A test that
        // attempts this MUST be refused.
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Issue.record("Application Support unavailable")
            return
        }
        let underneath = supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)

        #expect(throws: ModelLaunchRecorderError.self) {
            // The injectable init hard-refuses a recorder bound to the
            // production diagnostics directory; the throwable error (rather
            // than a precondition/fatalError) keeps the test process alive.
            _ = try ModelLaunchRecorder(
                outputDir: underneath,
                pid: 4248,
                executablePath: "/tmp/VoiceDock",
                bundleIdentifier: "com.voicedock.test",
                iso8601: "2026-07-25T00:00:00Z"
            )
        }
        // silence "unused" of the shared instance above; it proves the
        // production singleton still exists.
        _ = prodDiag
    }
}

private extension ModelLaunchRecorderTests {
    static func readRows(at url: URL) throws -> [ModelLaunchRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let decoder = JSONDecoder()
        let lines = (try String(contentsOf: url, encoding: .utf8))
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        return try lines.map { try decoder.decode(ModelLaunchRecord.self, from: String($0).data(using: .utf8)!) }
    }
}
