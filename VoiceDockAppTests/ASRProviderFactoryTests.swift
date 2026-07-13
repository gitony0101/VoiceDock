//
//  ASRProviderFactoryTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation
import Testing
import VoiceDockCore

@Suite("ASRProviderFactory Tests", .serialized)
struct ASRProviderFactoryTests {

    @Test("No environment variable selects Qwen3 1.7B 4-bit (Quality/default)")
    func testNoEnvVarSelectsQwen17B4bit() {
        // Save original value
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]

        // Temporarily unset
        unsetenv(ASRModelEnvVarName)

        // Test default selection (Qwen3 1.7B 4-bit is default)
        let selection = ASRModelSelection.current()
        #expect(selection == .qwen3_1_7B_4bit)

        // Restore original
        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        }
    }

    @Test("Qwen 0.6B 8-bit environment value selects Qwen3ASRProvider")
    func testQwen8bitEnvValueSelectsQwen() {
        // Save original value
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]

        // Set Qwen 8-bit value
        setenv(ASRModelEnvVarName, "qwen3-0.6b-8bit", 1)

        // Test selection - reload from environment
        let selection = ASRModelSelection.fromEnvironmentValue(ProcessInfo.processInfo.environment[ASRModelEnvVarName])
        #expect(selection == .qwen3_0_6B_8bit)

        // Create provider using explicit selection for deterministic test
        let provider = ASRProviderFactory.createProvider(for: .qwen3_0_6B_8bit)
        #expect(provider is Qwen3ASRProvider)

        // Restore original
        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    @Test("Qwen 1.7B 4-bit environment value selects Qwen3ASRProvider")
    func testQwen17bitEnvValueSelectsQwen() {
        // Save original value
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]

        // Set Qwen 1.7B value
        setenv(ASRModelEnvVarName, "qwen3-1.7b-4bit", 1)

        // Test selection - reload from environment
        let selection = ASRModelSelection.fromEnvironmentValue(ProcessInfo.processInfo.environment[ASRModelEnvVarName])
        #expect(selection == .qwen3_1_7B_4bit)

        // Create provider using explicit selection for deterministic test
        let provider = ASRProviderFactory.createProvider(for: .qwen3_1_7B_4bit)
        #expect(provider is Qwen3ASRProvider)

        // Restore original
        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    @Test("Unknown environment value falls back to Qwen3 1.7B 4-bit")
    func testUnknownEnvValueFallsBackToQwen17B4bit() {
        // Save original value
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]

        // Set unknown value
        setenv(ASRModelEnvVarName, "unknown-model-123", 1)

        // Test selection falls back to Qwen3 1.7B 4-bit (default)
        let selection = ASRModelSelection.fromEnvironmentValue(ProcessInfo.processInfo.environment[ASRModelEnvVarName])
        #expect(selection == .qwen3_1_7B_4bit)

        // Restore original
        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    @Test("Explicit selection creates correct provider")
    func testExplicitSelectionCreatesCorrectProvider() {
        // Test Qwen 0.6B 8-bit explicit selection
        let qwen8bitProvider = ASRProviderFactory.createProvider(for: .qwen3_0_6B_8bit)
        #expect(qwen8bitProvider is Qwen3ASRProvider)

        // Test Qwen 1.7B 4-bit explicit selection
        let qwen17bitProvider = ASRProviderFactory.createProvider(for: .qwen3_1_7B_4bit)
        #expect(qwen17bitProvider is Qwen3ASRProvider)
    }

    @Test("ASRModelSelection enum cases are correct")
    func testASRModelSelectionEnumCases() {
        let allCases = ASRModelSelection.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.qwen3_0_6B_8bit))
        #expect(allCases.contains(.qwen3_1_7B_4bit))
    }

    @Test("ASRModelSelection raw values are correct")
    func testASRModelSelectionRawValues() {
        #expect(ASRModelSelection.qwen3_0_6B_8bit.rawValue == "qwen3-0.6b-8bit")
        #expect(ASRModelSelection.qwen3_1_7B_4bit.rawValue == "qwen3-1.7b-4bit")
    }

    @Test("fromEnvironmentValue handles nil by returning Qwen3 1.7B 4-bit default")
    func testFromEnvironmentValueHandlesNil() {
        let selection = ASRModelSelection.fromEnvironmentValue(nil)
        #expect(selection == .qwen3_1_7B_4bit)
    }

    @Test("fromEnvironmentValue handles valid qwen 0.6B 8-bit value")
    func testFromEnvironmentValueHandlesValidQwen8bit() {
        let selection = ASRModelSelection.fromEnvironmentValue("qwen3-0.6b-8bit")
        #expect(selection == .qwen3_0_6B_8bit)
    }

    @Test("fromEnvironmentValue handles valid qwen 1.7B 4-bit value")
    func testFromEnvironmentValueHandlesValidQwen17bit() {
        let selection = ASRModelSelection.fromEnvironmentValue("qwen3-1.7b-4bit")
        #expect(selection == .qwen3_1_7B_4bit)
    }

    @Test("fromEnvironmentValue handles invalid value by falling back to Qwen3 1.7B 4-bit")
    func testFromEnvironmentValueHandlesInvalidValue() {
        let selection = ASRModelSelection.fromEnvironmentValue("invalid-model-name")
        #expect(selection == .qwen3_1_7B_4bit)
    }
}