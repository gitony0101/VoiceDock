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

    // MARK: - Default Behavior

    @Test("No environment variable selects Qwen3 1.7B 4-bit (default)")
    func testNoEnvVarSelectsQwen17B4bit() {
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        unsetenv(ASRModelEnvVarName)

        let selection = ASRModelSelection.current()
        #expect(selection == .qwen3_1_7B_4bit)

        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    @Test("Empty environment value selects Qwen3 1.7B 4-bit (default)")
    func testEmptyEnvValueSelectsDefault() {
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        setenv(ASRModelEnvVarName, "", 1)

        let selection = ASRModelSelection.fromEnvironmentValue("")
        #expect(selection == .qwen3_1_7B_4bit)

        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    // MARK: - Supported Production Models

    @Test("Qwen 1.7B 4-bit environment value selects Qwen3ASRProvider")
    func testQwen17bitEnvValueSelectsQwen() {
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        setenv(ASRModelEnvVarName, "qwen3-1.7b-4bit", 1)

        let selection = ASRModelSelection.fromEnvironmentValue(ProcessInfo.processInfo.environment[ASRModelEnvVarName])
        #expect(selection == .qwen3_1_7B_4bit)

        let provider = ASRProviderFactory.createProvider(for: .qwen3_1_7B_4bit)
        #expect(provider is Qwen3ASRProvider)

        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    @Test("Qwen 0.6B 8-bit environment value selects Qwen3ASRProvider")
    func testQwen8bitEnvValueSelectsQwen() {
        let originalValue = ProcessInfo.processInfo.environment[ASRModelEnvVarName]
        setenv(ASRModelEnvVarName, "qwen3-0.6b-8bit", 1)

        let selection = ASRModelSelection.fromEnvironmentValue(ProcessInfo.processInfo.environment[ASRModelEnvVarName])
        #expect(selection == .qwen3_0_6B_8bit)

        let provider = ASRProviderFactory.createProvider(for: .qwen3_0_6B_8bit)
        #expect(provider is Qwen3ASRProvider)

        if let originalValue = originalValue {
            setenv(ASRModelEnvVarName, originalValue, 1)
        } else {
            unsetenv(ASRModelEnvVarName)
        }
    }

    // MARK: - Retired Model Fallback Behavior

    @Test("Retired Nemotron value falls back to Qwen3 1.7B 4-bit with warning")
    func testRetiredNemotronValueFallsBackToDefault() {
        var warningReason: ASRModelSelection.FallbackReason?
        var warningMessage: String?

        let selection = ASRModelSelection.fromEnvironmentValue("nemotron-0.6b-8bit") { reason, msg in
            warningReason = reason
            warningMessage = msg
        }

        #expect(selection == .qwen3_1_7B_4bit)
        #expect(warningReason == .retired)
        #expect(warningMessage?.contains("Retired ASR model") == true)
        #expect(warningMessage?.contains("nemotron-0.6b-8bit") == true)
    }

    @Test("Retired Qwen 0.6B 6-bit value falls back to Qwen3 1.7B 4-bit with warning")
    func testRetiredQwen6bitValueFallsBackToDefault() {
        var warningReason: ASRModelSelection.FallbackReason?
        var warningMessage: String?

        let selection = ASRModelSelection.fromEnvironmentValue("qwen3-0.6b-6bit") { reason, msg in
            warningReason = reason
            warningMessage = msg
        }

        #expect(selection == .qwen3_1_7B_4bit)
        #expect(warningReason == .retired)
        #expect(warningMessage?.contains("Retired ASR model") == true)
        #expect(warningMessage?.contains("qwen3-0.6b-6bit") == true)
    }

    // MARK: - Invalid Value Fallback

    @Test("Unknown environment value falls back to Qwen3 1.7B 4-bit with warning")
    func testUnknownEnvValueFallsBackToDefault() {
        var warningReason: ASRModelSelection.FallbackReason?
        var warningMessage: String?

        let selection = ASRModelSelection.fromEnvironmentValue("unknown-model-123") { reason, msg in
            warningReason = reason
            warningMessage = msg
        }

        #expect(selection == .qwen3_1_7B_4bit)
        #expect(warningReason == .unknown)
        #expect(warningMessage?.contains("Unknown ASR model value") == true)
    }

    // MARK: - Explicit Selection

    @Test("Explicit selection creates correct provider for Quality model")
    func testExplicitSelectionCreatesQualityProvider() {
        let provider = ASRProviderFactory.createProvider(for: .qwen3_1_7B_4bit)
        #expect(provider is Qwen3ASRProvider)
    }

    @Test("Explicit selection creates correct provider for Fast model")
    func testExplicitSelectionCreatesFastProvider() {
        let provider = ASRProviderFactory.createProvider(for: .qwen3_0_6B_8bit)
        #expect(provider is Qwen3ASRProvider)
    }

    // MARK: - Enum Metadata

    @Test("ASRModelSelection enum has exactly 2 cases")
    func testASRModelSelectionEnumCasesCount() {
        #expect(ASRModelSelection.allCases.count == 2)
    }

    @Test("ASRModelSelection raw values are correct")
    func testASRModelSelectionRawValues() {
        #expect(ASRModelSelection.qwen3_0_6B_8bit.rawValue == "qwen3-0.6b-8bit")
        #expect(ASRModelSelection.qwen3_1_7B_4bit.rawValue == "qwen3-1.7b-4bit")
    }

    // MARK: - Helper Tests

    @Test("fromEnvironmentValue handles nil by returning default")
    func testFromEnvironmentValueHandlesNil() {
        let selection = ASRModelSelection.fromEnvironmentValue(nil)
        #expect(selection == .qwen3_1_7B_4bit)
    }
}