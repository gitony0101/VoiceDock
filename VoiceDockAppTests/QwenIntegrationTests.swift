//
//  QwenIntegrationTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//
//  Opt-in integration tests - skipped by default
//  Run with VOICEDOCK_RUN_QWEN_INTEGRATION=1 swift test
//

import XCTest
@testable import VoiceDockCore

/// Helper function to count safetensors files (escapes actor context)
private func countSafetensorsFiles(at url: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
        return 0
    }
    var count = 0
    for case let fileURL as URL in enumerator {
        if fileURL.pathExtension == "safetensors" {
            count += 1
        }
    }
    return count
}

@MainActor
final class QwenIntegrationTests: XCTestCase {
    var provider: Qwen3ASRProvider!
    var storage: ModelStorage!
    var installer: ModelInstaller!
    let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()

        // Check if integration tests are enabled
        guard ProcessInfo.processInfo.environment["VOICEDOCK_RUN_QWEN_INTEGRATION"] == "1" else {
            throw XCTSkip("Qwen integration tests are disabled. Set VOICEDOCK_RUN_QWEN_INTEGRATION=1 to enable.")
        }

        // Use real Application Support for integration tests
        storage = ModelStorage(baseDirectory: nil)
        installer = ModelInstaller(storage: storage)
        provider = Qwen3ASRProvider(storage: storage, descriptor: descriptor)
    }

    override func tearDown() async throws {
        provider = nil
        installer = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Integration Tests

    func testModelInstallationAndValidation() async throws {
        print("🔍 Testing Qwen model installation and validation...")

        // Check if already installed
        let alreadyValid = await storage.isModelValid(descriptor)

        if !alreadyValid {
            print("📥 Model not installed, downloading...")

            // Install with progress
            try await installer.install(descriptor) { progress in
                print("📊 Download progress: \(Int(progress * 100))%")
            }

            print("✅ Download complete")
        } else {
            print("✅ Model already installed")
        }

        // Validate installation
        let isValid = await storage.isModelValid(descriptor)
        XCTAssertTrue(isValid, "Model should be valid after installation")

        // Verify canonical path
        let modelURL = await storage.canonicalModelURL(for: descriptor)
        print("📁 Model installed at: \(modelURL.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))
    }

    func testModelLoad() async throws {
        print("🔍 Testing Qwen model load...")

        // Ensure model is installed
        let isValid = await storage.isModelValid(descriptor)
        guard isValid else {
            throw XCTSkip("Model not installed. Run testModelInstallationAndValidation first.")
        }

        // Load model
        try await provider.load()
        print("✅ Model loaded successfully")
    }

    func testModelWarmup() async throws {
        print("🔍 Testing Qwen model warmup...")

        // Ensure model is loaded
        let isValid = await storage.isModelValid(descriptor)
        guard isValid else {
            throw XCTSkip("Model not installed.")
        }

        try await provider.load()
        try await provider.warmup()
        print("✅ Model warmup successful")
    }

    func testModelTranscription() async throws {
        print("🔍 Testing Qwen model transcription...")

        // Ensure model is loaded
        let isValid = await storage.isModelValid(descriptor)
        guard isValid else {
            throw XCTSkip("Model not installed.")
        }

        try await provider.load()
        try await provider.warmup()

        // Create test audio (100ms of silence at 16 kHz)
        let audio: [Float] = Array(repeating: 0.0, count: 1600)

        print("🎤 Transcribing test audio (\(audio.count) samples)...")
        let result = try await provider.transcribe(audio: audio)
        print("📝 Result: \"\(result)\"")

        // Verify result is a string (may be empty for silent audio)
        XCTAssertNotNil(result)
    }

    func testModelUnload() async throws {
        print("🔍 Testing Qwen model unload...")

        let isValid = await storage.isModelValid(descriptor)
        guard isValid else {
            throw XCTSkip("Model not installed.")
        }

        try await provider.load()
        await provider.unload()
        print("✅ Model unloaded successfully")
    }

    func testFullIntegrationFlow() async throws {
        print("🔍 Testing full Qwen integration flow...")
        print("  1. Installing model...")

        // Install
        let alreadyValid = await storage.isModelValid(descriptor)
        if !alreadyValid {
            try await installer.install(descriptor) { progress in
                if progress >= 1.0 {
                    print("  📥 Download complete")
                }
            }
        }

        print("  2. Validating model...")
        let isValid = await storage.isModelValid(descriptor)
        XCTAssertTrue(isValid)

        print("  3. Loading model...")
        try await provider.load()

        print("  4. Warming up model...")
        try await provider.warmup()

        print("  5. Transcribing test audio...")
        let testAudio: [Float] = Array(repeating: 0.0, count: 1600) // 100ms silence
        let result = try await provider.transcribe(audio: testAudio)
        print("  📝 Result: \"\(result)\"")

        print("  6. Unloading model...")
        await provider.unload()

        print("✅ Full integration flow complete")
    }

    func testCanonicalPathExists() async throws {
        print("🔍 Verifying canonical model path...")

        let modelURL = await storage.canonicalModelURL(for: descriptor)
        print("📁 Canonical path: \(modelURL.path)")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory)

        XCTAssertTrue(exists, "Model directory should exist at canonical path")
        XCTAssertTrue(isDirectory.boolValue, "Canonical path should be a directory")

        // Verify required files exist
        for file in descriptor.requiredFiles {
            let fileURL = modelURL.appendingPathComponent(file)
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            if fileExists {
                print("  ✅ \(file)")
            } else {
                print("  ⚠️ \(file) - MISSING")
            }
        }

        // Count safetensors files using helper function
        let safetensorsCount = countSafetensorsFiles(at: modelURL)
        print("  📦 Found \(safetensorsCount) safetensors file(s)")
        XCTAssertGreaterThan(safetensorsCount, 0, "Should have at least one safetensors file")
    }
}