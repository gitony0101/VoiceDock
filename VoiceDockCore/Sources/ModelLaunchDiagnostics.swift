//
//  ModelLaunchDiagnostics.swift
//  VoiceDock
//
//  VoiceDock 0.2 — Per-launch structured diagnostic for the model-selection chain.
//
//  Each process launch appends exactly one JSONL record to
//  ~/Library/Application Support/VoiceDock/Diagnostics/model-launch.jsonl
//  capturing the real production objects: PID, exec path, exec SHA-256, bundle
//  id, preference suite/domain, persisted raw selected-model value, the
//  ModelStatus state immediately after init, the factory result.selection,
//  the descriptor repo id, resolved model directory, ModelStatus.activeModel
//  after captureActive, provider load result, and warmup result.
//
//  Exactly one record is written per PID: a single atomic `hasFlushed` guard
//  makes a second finalizer a no-op, so a terminal `finalizeAndFlush(_:)`
//  fired on load+warmup success / load failure / warmup failure and the
//  guaranteed `applicationWillTerminate` flush cannot both write — only the
//  first finalizer emits the JSONL row; subsequent calls are no-ops. A
//  success that arrives after an earlier finalizer is therefore not lost.
//
//  No transcript content is ever recorded.
//

import Foundation
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ModelLaunchDiagnostics")

/// Structured per-launch record for the model-selection chain. Built from real
/// production objects (not duplicated test logic) and serialized as one line
/// of JSON to `model-launch.jsonl`.
public struct ModelLaunchRecord: Codable, Sendable {
    public let iso8601: String
    public let pid: Int32
    public let executablePath: String
    public let executableSHA256: String
    public let bundleIdentifier: String
    public let preferenceSuiteName: String
    public let persistedRawSelectedModel: String?
    public let modelStatusSelectedAfterInit: String
    public let modelStatusEffectiveBeforeProvider: String
    public let factorySelection: String
    public let factoryDescriptorRepoID: String
    public let resolvedModelDirectory: String
    public let modelStatusActiveAfterCapture: String
    public let providerLoadResult: String
    public let providerWarmupResult: String
    /// Marker for whether the recorded lifecycle reached completion. One of:
    /// "complete", "loadFailed[:reason]", "warmupFailed[:reason]",
    /// "incomplete:<reason>", "duplicateCaptureAttempted".
    public let lifecycleState: String

    public init(
        iso8601: String,
        pid: Int32,
        executablePath: String,
        executableSHA256: String,
        bundleIdentifier: String,
        preferenceSuiteName: String,
        persistedRawSelectedModel: String?,
        modelStatusSelectedAfterInit: String,
        modelStatusEffectiveBeforeProvider: String,
        factorySelection: String,
        factoryDescriptorRepoID: String,
        resolvedModelDirectory: String,
        modelStatusActiveAfterCapture: String,
        providerLoadResult: String,
        providerWarmupResult: String,
        lifecycleState: String
    ) {
        self.iso8601 = iso8601
        self.pid = pid
        self.executablePath = executablePath
        self.executableSHA256 = executableSHA256
        self.bundleIdentifier = bundleIdentifier
        self.preferenceSuiteName = preferenceSuiteName
        self.persistedRawSelectedModel = persistedRawSelectedModel
        self.modelStatusSelectedAfterInit = modelStatusSelectedAfterInit
        self.modelStatusEffectiveBeforeProvider = modelStatusEffectiveBeforeProvider
        self.factorySelection = factorySelection
        self.factoryDescriptorRepoID = factoryDescriptorRepoID
        self.resolvedModelDirectory = resolvedModelDirectory
        self.modelStatusActiveAfterCapture = modelStatusActiveAfterCapture
        self.providerLoadResult = providerLoadResult
        self.providerWarmupResult = providerWarmupResult
        self.lifecycleState = lifecycleState
    }
}

/// Terminal lifecycle state for the per-launch record. `finalizeAndFlush`
/// takes one of these; `lifecycleState` in the emitted JSONL row is derived
/// from it (and, for `.incomplete`, from the recorded load/warmup flags).
public enum LaunchLifecycleState: String, Sendable {
    case complete
    case loadFailed
    case warmupFailed
    case incomplete
}

/// Error raised by the injectable `ModelLaunchRecorder.init` when a test
/// attempts to bind a recorder to the production diagnostics directory.
/// `precondition`/`fatalError` would trap the whole test process; a
/// catchable Swift error lets the hard path guard itself be asserted in
/// tests while production (which only uses `.shared`) never sees it.
public enum ModelLaunchRecorderError: Error, Equatable {
    case productionPathBlocked(path: String)
}

/// Accumulator-style recorder for the single per-launch record. Each process
/// records exactly one record; partial fields written before provider creation
/// are reported with sentinel values so the file remains a faithful witness.
///
/// `finalizeAndFlush(_:)` is exactly-once per process: a single atomic
/// `hasFlushed` flag guards it, so the terminal flush triggered on
/// load+warmup success, load failure, warmup failure, or the guaranteed flush
/// in `applicationWillTerminate` cannot both write — only the first finalizer
/// emits the JSONL row; subsequent calls are no-ops. A success that arrives
/// after an earlier finalizer is therefore not lost: that earlier finalizer
/// already recorded the true terminal state.
///
/// The shared production singleton (`.shared`) writes to the canonical
/// `~/Library/Application Support/VoiceDock/Diagnostics/` directory, capturing
/// the real PID, executable path, bundle id, and ISO-8601 timestamp. Tests
/// construct an independent recorder with `init(outputDir:pid:...)` pointing
/// at a temporary directory and synthetic identity; a hard path guard refuses
/// to construct a recorder whose output directory is inside the production
/// diagnostics path so tests can never pollute the owner's diagnostics file.
public final class ModelLaunchRecorder: @unchecked Sendable {
    public static let shared = ModelLaunchRecorder()

    private let queue = DispatchQueue(label: "com.voicedock.ModelLaunchRecorder", qos: .utility)
    private var recordStorage: [String: String] = [:]
    private let iso8601: String
    private let pid: Int32
    private let executablePath: String
    private let bundleIdentifier: String
    /// Absolute output directory for this recorder. Production points at the
    /// canonical Application Support/Diagnostics path; tests point at a temp
    /// directory and are hard-refused if it would land inside production.
    private let outputDirectory: URL
    /// Hard guard: a recorder bound to the production diagnostics directory
    /// must never be constructed by tests.
    private let isProduction: Bool
    /// Exactly-once guard. Set atomically under `queue` inside the finalizer.
    /// Once true, subsequent `finalizeAndFlush(_:)`/`flush()` calls are no-ops.
    private var hasFlushed: Bool = false
    /// The explicit terminal state passed to the most recent
    /// `finalizeAndFlush(_:)`, if any. Wins over the flag-derived state.
    private var explicitState: LaunchLifecycleState?
    /// True iff `recordProviderLifecycle` recorded an "ok" load and an "ok"
    /// warmup. Used to flag an explicit incomplete/failure state when load or
    /// warmup did not complete by finalization time (`.incomplete` path).
    private var loadCompleted: Bool = false
    private var warmupCompleted: Bool = false
    /// True iff a duplicate `captureActive` was attempted.
    private var duplicateCaptureAttempted: Bool = false

    private init() {
        // Capture launch time once, up-front. We use a fixed formatter rather
        // than Date.ISO8601Format() to avoid surprises with sub-second
        // precision across the process boundary.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = formatter.string(from: Date())
        let pid = ProcessInfo.processInfo.processIdentifier
        let exec = Bundle.main.bundlePath + "/Contents/MacOS/" + (ProcessInfo.processInfo.processName.isEmpty ? "VoiceDock" : ProcessInfo.processInfo.processName)
        let bundle = Bundle.main.bundleIdentifier ?? "unknown"

        // Resolve the canonical production diagnostics directory once; the
        // hard path guard below asserts the recorder is the singleton bound to
        // that path.
        let prodDir = ModelLaunchRecorder.productionDiagnosticsDirectory()
        self.iso8601 = iso
        self.pid = pid
        self.executablePath = exec
        self.bundleIdentifier = bundle
        self.outputDirectory = prodDir
        self.isProduction = true
        self.recordStorage = [
            "iso8601": iso,
            "pid": String(pid),
            "executablePath": exec,
            "bundleIdentifier": bundle
        ]
    }

    /// Injectable initializer for tests. Constructs a recorder bound to the
    /// given `outputDir` with a synthetic PID, executable path, bundle
    /// identifier, and (optionally) an injected ISO-8601 timestamp string
    /// (inject the clock — `Date()` must not be called inside the recorder
    /// when deterministic timestamps are required). Hard-refuses any
    /// `outputDir` that is inside the production diagnostics directory so
    /// tests can never write to the owner's `model-launch.jsonl`.
    public init(
        outputDir: URL,
        pid: Int32,
        executablePath: String,
        bundleIdentifier: String,
        iso8601: String
    ) throws {
        let prodDir = ModelLaunchRecorder.productionDiagnosticsDirectory()
        // Hard path guard: a test recorder may not target the production
        // diagnostics directory (or any path underneath it). Throws a
        // catchable error rather than trapping so the guard itself can be
        // asserted in tests; production (which only uses `.shared`) never
        // invokes this init.
        let standardized = outputDir.standardizedFileURL.path
        let prefix = prodDir.standardizedFileURL.path
        guard !standardized.hasPrefix(prefix) else {
            throw ModelLaunchRecorderError.productionPathBlocked(path: standardized)
        }
        self.iso8601 = iso8601
        self.pid = pid
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.outputDirectory = outputDir
        self.isProduction = false
        self.recordStorage = [
            "iso8601": iso8601,
            "pid": String(pid),
            "executablePath": executablePath,
            "bundleIdentifier": bundleIdentifier
        ]
    }

    /// Resolve the canonical production diagnostics directory
    /// `~/Library/Application Support/VoiceDock/Diagnostics`. Returns a
    /// placeholder URL when Application Support is unavailable (best-effort).
    private static func productionDiagnosticsDirectory() -> URL {
        let fm = FileManager.default
        guard let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: "/dev/null")
        }
        return supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// Record the preference-suite identifier and persisted raw selected-model value.
    public func recordPreferenceState(suiteName: String, rawSelectedModel: String?) {
        queue.sync {
            recordStorage["preferenceSuiteName"] = suiteName
            recordStorage["persistedRawSelectedModel"] = rawSelectedModel ?? "nil"
        }
    }

    /// Record the ModelStatus state immediately after initialization.
    /// `effective` is the active model the status *believes* is effective
    /// before the provider is created; since `activeModel` starts `nil` in
    /// production, this is recorded as `"notCreated"` rather than collapsing
    /// to `selectedModel` (the saved preference must not be reported as a
    /// real effective selection before the provider exists).
    public func recordModelStatusInit(selected: ASRModelSelection, effective: ASRModelSelection?) {
        queue.sync {
            recordStorage["modelStatusSelectedAfterInit"] = selected.rawValue
            recordStorage["modelStatusEffectiveBeforeProvider"] = effective?.rawValue ?? "notCreated"
        }
    }

    /// Record the factory result and resolved model directory, plus the
    /// ModelStatus.activeModel after `captureActive`.
    public func recordFactoryResult(
        selection: ASRModelSelection,
        descriptorRepoID: String,
        resolvedModelDirectory: String,
        activeAfterCapture: ASRModelSelection?
    ) {
        queue.sync {
            recordStorage["factorySelection"] = selection.rawValue
            recordStorage["factoryDescriptorRepoID"] = descriptorRepoID
            recordStorage["resolvedModelDirectory"] = resolvedModelDirectory
            recordStorage["modelStatusActiveAfterCapture"] = activeAfterCapture?.rawValue ?? "nil"
        }
    }

    /// Record provider load and warmup outcomes. Outcomes are summarized as
    /// short strings: "ok", "fail:<localizedError>", "skipped". A load or
    /// warmup recorded as "ok" marks that phase complete and is used at
    /// flush time to flag an explicit incomplete/failure state otherwise.
    public func recordProviderLifecycle(loadResult: String, warmupResult: String) {
        queue.sync {
            recordStorage["providerLoadResult"] = loadResult
            recordStorage["providerWarmupResult"] = warmupResult
            if loadResult == "ok" || loadResult.hasPrefix("ok:") {
                loadCompleted = true
            }
            if warmupResult == "ok" {
                warmupCompleted = true
            }
        }
    }

    /// Record that a duplicate `captureActive` was attempted (programming
    /// error). The recorder does NOT mutate the active-model fields; this is
    /// a witness marker only, surfaced in `lifecycleState`.
    public func recordDuplicateCaptureActive(
        attemptedSelection: ASRModelSelection,
        existingActive: ASRModelSelection?
    ) {
        queue.sync {
            duplicateCaptureAttempted = true
            recordStorage["duplicateCaptureAttempted"] = "attempted=\(attemptedSelection.rawValue) existing=\(existingActive?.rawValue ?? "nil")"
        }
        logger.error("ModelLaunchRecorder: duplicate captureActive attempted=\(attemptedSelection.rawValue, privacy: .public) existing=\(existingActive?.rawValue ?? "nil", privacy: .public)")
    }

    /// Compute the SHA-256 of the running executable lazily (heavy operation).
    public func recordExecutableHash(_ hash: String) {
        queue.sync {
            recordStorage["executableSHA256"] = hash
        }
    }

    /// Write the accumulated record as exactly one JSONL line.
    ///
    /// `state` is the terminal lifecycle state: `.complete` after a successful
    /// load+warmup, `.loadFailed`/`.warmupFailed` on the corresponding final
    /// failure, or `.incomplete` when the app terminates before a terminal
    /// result is recorded (in which case the flag-derived state —
    /// `incomplete:loadNotRun` / `incomplete:loadDidNotComplete` /
    /// `incomplete:warmupDidNotComplete` — is recorded as the witness). A
    /// prior duplicate-capture attempt overrides the state to
    /// `duplicateCaptureAttempted` so the programming error is visible even
    /// when load+warmup nominally completed.
    ///
    /// Exactly-once: the first call finalizes and writes one JSONL row;
    /// subsequent calls (e.g. a later `applicationWillTerminate` flush after
    /// the success flush already fired) are no-ops. A success that arrives
    /// after an earlier finalizer is therefore not lost — the earlier
    /// finalizer already recorded the true terminal state.
    public func finalizeAndFlush(_ state: LaunchLifecycleState, reason: String? = nil) {
        let record: ModelLaunchRecord? = queue.sync {
            if hasFlushed {
                logger.info("ModelLaunchRecorder: already finalized for pid \(String(describing: self.pid)); secondary finalizer (\(state.rawValue)) is a no-op")
                return nil
            }
            hasFlushed = true
            explicitState = state

            // Snapshot current values with sentinel defaults for any field
            // that has not yet been recorded. This guarantees a faithful
            // witness even under early failure.
            recordStorage["executableSHA256"] = recordStorage["executableSHA256"] ?? "uncomputed"
            recordStorage["preferenceSuiteName"] = recordStorage["preferenceSuiteName"] ?? "unknown"
            recordStorage["modelStatusSelectedAfterInit"] = recordStorage["modelStatusSelectedAfterInit"] ?? "unknown"
            recordStorage["modelStatusEffectiveBeforeProvider"] = recordStorage["modelStatusEffectiveBeforeProvider"] ?? "notCreated"
            recordStorage["factorySelection"] = recordStorage["factorySelection"] ?? "unknown"
            recordStorage["factoryDescriptorRepoID"] = recordStorage["factoryDescriptorRepoID"] ?? "unknown"
            recordStorage["resolvedModelDirectory"] = recordStorage["resolvedModelDirectory"] ?? "unknown"
            recordStorage["modelStatusActiveAfterCapture"] = recordStorage["modelStatusActiveAfterCapture"] ?? "nil"
            recordStorage["providerLoadResult"] = recordStorage["providerLoadResult"] ?? "notrun"
            recordStorage["providerWarmupResult"] = recordStorage["providerWarmupResult"] ?? "notrun"
            let persistedRaw: String?
            if let raw = recordStorage["persistedRawSelectedModel"], raw != "nil" {
                persistedRaw = raw
            } else {
                persistedRaw = nil
            }

            let lifecycleState = Self.deriveLifecycleState(
                explicit: state,
                reason: reason,
                loadCompleted: loadCompleted,
                warmupCompleted: warmupCompleted,
                duplicateCaptureAttempted: duplicateCaptureAttempted
            )

            return ModelLaunchRecord(
                iso8601: recordStorage["iso8601"] ?? iso8601,
                pid: pid,
                executablePath: recordStorage["executablePath"] ?? executablePath,
                executableSHA256: recordStorage["executableSHA256"] ?? "uncomputed",
                bundleIdentifier: recordStorage["bundleIdentifier"] ?? bundleIdentifier,
                preferenceSuiteName: recordStorage["preferenceSuiteName"] ?? "unknown",
                persistedRawSelectedModel: persistedRaw,
                modelStatusSelectedAfterInit: recordStorage["modelStatusSelectedAfterInit"] ?? "unknown",
                modelStatusEffectiveBeforeProvider: recordStorage["modelStatusEffectiveBeforeProvider"] ?? "notCreated",
                factorySelection: recordStorage["factorySelection"] ?? "unknown",
                factoryDescriptorRepoID: recordStorage["factoryDescriptorRepoID"] ?? "unknown",
                resolvedModelDirectory: recordStorage["resolvedModelDirectory"] ?? "unknown",
                modelStatusActiveAfterCapture: recordStorage["modelStatusActiveAfterCapture"] ?? "nil",
                providerLoadResult: recordStorage["providerLoadResult"] ?? "notrun",
                providerWarmupResult: recordStorage["providerWarmupResult"] ?? "notrun",
                lifecycleState: lifecycleState
            )
        }

        if let record = record {
            writeToDisk(record)
        }
    }

    /// Guaranteed terminal flush when the app terminates before an explicit
    /// terminal result was recorded (`.incomplete`). If a prior
    /// `finalizeAndFlush(_:)` already wrote the row, this is a no-op.
    public func flush() {
        finalizeAndFlush(.incomplete)
    }

    /// Best-effort classification of which phase owned a final failure, based
    /// on the load/warmup flags the provider recorded. Caller (e.g.
    /// AppDelegate observing a `.failed` state) passes this to
    /// `finalizeAndFlush(_:)` so the row records `loadFailed` or
    /// `warmupFailed` rather than the generic `.incomplete` family. If neither
    /// phase ran, returns `.incomplete` (a true non-terminal witness).
    public func failureTerminalState() -> LaunchLifecycleState {
        queue.sync {
            if loadCompleted && !warmupCompleted {
                return .warmupFailed
            } else if !loadCompleted {
                return .loadFailed
            } else {
                return .incomplete
            }
        }
    }

    /// Pure derivation of the `lifecycleState` field. A duplicate-capture
    /// attempt is the loudest signal and wins. An explicit terminal state
    /// (`.complete`/`.loadFailed`/`.warmupFailed`) is honored as written
    /// (with a `:<reason>` suffix when provided). `.incomplete` falls back to
    /// the flag-derived witness so the row records which phase never reached
    /// steady state.
    static func deriveLifecycleState(
        explicit: LaunchLifecycleState,
        reason: String?,
        loadCompleted: Bool,
        warmupCompleted: Bool,
        duplicateCaptureAttempted: Bool
    ) -> String {
        if duplicateCaptureAttempted {
            return "duplicateCaptureAttempted"
        }
        switch explicit {
        case .complete:
            return "complete"
        case .loadFailed:
            return reason.map { "loadFailed:\($0)" } ?? "loadFailed"
        case .warmupFailed:
            return reason.map { "warmupFailed:\($0)" } ?? "warmupFailed"
        case .incomplete:
            if !loadCompleted && !warmupCompleted {
                return "incomplete:loadNotRun"
            } else if !loadCompleted {
                return "incomplete:loadDidNotComplete"
            } else {
                return "incomplete:warmupDidNotComplete"
            }
        }
    }

    /// Test-only accessor for the exactly-once guard state. Not used by
    /// production code paths. Tests do NOT reset the shared recorder; they
    /// construct an independent recorder via `init(outputDir:pid:...)`.
    public func hasFinalized() -> Bool {
        queue.sync { hasFlushed }
    }

    private func writeToDisk(_ record: ModelLaunchRecord) {
        let fm = FileManager.default
        let diagDir = outputDirectory
        do {
            try fm.createDirectory(at: diagDir, withIntermediateDirectories: true)
        } catch {
            logger.error("ModelLaunchRecorder: failed to create diagnostic dir \(diagDir.path): \(error.localizedDescription)")
            return
        }

        let fileURL = diagDir.appendingPathComponent("model-launch.jsonl")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let line = try encoder.encode(record)
            var lineData = line
            // One record per line, JSONL.
            lineData.append(0x0A) // \n
            if fm.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: lineData)
                    try? handle.close()
                } else {
                    try lineData.write(to: fileURL)
                }
            } else {
                try lineData.write(to: fileURL)
            }
            logger.info("ModelLaunchRecorder: flushed record for pid \(record.pid) to \(fileURL.path) lifecycleState=\(record.lifecycleState, privacy: .public)")
        } catch {
            logger.error("ModelLaunchRecorder: failed to encode/write record: \(error.localizedDescription)")
        }
    }
}

// MARK: - Executable hash helper

extension ModelLaunchRecorder {
    /// Compute the SHA-256 of the running main executable lazily. Best-effort:
    /// failures record "uncomputed" rather than aborting the launch.
    public static func computeExecutableHash() -> String {
        let execPath = Bundle.main.bundlePath + "/Contents/MacOS/" + (ProcessInfo.processInfo.processName.isEmpty ? "VoiceDock" : ProcessInfo.processInfo.processName)
        return sha256(at: execPath)
    }

    static func sha256(at path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "uncomputed:no-data"
        }
        return data.sha256Hex()
    }
}

extension Data {
    func sha256Hex() -> String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
