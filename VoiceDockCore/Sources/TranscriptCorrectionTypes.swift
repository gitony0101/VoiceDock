//
//  TranscriptCorrectionTypes.swift
//  VoiceDock
//
//  VoiceDock Personal Transcript Correction v1
//

import Foundation

/// Represents a single correction applied to a transcript
public struct AppliedCorrection: Equatable {
    /// The original text that was corrected
    public let originalText: String
    /// The replacement text
    public let replacementText: String
    /// A unique identifier for the rule that was applied
    public let ruleIdentifier: String
    /// The range in the original transcript where the correction was applied
    public let range: Range<String.Index>

    public init(originalText: String, replacementText: String, ruleIdentifier: String, range: Range<String.Index>) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.ruleIdentifier = ruleIdentifier
        self.range = range
    }
}

/// Result of running the correction engine on a transcript
public struct CorrectionResult: Equatable {
    /// The original uncorrected transcript
    public let rawTranscript: String
    /// The corrected transcript (may be identical to raw if no corrections applied)
    public let correctedTranscript: String
    /// List of corrections that were applied
    public let appliedCorrections: [AppliedCorrection]
    /// Whether any changes were made
    public let didChange: Bool

    public init(rawTranscript: String, correctedTranscript: String, appliedCorrections: [AppliedCorrection]) {
        self.rawTranscript = rawTranscript
        self.correctedTranscript = correctedTranscript
        self.appliedCorrections = appliedCorrections
        self.didChange = !appliedCorrections.isEmpty
    }
}

/// Matching strategy for a correction rule
public enum CorrectionMatchType: String, Codable {
    /// Exact match (case-sensitive)
    case exactPhrase
    /// Case-insensitive phrase match
    case caseInsensitivePhrase
    /// Word boundary match (won't match inside other words)
    case wordBoundaryPhrase
    /// Contextual match (requires nearby context keywords)
    case contextualPhrase
}

/// A single correction rule
public struct CorrectionRule: Equatable {
    /// Unique identifier for this rule
    public let id: String
    /// The text pattern to match
    public let pattern: String
    /// The replacement text
    public let replacement: String
    /// The match type to use
    public let matchType: CorrectionMatchType
    /// Optional context keywords required for contextual matches
    public let contextKeywords: [String]?
    /// Priority (higher = applied first)
    public let priority: Int

    public init(id: String, pattern: String, replacement: String, matchType: CorrectionMatchType = .caseInsensitivePhrase, contextKeywords: [String]? = nil, priority: Int = 0) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.matchType = matchType
        self.contextKeywords = contextKeywords
        self.priority = priority
    }
}