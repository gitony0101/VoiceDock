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
        providerWarmupResult: String
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
    }
}

/// Accumulator-style recorder for the single per-launch record. Each process
/// records exactly one record; partial fields written before provider creation
/// are reported with sentinel values so the file remains a faithful witness.
public final class ModelLaunchRecorder: @unchecked Sendable {
    public static let shared = ModelLaunchRecorder()

    private let queue = DispatchQueue(label: "com.voicedock.ModelLaunchRecorder", qos: .utility)
    private var recordStorage: [String: String] = [:]
    private let iso8601: String

    private init() {
        // Capture launch time once, up-front. We use a fixed formatter rather
        // than Date.ISO8601Format() to avoid surprises with sub-second
        // precision across the process boundary.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = formatter.string(from: Date())
        recordStorage["iso8601"] = iso8601
        recordStorage["pid"] = String(ProcessInfo.processInfo.processIdentifier)
        recordStorage["executablePath"] = Bundle.main.bundlePath + "/Contents/MacOS/" + (ProcessInfo.processInfo.processName.isEmpty ? "VoiceDock" : ProcessInfo.processInfo.processName)
        recordStorage["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// Record the preference-suite identifier and persisted raw selected-model value.
    public func recordPreferenceState(suiteName: String, rawSelectedModel: String?) {
        queue.sync {
            recordStorage["preferenceSuiteName"] = suiteName
            recordStorage["persistedRawSelectedModel"] = rawSelectedModel ?? "nil"
        }
    }

    /// Record the ModelStatus state immediately after initialization.
    public func recordModelStatusInit(selected: ASRModelSelection, effective: ASRModelSelection) {
        queue.sync {
            recordStorage["modelStatusSelectedAfterInit"] = selected.rawValue
            recordStorage["modelStatusEffectiveBeforeProvider"] = effective.rawValue
        }
    }

    /// Record the factory result and resolved model directory, plus the
    /// ModelStatus.activeModel after `captureActive`.
    public func recordFactoryResult(
        selection: ASRModelSelection,
        descriptorRepoID: String,
        resolvedModelDirectory: String,
        activeAfterCapture: ASRModelSelection
    ) {
        queue.sync {
            recordStorage["factorySelection"] = selection.rawValue
            recordStorage["factoryDescriptorRepoID"] = descriptorRepoID
            recordStorage["resolvedModelDirectory"] = resolvedModelDirectory
            recordStorage["modelStatusActiveAfterCapture"] = activeAfterCapture.rawValue
        }
    }

    /// Record provider load and warmup outcomes. Outcomes are summarized as
    /// short strings: "ok", "fail:<localizedError>", "skipped".
    public func recordProviderLifecycle(loadResult: String, warmupResult: String) {
        queue.sync {
            recordStorage["providerLoadResult"] = loadResult
            recordStorage["providerWarmupResult"] = warmupResult
        }
    }

    /// Compute the SHA-256 of the running executable lazily (heavy operation).
    public func recordExecutableHash(_ hash: String) {
        queue.sync {
            recordStorage["executableSHA256"] = hash
        }
    }

    /// Write the accumulated record as exactly one JSONL line and reset.
    /// Called once per process, at the appropriate lifecycle moment.
    public func flush() {
        let record: ModelLaunchRecord = queue.sync {
            // Snapshot current values with sentinel defaults for any field
            // that has not yet been recorded. This guarantees a faithful
            // witness even under early failure.
            recordStorage["executableSHA256"] = recordStorage["executableSHA256"] ?? "uncomputed"
            recordStorage["preferenceSuiteName"] = recordStorage["preferenceSuiteName"] ?? "unknown"
            recordStorage["modelStatusSelectedAfterInit"] = recordStorage["modelStatusSelectedAfterInit"] ?? "unknown"
            recordStorage["modelStatusEffectiveBeforeProvider"] = recordStorage["modelStatusEffectiveBeforeProvider"] ?? "unknown"
            recordStorage["factorySelection"] = recordStorage["factorySelection"] ?? "unknown"
            recordStorage["factoryDescriptorRepoID"] = recordStorage["factoryDescriptorRepoID"] ?? "unknown"
            recordStorage["resolvedModelDirectory"] = recordStorage["resolvedModelDirectory"] ?? "unknown"
            recordStorage["modelStatusActiveAfterCapture"] = recordStorage["modelStatusActiveAfterCapture"] ?? "unknown"
            recordStorage["providerLoadResult"] = recordStorage["providerLoadResult"] ?? "notrun"
            recordStorage["providerWarmupResult"] = recordStorage["providerWarmupResult"] ?? "notrun"
            let persistedRaw: String?
            if let raw = recordStorage["persistedRawSelectedModel"], raw != "nil" {
                persistedRaw = raw
            } else {
                persistedRaw = nil
            }

            return ModelLaunchRecord(
                iso8601: recordStorage["iso8601"] ?? iso8601,
                pid: Int32(recordStorage["pid"] ?? "0") ?? 0,
                executablePath: recordStorage["executablePath"] ?? "",
                executableSHA256: recordStorage["executableSHA256"] ?? "uncomputed",
                bundleIdentifier: recordStorage["bundleIdentifier"] ?? "unknown",
                preferenceSuiteName: recordStorage["preferenceSuiteName"] ?? "unknown",
                persistedRawSelectedModel: persistedRaw,
                modelStatusSelectedAfterInit: recordStorage["modelStatusSelectedAfterInit"] ?? "unknown",
                modelStatusEffectiveBeforeProvider: recordStorage["modelStatusEffectiveBeforeProvider"] ?? "unknown",
                factorySelection: recordStorage["factorySelection"] ?? "unknown",
                factoryDescriptorRepoID: recordStorage["factoryDescriptorRepoID"] ?? "unknown",
                resolvedModelDirectory: recordStorage["resolvedModelDirectory"] ?? "unknown",
                modelStatusActiveAfterCapture: recordStorage["modelStatusActiveAfterCapture"] ?? "unknown",
                providerLoadResult: recordStorage["providerLoadResult"] ?? "notrun",
                providerWarmupResult: recordStorage["providerWarmupResult"] ?? "notrun"
            )
        }

        writeToDisk(record)
    }

    private func writeToDisk(_ record: ModelLaunchRecord) {
        let fm = FileManager.default
        guard let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("ModelLaunchRecorder: application support directory unavailable")
            return
        }
        let diagDir = supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try fm.createDirectory(at: diagDir, withIntermediateDirectories: true)
        } catch {
            logger.error("ModelLaunchRecorder: failed to create diagnostic dir: \(error.localizedDescription)")
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
            logger.info("ModelLaunchRecorder: flushed record for pid \(record.pid) to \(fileURL.path)")
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
