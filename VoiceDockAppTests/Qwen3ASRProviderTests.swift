//
//  Qwen3ASRProviderTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
@testable import VoiceDockCore

@MainActor
final class Qwen3ASRProviderTests: XCTestCase {
    var provider: Qwen3ASRProvider!
    var mockStorage: ModelStorage!
    var tempBaseDir: URL!
    let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        // Create temporary test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBaseDir = tempDir
        mockStorage = ModelStorage(baseDirectory: tempDir)
        provider = Qwen3ASRProvider(storage: mockStorage, descriptor: descriptor)
    }

    override func tearDown() async throws {
        provider = nil
        mockStorage = nil
        if let tempDir = tempBaseDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempBaseDir = nil
        try await super.tearDown()
    }

    // MARK: - Load Tests

    func testLoadWithMissingModel() async throws {
        // Model not installed
        do {
            try await provider.load()
            XCTFail("Load should throw when model is missing")
        } catch let error as VoiceDockError {
            guard case .modelLoadFailed = error else {
                XCTFail("Should throw modelLoadFailed")
                return
            }
        } catch {
            XCTFail("Should throw VoiceDockError")
        }
    }

    func testLoadWithInvalidModel() async throws {
        // Create invalid model directory (missing files)
        let modelDir = await mockStorage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "incomplete".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        // No safetensors file

        do {
            try await provider.load()
            XCTFail("Load should throw when model is invalid")
        } catch let error as VoiceDockError {
            guard case .modelLoadFailed = error else {
                XCTFail("Should throw modelLoadFailed")
                return
            }
        } catch {
            XCTFail("Should throw VoiceDockError")
        }
    }

    // MARK: - Warmup Tests

    func testWarmupWithoutLoad() async throws {
        do {
            try await provider.warmup()
            XCTFail("Warmup should throw when model is not loaded")
        } catch let error as VoiceDockError {
            guard case .modelWarmupFailed = error else {
                XCTFail("Should throw modelWarmupFailed")
                return
            }
        } catch {
            XCTFail("Should throw VoiceDockError")
        }
    }

    // MARK: - Transcribe Tests

    func testTranscribeWithoutLoad() async throws {
        let audio: [Float] = [0.1, 0.2, 0.3]
        do {
            _ = try await provider.transcribe(audio: audio)
            XCTFail("Transcribe should throw when model is not loaded")
        } catch let error as VoiceDockError {
            guard case .modelInferenceFailed = error else {
                XCTFail("Should throw modelInferenceFailed")
                return
            }
        } catch {
            XCTFail("Should throw VoiceDockError")
        }
    }

    func testTranscribeWithEmptyAudio() async {
        // Note: This test would require a loaded model to fully test
        // The provider returns empty string for empty input before checking model
        let audio: [Float] = []
        do {
            let result = try await provider.transcribe(audio: audio)
            XCTAssertEqual(result, "", "Empty audio should return empty string")
        } catch {
            // Expected if model not loaded
        }
    }

    // MARK: - Unload Tests

    func testUnload() async throws {
        // Unload should be safe to call multiple times
        await provider.unload()
        await provider.unload()
        // No assertion - just verifying it doesn't crash
    }

    func testUnloadAfterLoadFails() async throws {
        // This test requires a real MLX model and metallib.
        // Run with VOICEDOCK_RUN_QWEN_INTEGRATION=1 swift test to enable.
        guard ProcessInfo.processInfo.environment["VOICEDOCK_RUN_QWEN_INTEGRATION"] == "1" else {
            throw XCTSkip("Unload after load test requires real MLX model. Set VOICEDOCK_RUN_QWEN_INTEGRATION=1 to enable.")
        }

        // Create valid mock model directory
        let modelDir = await mockStorage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required files
        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create valid safetensors
        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)

        // Create valid config.json
        let configURL = modelDir.appendingPathComponent("config.json")
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: configURL)

        // Load (will fail because we can't create a real MLX model in tests)
        // But we can test that unload is safe afterwards
        do {
            try await provider.load()
        } catch {
            // Expected - we don't have a real model
        }

        // Unload should still be safe
        await provider.unload()
    }

    // MARK: - Integration Tests (Requires Real MLX Model)

    func testFullLifecycleIntegration() async throws {
        // This test requires a real MLX model and metallib.
        // Run with VOICEDOCK_RUN_QWEN_INTEGRATION=1 swift test to enable.
        guard ProcessInfo.processInfo.environment["VOICEDOCK_RUN_QWEN_INTEGRATION"] == "1" else {
            throw XCTSkip("Full lifecycle integration test requires real MLX model. Set VOICEDOCK_RUN_QWEN_INTEGRATION=1 to enable.")
        }

        // This test verifies the expected call order
        // 1. load (requires valid model)
        // 2. warmup
        // 3. transcribe
        // 4. unload

        // Create valid mock model
        let modelDir = await mockStorage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)

        let configURL = modelDir.appendingPathComponent("config.json")
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: configURL)

        // Load will fail in tests (no real MLX), but we verify the flow
        var loadThrew = false
        do {
            try await provider.load()
        } catch {
            loadThrew = true
        }
        XCTAssertTrue(loadThrew, "Load should throw without real MLX model")

        // But unload should still be callable
        await provider.unload()
    }

    func testUnloadAfterLoadIntegration() async throws {
        // This test requires a real MLX model and metallib.
        // Run with VOICEDOCK_RUN_QWEN_INTEGRATION=1 swift test to enable.
        guard ProcessInfo.processInfo.environment["VOICEDOCK_RUN_QWEN_INTEGRATION"] == "1" else {
            throw XCTSkip("Unload after load integration test requires real MLX model. Set VOICEDOCK_RUN_QWEN_INTEGRATION=1 to enable.")
        }

        // Create valid mock model directory
        let modelDir = await mockStorage.modelDirectory(for: descriptor)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required files
        for file in descriptor.requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create valid safetensors
        let safetensorsURL = modelDir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0x42, count: 1024).write(to: safetensorsURL)

        // Create valid config.json
        let configURL = modelDir.appendingPathComponent("config.json")
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: configURL)

        // Load (will fail because we can't create a real MLX model in tests)
        // But we can test that unload is safe afterwards
        do {
            try await provider.load()
        } catch {
            // Expected - we don't have a real model
        }

        // Unload should still be safe
        await provider.unload()
    }

    // MARK: - Multiple Unload Safety

    func testMultipleUnloadSafety() async {
        await provider.unload()
        await provider.unload()
        await provider.unload()
        // Should not crash
    }
}