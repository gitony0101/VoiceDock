//
//  ModelInstaller.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import HuggingFace
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ModelInstaller")

/// Progress callback for model downloads
public typealias DownloadProgressHandler = @Sendable (Double) -> Void

/// Minimal seam for the snapshot download performed by `ModelInstaller`.
///
/// This exists only so model acquisition transaction semantics (staging
/// identity, lock release, failure/cancellation cleanup, retry readiness) can
/// be tested deterministically without network access or a real model. It is
/// not a generic download framework. The production adapter is HubClient.
public protocol ModelSnapshotDownloading: Sendable {
    /// Download a model snapshot into `destination`.
    ///
    /// Implementations must leave the model snapshot files directly inside
    /// `destination` (not nested under a parent), matching HubClient's
    /// `downloadSnapshot(to:)` behavior.
    func download(
        descriptor: QwenModelDescriptor,
        to destination: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws
}

/// Production adapter: downloads through the HubClient-backed snapshot API.
struct HubSnapshotDownloader: ModelSnapshotDownloading {
    let hubClient: HubClient

    func download(
        descriptor: QwenModelDescriptor,
        to destination: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws {
        guard let repoID = Repo.ID(rawValue: descriptor.repoID) else {
            throw VoiceDockError.modelDownloadFailed(underlying: NSError(
                domain: "ModelInstaller",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repo ID: \(descriptor.repoID)"]
            ))
        }

        _ = try await hubClient.downloadSnapshot(
            of: repoID,
            kind: .model,
            to: destination,
            progressHandler: { progress in
                // Map Hub progress to our 0-0.9 range (0.9 is pre-validation).
                let fraction = progress.fractionCompleted * 0.9
                Task { @MainActor in
                    progressHandler?(fraction)
                }
            }
        )
    }
}

/// Model installer for safely downloading and installing ASR models.
///
/// A single `install(_:progressHandler:)` call is one owned transaction over a
/// single staging directory. The staging URL created at the start is the exact
/// URL downloaded into, validated, and — on any terminal path — cleaned up or
/// published. When the call returns success or throws, the installation lock
/// for that descriptor is already released, so an immediate retry never
/// observes a stale "installation already in progress" failure.
public final class ModelInstaller: Sendable {
    private let storage: ModelStorage
    private let downloader: ModelSnapshotDownloading

    /// HubClient-backed initializer (the production construction path).
    public init(storage: ModelStorage, hubClient: HubClient = .default) {
        self.storage = storage
        self.downloader = HubSnapshotDownloader(hubClient: hubClient)
    }

    /// Test initializer with an injected downloader seam. Deterministic tests
    /// supply a fake to exercise transaction semantics without network access.
    public init(storage: ModelStorage, downloader: ModelSnapshotDownloading) {
        self.storage = storage
        self.downloader = downloader
    }

    /// Install a model with progress reporting.
    ///
    /// - Parameters:
    ///   - descriptor: Model descriptor to install.
    ///   - progressHandler: Optional callback for download progress (0.0 - 1.0).
    /// - Returns: `true` when the model is already validly installed or was
    ///   just installed successfully.
    ///
    /// On every terminal path (success, failure, cancellation), the
    /// installation lock is released before this returns.
    public func install(
        _ descriptor: QwenModelDescriptor,
        progressHandler: DownloadProgressHandler? = nil
    ) async throws -> Bool {
        // Check if already validly installed.
        if await storage.isModelValid(descriptor) {
            logger.info("Model already validly installed: \(descriptor.repoID)")
            progressHandler?(1.0)
            return true
        }

        // Single-flight: claim the lock, or fail fast with a precise error.
        let started = await storage.startInstallation(for: descriptor)
        guard started else {
            logger.info("Installation already in progress for: \(descriptor.repoID)")
            throw VoiceDockError.modelLoadFailed(underlying: NSError(
                domain: "ModelInstaller",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Installation already in progress"]
            ))
        }

        // One staging URL for the whole transaction. It is created exactly once
        // and retained across download, validation, publish, and cleanup.
        let stagingURL = await storage.stagingDirectory()

        let result: Bool
        do {
            result = try await performTransaction(
                descriptor,
                stagingURL: stagingURL,
                progressHandler: progressHandler
            )
        } catch {
            // Clean up the exact transaction staging directory on failure.
            await storage.cleanupStaging(stagingURL)
            await cleanupFailedPublication(descriptor)
            logger.error("Model installation failed: \(error.localizedDescription)")
            // Release the lock before rethrowing so an immediate retry never
            // observes a stale "installation already in progress" failure.
            await storage.completeInstallation(for: descriptor)
            throw error
        }

        // Success path: release the lock before returning so the caller never
        // observes a lingering lock.
        await storage.completeInstallation(for: descriptor)
        return result
    }

    /// Download, validate, and atomically publish a single staging directory.
    private func performTransaction(
        _ descriptor: QwenModelDescriptor,
        stagingURL: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create staging directory \(stagingURL.path): \(error.localizedDescription)")
            throw VoiceDockError.modelDownloadFailed(underlying: error)
        }

        // Download into the exact staging URL.
        do {
            try await downloader.download(
                descriptor: descriptor,
                to: stagingURL,
                progressHandler: progressHandler
            )
        } catch {
            throw error
        }
        logger.info("Downloaded snapshot to: \(stagingURL.path)")

        // Validate the downloaded staging model.
        let isValid = await validateStagingModel(stagingURL, descriptor: descriptor)
        guard isValid else {
            throw VoiceDockError.modelDownloadFailed(underlying: NSError(
                domain: "ModelInstaller",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Staging model validation failed"]
            ))
        }

        // Atomically publish staging → final. On failure, the partial final
        // installation must not be left behind; the catch path below removes
        // any invalid or incomplete result.
        do {
            try await storage.atomicInstall(from: stagingURL, for: descriptor)
        } catch {
            // atomicInstall may have already moved/removed files; ensure no
            // partial final model survives a failed publish.
            await cleanupFailedPublication(descriptor)
            throw error
        }

        logger.info("Model installed successfully: \(descriptor.repoID)")
        progressHandler?(1.0)
        return true
    }

    /// Remove any invalid or partial final model publication left by a failed
    /// install. Never removes a validly installed model.
    private func cleanupFailedPublication(_ descriptor: QwenModelDescriptor) async {
        if await !storage.isModelValid(descriptor) {
            try? await storage.deleteModel(descriptor)
            logger.info("Cleaned up failed installation")
        }
    }

    /// Validate the staging model directory. The staging URL is the model
    /// directory itself, so validation treats it directly.
    private func validateStagingModel(_ url: URL, descriptor: QwenModelDescriptor) async -> Bool {
        await storage.validateModelDirectory(url, descriptor: descriptor)
    }
}