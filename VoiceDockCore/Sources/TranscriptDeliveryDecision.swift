//
//  TranscriptDeliveryDecision.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import Foundation

/// Decision about how to deliver a transcript.
///
/// The decision accounts for user preferences and the frontmost application.
public enum TranscriptDeliveryDecision: Equatable {
    /// Only copy to clipboard; no paste event.
    case copyToClipboard

    /// Paste the transcript (Cmd-V) but do not send Return.
    case pasteTranscript

    /// Paste the transcript and send Return key.
    case pasteAndSendReturn

    /// Paste the transcript but suppress Return for safety.
    ///
    /// The reason explains why Return was suppressed (e.g., terminal app detected).
    case pasteWithReturnSuppressed(reason: String)
}