//
//  TranscriptCorrectionEngine.swift
//  VoiceDock
//
//  VoiceDock Personal Transcript Correction v1
//

import Foundation

/// Protocol for transcript correction engines
///
/// The correction engine applies deterministic rules to fix known ASR errors
/// without changing meaning, removing content, or inventing facts.
public protocol TranscriptCorrectionEngine: Sendable {
    /// Correct a transcript using builtin rules and optional user corrections
    /// - Parameter transcript: The raw transcript from ASR
    /// - Returns: A CorrectionResult with raw, corrected, and applied corrections
    func correct(_ transcript: String) -> CorrectionResult

    /// Load user correction rules from the standard location
    /// - Throws: If the file exists but contains invalid JSON
    func loadUserCorrections() async throws

    /// Reload user corrections manually (e.g., after editing the file)
    func reloadUserCorrections() async
}