//
//  QwenModelDescriptorTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import Testing
import VoiceDockCore

@Suite("QwenModelDescriptor Tests", .serialized)
struct QwenModelDescriptorTests {

    @Test("All descriptors have valid repo IDs")
    func testAllDescriptorsHaveValidRepoIDs() {
        for descriptor in QwenModelDescriptor.all {
            #expect(!descriptor.repoID.isEmpty)
            #expect(descriptor.repoID.contains("/"))
        }
    }

    @Test("All descriptors have valid canonical directory names")
    func testAllDescriptorsHaveValidDirectoryNames() {
        for descriptor in QwenModelDescriptor.all {
            #expect(!descriptor.canonicalDirectoryName.isEmpty)
            #expect(!descriptor.canonicalDirectoryName.contains("/"))
            #expect(!descriptor.canonicalDirectoryName.contains(".."))
        }
    }

    @Test("All descriptors have non-empty display names")
    func testAllDescriptorsHaveNonEmptyDisplayNames() {
        for descriptor in QwenModelDescriptor.all {
            #expect(!descriptor.displayName.isEmpty)
        }
    }

    @Test("All descriptors have required files")
    func testAllDescriptorsHaveRequiredFiles() {
        for descriptor in QwenModelDescriptor.all {
            #expect(!descriptor.requiredFiles.isEmpty)
            #expect(descriptor.requiredFiles.contains("config.json"))
        }
    }

    @Test("Qwen3 models have correct family")
    func testQwen3ModelsHaveCorrectFamily() {
        let qwenModels: [QwenModelDescriptor] = [
            .qwen3_0_6B_8bit,
            .qwen3_1_7B_4bit
        ]

        for descriptor in qwenModels {
            #expect(descriptor.family == .qwen3)
        }
    }

    @Test("All descriptors have only Qwen3 family")
    func testAllDescriptorsHaveQwen3Family() {
        for descriptor in QwenModelDescriptor.all {
            #expect(descriptor.family == .qwen3)
        }
    }

    @Test("Qwen3-ASR-0.6B-8bit descriptor values")
    func testQwen3_0_6B_8bitDescriptorValues() {
        let descriptor = QwenModelDescriptor.qwen3_0_6B_8bit

        #expect(descriptor.repoID == "mlx-community/Qwen3-ASR-0.6B-8bit")
        #expect(descriptor.displayName == "Qwen3 ASR 0.6B 8-bit")
        #expect(descriptor.canonicalDirectoryName == "Qwen3-ASR-0.6B-8bit")
        #expect(descriptor.family == .qwen3)
        #expect(descriptor.requiredFiles.contains("config.json"))
        #expect(descriptor.requiredFiles.contains("tokenizer_config.json"))
        #expect(descriptor.requiredFiles.contains("merges.txt"))
        #expect(descriptor.requiredFiles.contains("vocab.json"))
        #expect(descriptor.requiredFiles.contains("preprocessor_config.json"))
        #expect(descriptor.requiredFiles.contains("generation_config.json"))
        #expect(descriptor.indexedFiles.contains("model.safetensors.index.json"))
    }

    @Test("Qwen3-ASR-1.7B-4bit descriptor values")
    func testQwen3_1_7B_4bitDescriptorValues() {
        let descriptor = QwenModelDescriptor.qwen3_1_7B_4bit

        #expect(descriptor.repoID == "mlx-community/Qwen3-ASR-1.7B-4bit")
        #expect(descriptor.displayName == "Qwen3 ASR 1.7B 4-bit")
        #expect(descriptor.canonicalDirectoryName == "Qwen3-ASR-1.7B-4bit")
        #expect(descriptor.family == .qwen3)
        #expect(descriptor.requiredFiles.contains("config.json"))
        #expect(descriptor.requiredFiles.contains("tokenizer_config.json"))
        #expect(descriptor.requiredFiles.contains("merges.txt"))
        #expect(descriptor.requiredFiles.contains("vocab.json"))
        #expect(descriptor.requiredFiles.contains("preprocessor_config.json"))
        #expect(descriptor.requiredFiles.contains("generation_config.json"))
        #expect(descriptor.indexedFiles.contains("model.safetensors.index.json"))
    }

    @Test("All models list contains all expected models")
    func testAllModelsListContainsAllExpectedModels() {
        let all = QwenModelDescriptor.all

        #expect(all.count == 2)
        #expect(all.contains(.qwen3_0_6B_8bit))
        #expect(all.contains(.qwen3_1_7B_4bit))
    }

    @Test("modelDescriptor property returns correct descriptor for each enum case")
    func testASRModelSelectionModelDescriptorProperty() {
        #expect(ASRModelSelection.qwen3_0_6B_8bit.modelDescriptor == .qwen3_0_6B_8bit)
        #expect(ASRModelSelection.qwen3_1_7B_4bit.modelDescriptor == .qwen3_1_7B_4bit)
    }

    @Test("ASRModelSelection allCases count matches enum cases")
    func testASRModelSelectionAllCasesCount() {
        #expect(ASRModelSelection.allCases.count == 2)
    }
}