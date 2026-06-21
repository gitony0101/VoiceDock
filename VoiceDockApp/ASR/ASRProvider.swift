//
//  ASRProvider.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

enum ASError: Error {
    case loadFailed
    case warmupFailed
    case inferenceFailed
    case modelNotFound
}

/// Protocol for ASR providers - model-agnostic interface
protocol ASRProvider: Actor {
    func load() async throws
    func warmup() async throws
    func transcribe(audio: [Float]) async throws -> String
    func unload() async
}