//
//  ModelStorage.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "ModelStorage")

/// Model storage abstraction for managing ASR models in Application Support
public actor ModelStorage {
    /// Base directory for model storage (injected for testability)
    private let baseDirectory: URL
    /// Queue for serializing model installations
    private var installationLocks: [String: Bool] = [:]

    /// Initialize with custom base directory (for testing) or default Application Support
    public init(baseDirectory: URL? = nil) {
        if let customDir = baseDirectory {
            self.baseDirectory = customDir
            logger.info("Initialized with custom base directory: \(customDir.path)")
        } else {
            // Use FileManager's applicationSupportDirectory
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport
                .appendingPathComponent("VoiceDock", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
            logger.info("Initialized with Application Support directory: \(self.baseDirectory.path)")
        }
    }

    /// Find a valid safetensors file in a directory (non-async helper)
    private static func findValidSafetensorsFile(at url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return false
        }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "safetensors" {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                      let size = attrs[.size] as? Int64, size > 0 else {
                    continue
                }
                return true
            }
        }
        return false
    }

    // MARK: - Directory Resolution

    /// Resolve the canonical model directory for a descriptor
    public func modelDirectory(for descriptor: QwenModelDescriptor) -> URL {
        baseDirectory
            .appendingPathComponent(descriptor.canonicalDirectoryName, isDirectory: true)
    }

    /// Resolve the temporary staging directory
    public func stagingDirectory() -> URL {
        baseDirectory
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("Temporary", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Validation

    /// Check if a model is validly installed
    public func isModelValid(_ descriptor: QwenModelDescriptor) async -> Bool {
        let modelDir = modelDirectory(for: descriptor)
        return await validateModelDirectory(modelDir, descriptor: descriptor)
    }

    /// Validate a model directory (internal for ModelInstaller)
    func validateModelDirectory(_ url: URL, descriptor: QwenModelDescriptor) async -> Bool {
        // Check directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            logger.warning("Model directory does not exist: \(url.path)")
            return false
        }

        // Check required files
        for file in descriptor.requiredFiles {
            let fileURL = url.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                logger.warning("Required file missing: \(fileURL.path)")
                return false
            }

            // Reject zero-byte files
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64, size > 0 else {
                logger.warning("File is empty or unreadable: \(fileURL.path)")
                return false
            }
        }

        // Check for at least one non-empty safetensors file
        // Use Task.detached to escape actor context for enumeration
        let foundValidSafetensors = await Task.detached {
            return Self.findValidSafetensorsFile(at: url)
        }.value

        guard foundValidSafetensors else {
            logger.warning("No valid .safetensors files found")
            return false
        }

        // Validate config.json parses as JSON
        let configURL = url.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              (try? JSONSerialization.jsonObject(with: configData)) != nil else {
            logger.warning("config.json is invalid or unreadable")
            return false
        }

        // Validate indexed files if present
        for indexedFile in descriptor.indexedFiles {
            let indexedURL = url.appendingPathComponent(indexedFile)
            if FileManager.default.fileExists(atPath: indexedURL.path) {
                guard let indexedData = try? Data(contentsOf: indexedURL),
                      (try? JSONSerialization.jsonObject(with: indexedData)) != nil else {
                    logger.warning("Indexed file \(indexedFile) is invalid")
                    return false
                }
            }
        }

        logger.info("Model directory validation passed: \(url.path)")
        return true
    }

    /// Get the canonical model URL for UI display
    public func canonicalModelURL(for descriptor: QwenModelDescriptor) -> URL {
        modelDirectory(for: descriptor)
    }

    // MARK: - Directory Management

    /// Create the model directory hierarchy
    public func createModelDirectory(for descriptor: QwenModelDescriptor) throws {
        let modelDir = modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        logger.info("Created model directory: \(modelDir.path)")
    }

    /// Delete an installed model
    public func deleteModel(_ descriptor: QwenModelDescriptor) throws {
        let modelDir = modelDirectory(for: descriptor)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            logger.info("Model directory does not exist, nothing to delete")
            return
        }
        try FileManager.default.removeItem(at: modelDir)
        logger.info("Deleted model directory: \(modelDir.path)")
    }

    /// Clean up a staging directory
    public func cleanupStaging(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Cleaned up staging directory: \(url.path)")
        } catch {
            logger.error("Failed to cleanup staging: \(error.localizedDescription)")
        }
    }

    /// Delete incomplete staging artifacts
    public func cleanupFailedInstallation(_ descriptor: QwenModelDescriptor) {
        // Only delete if the model is invalid
        Task {
            if await !isModelValid(descriptor) {
                try? deleteModel(descriptor)
                logger.info("Cleaned up failed installation")
            }
        }
    }

    // MARK: - Concurrency Safety

    /// Check if installation is in progress
    public func isInstallationInProgress(for descriptor: QwenModelDescriptor) -> Bool {
        installationLocks[descriptor.repoID] == true
    }

    /// Mark installation as started (single-flight)
    public func startInstallation(for descriptor: QwenModelDescriptor) -> Bool {
        guard installationLocks[descriptor.repoID] != true else {
            return false
        }
        installationLocks[descriptor.repoID] = true
        return true
    }

    /// Mark installation as complete
    public func completeInstallation(for descriptor: QwenModelDescriptor) {
        installationLocks[descriptor.repoID] = nil
    }

    // MARK: - Atomic Operations

    /// Atomically move staging to final location
    public func atomicInstall(from stagingURL: URL, for descriptor: QwenModelDescriptor) throws {
        let finalURL = modelDirectory(for: descriptor)

        // Remove existing valid model if present
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }

        // Atomically move staging to final
        try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        logger.info("Atomically installed model to: \(finalURL.path)")
    }
}