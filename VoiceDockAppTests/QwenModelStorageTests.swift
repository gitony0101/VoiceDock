//
//  QwenModelStorageTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class QwenModelStorageTests: XCTestCase {
    var tempBaseDir: URL!
    var storage: ModelStorage!
    let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        // Create temporary test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBaseDir = tempDir
        storage = ModelStorage(baseDirectory: tempDir)
    }

    override func tearDown() async throws {
        // Cleanup test directories
        if let tempDir = tempBaseDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempBaseDir = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Directory Construction Tests

    func testModelDirectoryConstruction() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        XCTAssertTrue(modelDir.path.hasSuffix("Qwen3-ASR-0.6B-8bit"))
        XCTAssertTrue(modelDir.path.hasPrefix(tempBaseDir.path))
    }

    func testStagingDirectoryConstruction() async throws {
        let stagingDir = await storage.stagingDirectory()
        XCTAssertTrue(stagingDir.path.hasPrefix(tempBaseDir.deletingLastPathComponent().path))
        // Staging dir is under Temporary/UUID, so it should have more components than base
        XCTAssertGreaterThan(stagingDir.pathComponents.count, tempBaseDir.pathComponents.count)
    }

    // MARK: - Directory Creation Tests

    func testCreateModelDirectory() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))

        try await storage.createModelDirectory(for: descriptor)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    // MARK: - Validation Tests

    func testValidModelDirectoryDetection() async throws {
        // Create a valid mock model directory
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required files with content
        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create a valid safetensors file
        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)

        // Create valid config.json
        let configURL = modelDir.appendingPathComponent("config.json")
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: configURL)

        let isValid = await storage.isModelValid(descriptor)
        XCTAssertTrue(isValid, "Valid model directory should be detected")
    }

    func testMissingRequiredFileDetection() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create some files but miss one required
        for file in descriptor.requiredFiles.dropFirst() {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let isValid = await storage.isModelValid(descriptor)
        XCTAssertFalse(isValid, "Missing required file should be detected")
    }

    func testZeroByteSafetensorsRejection() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create all required files
        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create empty safetensors file
        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data().write(to: safetensorsURL)

        let isValid = await storage.isModelValid(descriptor)
        XCTAssertFalse(isValid, "Zero-byte safetensors should be rejected")
    }

    func testInvalidConfigJSONRejection() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required files
        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create invalid config.json
        let configURL = modelDir.appendingPathComponent("config.json")
        try "not valid json".write(to: configURL, atomically: true, encoding: .utf8)

        // Create valid safetensors
        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)

        let isValid = await storage.isModelValid(descriptor)
        XCTAssertFalse(isValid, "Invalid config.json should be rejected")
    }

    func testMissingDirectoryRejection() async throws {
        let isValid = await storage.isModelValid(descriptor)
        XCTAssertFalse(isValid, "Non-existent directory should be rejected")
    }

    // MARK: - Delete Tests

    func testDeleteModel() async throws {
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "content".write(to: modelDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

        try await storage.deleteModel(descriptor)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))
    }

    func testDeleteNonExistentModel() async throws {
        // Should not throw
        try await storage.deleteModel(descriptor)
    }

    // MARK: - Installation Concurrency Tests

    func testConcurrentInstallationPrevention() async throws {
        let exp = expectation(description: "Second installation should fail")

        // Start first installation
        let started = await storage.startInstallation(for: descriptor)
        XCTAssertTrue(started)

        // Try to start second
        let secondStarted = await storage.startInstallation(for: descriptor)
        XCTAssertFalse(secondStarted, "Second installation should be prevented")

        // Complete first
        await storage.completeInstallation(for: descriptor)

        // Now can start again
        let thirdStarted = await storage.startInstallation(for: descriptor)
        XCTAssertTrue(thirdStarted)

        await storage.completeInstallation(for: descriptor)
        exp.fulfill()

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testAtomicInstall() async throws {
        // Create staging directory with content
        let stagingURL = tempBaseDir.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try "test content".write(to: stagingURL.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

        // Atomic install
        try await storage.atomicInstall(from: stagingURL, for: descriptor)

        let finalURL = await storage.modelDirectory(for: descriptor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.appendingPathComponent("test.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testAtomicInstallReplacesExisting() async throws {
        // Create existing model directory
        let modelDir = await storage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "old content".write(to: modelDir.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

        // Create staging with new content
        let stagingURL = tempBaseDir.appendingPathComponent("staging2", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try "new content".write(to: stagingURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        // Atomic install
        try await storage.atomicInstall(from: stagingURL, for: descriptor)

        let finalURL = await storage.modelDirectory(for: descriptor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.appendingPathComponent("old.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.appendingPathComponent("new.txt").path))
    }

    // MARK: - Cleanup Tests

    func testCleanupStaging() async throws {
        let stagingURL = tempBaseDir.appendingPathComponent("cleanup_test", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try "temp".write(to: stagingURL.appendingPathComponent("temp.txt"), atomically: true, encoding: .utf8)

        await storage.cleanupStaging(stagingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testCleanupNonExistentStaging() async throws {
        let stagingURL = tempBaseDir.appendingPathComponent("nonexistent", isDirectory: true)
        // Should not throw
        await storage.cleanupStaging(stagingURL)
    }

    // MARK: - Canonical URL Tests

    func testCanonicalModelURL() async throws {
        let url = await storage.canonicalModelURL(for: descriptor)
        let expected = await storage.modelDirectory(for: descriptor)
        XCTAssertEqual(url, expected)
    }
}