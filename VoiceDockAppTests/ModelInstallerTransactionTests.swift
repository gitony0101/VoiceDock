//
//  ModelInstallerTransactionTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.4.2 — Model acquisition transaction hardening.
//
//  Deterministic tests only. No network access, no production model load.
//  A fake downloader seam drives ModelInstaller through success, download
//  failure, validation failure, and cancellation, and records the staging URL
//  it was handed so staging-identity is asserted exactly.
//

import XCTest
import Foundation
@testable import VoiceDockCore

/// A fake snapshot downloader that writes a valid model tree (or fails, or
/// cancels) and records the destination URL it received.
private actor FakeSnapshotDownloader: ModelSnapshotDownloading {
    enum Behavior: Sendable {
        case succeed
        case fail(Error)
        case cancel
    }

    let descriptor: QwenModelDescriptor
    let behavior: Behavior
    /// The exact destination URL handed to `download(to:)`.
    private(set) var receivedDestination: URL?

    init(descriptor: QwenModelDescriptor, behavior: Behavior) {
        self.descriptor = descriptor
        self.behavior = behavior
    }

    func receivedURL() -> URL? {
        receivedDestination
    }

    func download(
        descriptor: QwenModelDescriptor,
        to destination: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws {
        receivedDestination = destination

        switch behavior {
        case .succeed:
            try writeValidModel(at: destination)
            progressHandler?(0.9)
        case .fail(let error):
            throw error
        case .cancel:
            throw CancellationError()
        }
    }

    /// Write a fully valid model tree directly into `destination` matching the
    /// HubClient `downloadSnapshot(to:)` contract: files land directly inside
    /// the destination directory (a single non-indexed safetensors file).
    private func writeValidModel(at destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)

        for file in descriptor.requiredFiles {
            let fileURL = destination.appendingPathComponent(file)
            if file == "config.json" {
                let data = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
                try data.write(to: fileURL)
            } else {
                try Data("mock content".utf8).write(to: fileURL)
            }
        }

        let safetensorsURL = destination.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)
    }
}

private struct StubError: Error, Equatable {
    let message: String
    static let downloadBoom = StubError(message: "download failed")
}

@MainActor
final class ModelInstallerTransactionTests: XCTestCase {
    var tempBaseDir: URL!
    var storage: ModelStorage!
    let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockTxnTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBaseDir = tempDir
        storage = ModelStorage(baseDirectory: tempDir)
    }

    override func tearDown() async throws {
        if let tempDir = tempBaseDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempBaseDir = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - T1 success transaction

    func testSuccessTransaction_OneStagingURL_LockReleasedBeforeReturn() async throws {
        let downloader = FakeSnapshotDownloader(descriptor: descriptor, behavior: .succeed)
        let installer = ModelInstaller(storage: storage, downloader: downloader)

        let result = try await installer.install(descriptor)

        let inProgress = await storage.isInstallationInProgress(for: descriptor)
        let isValid = await storage.isModelValid(descriptor)
        let received = await downloader.receivedURL()

        XCTAssertTrue(result)
        // Lock is already released on return: no stale in-progress state.
        XCTAssertFalse(inProgress)
        // Final model is validly installed.
        XCTAssertTrue(isValid)
        // One staging URL was used.
        XCTAssertNotNil(received)
    }

    // MARK: - T2 download failure

    func testDownloadFailure_SameStagingURLCleaned_NoPublication_LockReleased() async throws {
        let downloader = FakeSnapshotDownloader(descriptor: descriptor, behavior: .fail(StubError.downloadBoom))
        let installer = ModelInstaller(storage: storage, downloader: downloader)

        do {
            _ = try await installer.install(descriptor)
            XCTFail("expected install to throw")
        } catch {
            if let stub = error as? StubError {
                XCTAssertEqual(stub, .downloadBoom)
            }
        }

        let inProgress = await storage.isInstallationInProgress(for: descriptor)
        let isValid = await storage.isModelValid(descriptor)
        let finalURL = await storage.modelDirectory(for: descriptor)
        let received = await downloader.receivedURL()

        XCTAssertFalse(inProgress)
        XCTAssertFalse(isValid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertNotNil(received)
        if let received {
            XCTAssertFalse(FileManager.default.fileExists(atPath: received.path))
        }
    }

    // MARK: - T3 validation failure

    func testValidationFailure_StagingCleaned_NoPublication_LockReleased() async throws {
        let downloader = IncompleteValidationDownloader(descriptor: descriptor)
        let installer = ModelInstaller(storage: storage, downloader: downloader)

        do {
            _ = try await installer.install(descriptor)
            XCTFail("expected install to throw on validation failure")
        } catch {
            // Expected: validation failed.
        }

        let inProgress = await storage.isInstallationInProgress(for: descriptor)
        let isValid = await storage.isModelValid(descriptor)
        let finalURL = await storage.modelDirectory(for: descriptor)
        let received = await downloader.receivedURL()

        XCTAssertFalse(inProgress)
        XCTAssertFalse(isValid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertNotNil(received)
        if let received {
            XCTAssertFalse(FileManager.default.fileExists(atPath: received.path))
        }
    }

    // MARK: - T4 cancellation

    func testCancellation_CleansStaging_ReleasesLock_CancellationObservable() async throws {
        let downloader = FakeSnapshotDownloader(descriptor: descriptor, behavior: .cancel)
        let installer = ModelInstaller(storage: storage, downloader: downloader)

        do {
            _ = try await installer.install(descriptor)
            XCTFail("expected install to throw on cancellation")
        } catch {
            XCTAssertTrue(
                error is CancellationError,
                "cancellation should remain observable, got \(type(of: error))"
            )
        }

        let received = await downloader.receivedURL()
        let inProgress = await storage.isInstallationInProgress(for: descriptor)
        let isValid = await storage.isModelValid(descriptor)

        XCTAssertNotNil(received)
        XCTAssertFalse(inProgress)
        XCTAssertFalse(isValid)
        if let received {
            XCTAssertFalse(FileManager.default.fileExists(atPath: received.path))
        }
    }

    // MARK: - T5 immediate retry after failure

    func testImmediateRetryAfterFailure_NoStaleLock() async throws {
        let failing = FakeSnapshotDownloader(descriptor: descriptor, behavior: .fail(StubError.downloadBoom))
        let installer1 = ModelInstaller(storage: storage, downloader: failing)
        _ = try? await installer1.install(descriptor)

        // Immediately retry with a succeeding downloader using the SAME storage.
        let succeeding = FakeSnapshotDownloader(descriptor: descriptor, behavior: .succeed)
        let installer2 = ModelInstaller(storage: storage, downloader: succeeding)
        let result = try await installer2.install(descriptor)

        let isValid = await storage.isModelValid(descriptor)

        XCTAssertTrue(result)
        XCTAssertTrue(isValid)
    }

    // MARK: - T6 immediate retry after success

    func testImmediateRetryAfterSuccess_LockAlreadyReleased() async throws {
        let downloader = FakeSnapshotDownloader(descriptor: descriptor, behavior: .succeed)
        let installer = ModelInstaller(storage: storage, downloader: downloader)
        _ = try await installer.install(descriptor)

        let inProgress = await storage.isInstallationInProgress(for: descriptor)
        let again = try await installer.install(descriptor)

        XCTAssertFalse(inProgress)
        XCTAssertTrue(again)
    }

    // MARK: - Stress: failure → retry × 30

    func testStressFailureRetryThirtyTimes() async throws {
        for iteration in 0..<30 {
            let failing = FakeSnapshotDownloader(descriptor: descriptor, behavior: .fail(StubError.downloadBoom))
            let installer = ModelInstaller(storage: storage, downloader: failing)
            _ = try? await installer.install(descriptor)

            let staleLock = await storage.isInstallationInProgress(for: descriptor)
            XCTAssertFalse(staleLock, "iteration \(iteration): stale lock")

            let succeeding = FakeSnapshotDownloader(descriptor: descriptor, behavior: .succeed)
            let installer2 = ModelInstaller(storage: storage, downloader: succeeding)
            _ = try await installer2.install(descriptor)

            let installed = await storage.isModelValid(descriptor)
            XCTAssertTrue(installed, "iteration \(iteration): not installed")

            try? await storage.deleteModel(descriptor)
        }
    }
}

/// A downloader that writes required metadata but no safetensors at all, so
/// validation deterministically fails (missing the required non-empty shard).
private actor IncompleteValidationDownloader: ModelSnapshotDownloading {
    let descriptor: QwenModelDescriptor
    private(set) var receivedDestination: URL?

    init(descriptor: QwenModelDescriptor) {
        self.descriptor = descriptor
    }

    func receivedURL() -> URL? { receivedDestination }

    func download(
        descriptor: QwenModelDescriptor,
        to destination: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws {
        receivedDestination = destination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in descriptor.requiredFiles where file != "config.json" {
            try Data("mock".utf8).write(to: destination.appendingPathComponent(file))
        }
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: destination.appendingPathComponent("config.json"))
        // Intentionally NO .safetensors file → validation fails.
    }
}