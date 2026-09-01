//
//  ModelStorageIndexedShardTests.swift
//  VoiceDockAppTests
//
//  VoiceDock 0.4.2 — Indexed-model shard completeness validation.
//
//  Deterministic tests for `ModelStorage.validateIndexedShards`: every shard
//  referenced by a safetensors index must exist, be readable, and be non-empty.
//

import XCTest
import Foundation
@testable import VoiceDockCore

@MainActor
final class ModelStorageIndexedShardTests: XCTestCase {
    var tempBaseDir: URL!
    var storage: ModelStorage!
    let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDockIndexedTests", isDirectory: true)
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

    /// Write required metadata + config.json into `dir` so the only thing that
    /// can fail is the safetensors shard validation.
    private func writeRequiredMetadata(into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in descriptor.requiredFiles where file != "config.json" {
            try Data("mock content".utf8).write(to: dir.appendingPathComponent(file))
        }
        let configData = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        try configData.write(to: dir.appendingPathComponent("config.json"))
    }

    private func writeIndex(_ shardNames: [String], into dir: URL) throws {
        var weightMap: [String: String] = [:]
        for shard in shardNames {
            weightMap[shard] = shard
        }
        let index: [String: Any] = ["weight_map": weightMap, "metadata": ["total_size": 1]]
        let data = try JSONSerialization.data(withJSONObject: index)
        try data.write(to: dir.appendingPathComponent("model.safetensors.index.json"))
    }

    private func writeShard(_ name: String, bytes: Int, into dir: URL) throws {
        try Data(repeating: 0x42, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    // MARK: T7 — all indexed shards present → valid

    func testIndexedModel_AllShardsPresent_Passes() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        let shards = ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"]
        try writeIndex(shards, into: dir)
        for shard in shards { try writeShard(shard, bytes: 1024, into: dir) }

        let valid = await storage.isModelValid(descriptor)
        XCTAssertTrue(valid)
    }

    // MARK: T8 — one referenced shard missing → invalid

    func testIndexedModel_OneShardMissing_Fails() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        let shards = ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"]
        try writeIndex(shards, into: dir)
        // Write only the first shard; the second is referenced but missing.
        try writeShard(shards[0], bytes: 1024, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertFalse(valid)
    }

    // MARK: T9 — one referenced shard zero bytes → invalid

    func testIndexedModel_OneShardZeroBytes_Fails() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        let shards = ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"]
        try writeIndex(shards, into: dir)
        try writeShard(shards[0], bytes: 1024, into: dir)
        try writeShard(shards[1], bytes: 0, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertFalse(valid)
    }

    // MARK: T10 — duplicate shard names (collapsed to distinct set) → valid

    func testIndexedModel_DuplicateShardNames_DistinctSetHandled() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        // weight_map references the same shard twice via different keys.
        let shardFile = "model.safetensors"
        let weightMap = ["layer.0.weight": shardFile, "layer.1.weight": shardFile]
        let index: [String: Any] = ["weight_map": weightMap, "metadata": ["total_size": 1]]
        try JSONSerialization.data(withJSONObject: index)
            .write(to: dir.appendingPathComponent("model.safetensors.index.json"))
        try writeShard(shardFile, bytes: 1024, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertTrue(valid)
    }

    // MARK: T11 — malformed index → invalid

    func testIndexedModel_MalformedIndex_Fails() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        // weight_map missing entirely, or wrong type.
        let badIndex: [String: Any] = ["metadata": ["total_size": 1]]
        try JSONSerialization.data(withJSONObject: badIndex)
            .write(to: dir.appendingPathComponent("model.safetensors.index.json"))
        // Also add a valid shard so only the index structure can fail.
        try writeShard("model.safetensors", bytes: 1024, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertFalse(valid)
    }

    func testIndexedModel_SyntacticallyInvalidIndexJSON_Fails() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        try Data("not valid json".utf8)
            .write(to: dir.appendingPathComponent("model.safetensors.index.json"))
        try writeShard("model.safetensors", bytes: 1024, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertFalse(valid)
    }

    // MARK: T12 — non-indexed model with valid safetensors → valid

    func testNonIndexedModel_ValidSafetensors_Passes() async throws {
        let dir = await storage.modelDirectory(for: descriptor)
        try writeRequiredMetadata(into: dir)
        // No index file at all; just a bare valid safetensors shard.
        try writeShard("model.safetensors", bytes: 1024, into: dir)

        let valid = await storage.isModelValid(descriptor)
        XCTAssertTrue(valid)
    }
}