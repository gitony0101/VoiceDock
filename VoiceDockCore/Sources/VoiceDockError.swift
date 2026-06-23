//
//  VoiceDockError.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

/// Unified error types for VoiceDock
public enum VoiceDockError: Error, LocalizedError {
    // Audio errors
    case microphonePermissionDenied
    case microphoneUnavailable
    case audioSessionConfigurationFailed
    case audioEngineStartFailed
    case audioCaptureFailed
    case emptyRecording

    // ASR errors
    case modelLoadFailed(underlying: Error?)
    case modelWarmupFailed
    case modelInferenceFailed(underlying: Error?)
    case modelNotFound
    case modelDownloadFailed(underlying: Error?)
    case transcriptionFailed(underlying: Error?)

    // Permission errors
    case accessibilityPermissionDenied
    case accessibilityNotTrusted

    // Delivery errors
    case clipboardWriteFailed
    case pasteSimulationFailed

    // System errors
    case invalidState(expected: String, actual: String)
    case cancellationRequested
    case unknown(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required for VoiceDock to record audio."
        case .microphoneUnavailable:
            return "No microphone is available on this system."
        case .audioSessionConfigurationFailed:
            return "Failed to configure audio session for recording."
        case .audioEngineStartFailed:
            return "Failed to start audio capture engine."
        case .audioCaptureFailed:
            return "Audio capture encountered an error."
        case .emptyRecording:
            return "Recording is empty. Please speak while holding the push-to-talk key."
        case .modelLoadFailed(let error):
            return "Failed to load transcription model: \(error?.localizedDescription ?? "Unknown error")"
        case .modelWarmupFailed:
            return "Failed to warm up transcription model."
        case .modelInferenceFailed(let error):
            return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
        case .modelNotFound:
            return "Transcription model not found. Please check your internet connection."
        case .modelDownloadFailed(let error):
            return "Failed to download model: \(error?.localizedDescription ?? "Unknown error")"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
        case .accessibilityPermissionDenied:
            return "Accessibility access is required to paste transcriptions into other apps."
        case .accessibilityNotTrusted:
            return "VoiceDock is not trusted for Accessibility. Please grant permission in System Settings."
        case .clipboardWriteFailed:
            return "Failed to write transcription to clipboard."
        case .pasteSimulationFailed:
            return "Failed to simulate paste keyboard event."
        case .invalidState(let expected, let actual):
            return "Invalid state: expected \(expected), got \(actual)"
        case .cancellationRequested:
            return "Operation was cancelled."
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Open System Settings → Privacy & Security → Microphone and enable VoiceDock."
        case .microphoneUnavailable:
            return "Connect a microphone and try again."
        case .audioSessionConfigurationFailed:
            return "Restart VoiceDock and try again."
        case .audioEngineStartFailed:
            return "Restart VoiceDock. If the problem persists, check microphone permissions."
        case .audioCaptureFailed:
            return "Try recording again. If the problem persists, restart VoiceDock."
        case .emptyRecording:
            return "Hold the push-to-talk key while speaking."
        case .modelLoadFailed:
            return "Check your internet connection and try again. The model will download automatically on first launch."
        case .modelWarmupFailed:
            return "Restart VoiceDock and try again."
        case .modelInferenceFailed:
            return "Try a shorter recording. If the problem persists, restart VoiceDock."
        case .modelNotFound:
            return "Ensure you have an internet connection for initial model download."
        case .modelDownloadFailed:
            return "Check your internet connection. You can also manually download the model from huggingface.co/mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
        case .transcriptionFailed:
            return "Try again with clearer speech or a shorter utterance."
        case .accessibilityPermissionDenied, .accessibilityNotTrusted:
            return "Open System Settings → Privacy & Security → Accessibility and enable VoiceDock."
        case .clipboardWriteFailed:
            return "Try again. If the problem persists, restart VoiceDock."
        case .pasteSimulationFailed:
            return "Ensure Accessibility permission is granted. Restart VoiceDock if needed."
        case .invalidState:
            return "Restart VoiceDock to reset the application state."
        case .cancellationRequested:
            return "Try recording again."
        case .unknown:
            return "Restart VoiceDock. If the problem persists, check the console logs."
        }
    }
}