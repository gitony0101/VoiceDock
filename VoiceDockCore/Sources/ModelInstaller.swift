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

/// Model installer for safely downloading and installing ASR models
public final class ModelInstaller: Sendable {
    private let storage: ModelStorage
    private let hubClient: HubClient

    public init(storage: ModelStorage, hubClient: HubClient = .default) {
        self.storage = storage
        self.hubClient = hubClient
    }

    /// Install a model with progress reporting
    /// - Parameters:
    ///   - descriptor: Model descriptor to install
    ///   - progressHandler: Optional callback for download progress (0.0 - 1.0)
    /// - Returns: Whether installation completed successfully
    public func install(
        _ descriptor: QwenModelDescriptor,
        progressHandler: DownloadProgressHandler? = nil
    ) async throws -> Bool {
        // Check if already validly installed
        if await storage.isModelValid(descriptor) {
            logger.info("Model already validly installed: \(descriptor.repoID)")
            progressHandler?(1.0)
            return true
        }

        // Check if installation already in progress (single-flight)
        let started = await storage.startInstallation(for: descriptor)
        guard started else {
            logger.info("Installation already in progress for: \(descriptor.repoID)")
            throw VoiceDockError.modelLoadFailed(underlying: NSError(
                domain: "ModelInstaller",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Installation already in progress"]
            ))
        }

        defer {
            Task { @Sendable in
                await storage.completeInstallation(for: descriptor)
            }
        }

        // Create staging directory
        let stagingURL = await storage.stagingDirectory()
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        do {
            // Download using HubClient - download to staging directly
            try await downloadModel(descriptor, to: stagingURL, progressHandler: progressHandler)

            // Validate staging model
            let isValid = await validateStagingModel(stagingURL, descriptor: descriptor)
            guard isValid else {
                throw VoiceDockError.modelDownloadFailed(underlying: NSError(
                    domain: "ModelInstaller",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Staging model validation failed"]
                ))
            }

            // Atomically install
            try await storage.atomicInstall(from: stagingURL, for: descriptor)

            // Cleanup staging (already moved, so nothing to clean)
            logger.info("Model installed successfully: \(descriptor.repoID)")
            progressHandler?(1.0)
            return true

        } catch {
            // Cleanup on failure
            let stagingURL = await storage.stagingDirectory()
            await storage.cleanupStaging(stagingURL)
            await storage.cleanupFailedInstallation(descriptor)
            logger.error("Model installation failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Methods

    /// Download model files using HubClient directly to staging directory
    private func downloadModel(
        _ descriptor: QwenModelDescriptor,
        to stagingURL: URL,
        progressHandler: DownloadProgressHandler?
    ) async throws {
        logger.info("Downloading model: \(descriptor.repoID) to \(stagingURL.path)")

        // Parse repo ID from string (format: "namespace/name")
        guard let repoID = Repo.ID(rawValue: descriptor.repoID) else {
            throw VoiceDockError.modelDownloadFailed(underlying: NSError(
                domain: "ModelInstaller",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repo ID: \(descriptor.repoID)"]
            ))
        }

        // Download the model snapshot directly to staging directory
        // Progress handler runs on main actor per HubClient API
        _ = try await hubClient.downloadSnapshot(
            of: repoID,
            kind: .model,
            to: stagingURL,
            progressHandler: { progress in
                // Map Hub progress to our 0-0.9 range (0.9 is pre-validation)
                let fraction = progress.fractionCompleted * 0.9
                Task { @MainActor in
                    progressHandler?(fraction)
                }
            }
        )

        logger.info("Downloaded snapshot to: \(stagingURL.path)")
    }

    /// Validate staging model directory
    private func validateStagingModel(_ url: URL, descriptor: QwenModelDescriptor) async -> Bool {
        // Validate the URL directly (it IS the model directory, not a parent)
        // Create a temporary storage that treats url as the base
        let tempStorage = ModelStorage(baseDirectory: url)
        // The descriptor's canonical directory is already the last component of url
        // So we need to check the URL directly
        return await tempStorage.validateModelDirectoryDirect(url, descriptor: descriptor)
    }
}

// Extension to expose validation for ModelInstaller
extension ModelStorage {
    /// Validate a model directory directly (exposed for ModelInstaller)
    func validateModelDirectoryDirect(_ url: URL, descriptor: QwenModelDescriptor) async -> Bool {
        return await validateModelDirectory(url, descriptor: descriptor)
    }
}