//
//  TranscriptCorrectionMode.swift
//  VoiceDock
//
//  VoiceDock Personal Transcript Correction v1
//

import Foundation

/// User preference for transcript correction
public enum TranscriptCorrectionMode: String, Codable, CaseIterable, Sendable {
    /// Deliver raw ASR transcript without correction
    case off = "off"
    /// Apply deterministic personal correction rules
    case personalCorrection = "personalCorrection"

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .personalCorrection:
            return "Personal Correction"
        }
    }

    public var description: String {
        switch self {
        case .off:
            return "Deliver raw ASR transcript"
        case .personalCorrection:
            return "Apply deterministic correction rules"
        }
    }
}