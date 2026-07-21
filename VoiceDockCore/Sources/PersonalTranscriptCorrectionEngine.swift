//
//  PersonalTranscriptCorrectionEngine.swift
//  VoiceDock
//
//  VoiceDock Personal Transcript Correction v1
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "TranscriptCorrection")

/// Deterministic personal transcript correction engine
///
/// Applies safe, deterministic rules to fix known ASR errors:
/// - Product names (VoiceDock, Qwen)
/// - Technical terms (PTT, recovery test)
/// - Highly constrained recurring confusions
///
/// Safety rules:
/// - Does NOT invent facts
/// - Does NOT summarize or translate
/// - Does NOT change numbers, dates, or unrelated names
/// - Does NOT remove negation or uncertainty words
/// - Returns original text unchanged when no rule matches confidently
public final class PersonalTranscriptCorrectionEngine: TranscriptCorrectionEngine, @unchecked Sendable {

    /// User correction file location
    private static let userCorrectionsPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceDock/Corrections/personal-corrections.json").path
    }()

    /// Ensure the user corrections directory exists
    public static func ensureCorrectionsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let correctionsDir = appSupport.appendingPathComponent("VoiceDock/Corrections", isDirectory: true)

        if !FileManager.default.fileExists(atPath: correctionsDir.path) {
            try FileManager.default.createDirectory(at: correctionsDir, withIntermediateDirectories: true)
        }

        return correctionsDir
    }

    /// Create a sample user corrections file with documented examples
    public static func createSampleUserCorrectionsFile() throws -> URL {
        let dir = try ensureCorrectionsDirectory()
        let fileURL = dir.appendingPathComponent("personal-corrections.json")

        // Don't overwrite existing file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let sample = UserCorrectionsFile(
            version: 1,
            replacements: [
                UserReplacement(id: "example-1", from: "my custom term", to: "My Custom Term", match: "caseInsensitivePhrase", priority: 50),
                UserReplacement(id: "example-2", from: "acronym ABC", to: "Acronym ABC", match: "exactPhrase", priority: 50)
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(sample)
        try data.write(to: fileURL)

        return fileURL
    }

    /// All correction rules (builtin + user), sorted by priority (highest first)
    private var allRules: [CorrectionRule] = []

    /// User-loaded correction rules
    private var userRules: [CorrectionRule] = []

    /// Built-in correction rules
    private let builtinRules: [CorrectionRule] = [
        // VoiceDock aliases - highest priority, most specific first
        CorrectionRule(id: "voicedock-voice-document", pattern: "Voice Document", replacement: "VoiceDock", matchType: .caseInsensitivePhrase, priority: 100),
        CorrectionRule(id: "voicedock-voice-doc-kovan", pattern: "voice: Doc", replacement: "VoiceDock", matchType: .caseInsensitivePhrase, priority: 100),
        CorrectionRule(id: "voicedock-voice-doc", pattern: "voice doc", replacement: "VoiceDock", matchType: .wordBoundaryPhrase, priority: 100),
        CorrectionRule(id: "voicedock-voice-duck", pattern: "Voice Duck", replacement: "VoiceDock", matchType: .caseInsensitivePhrase, priority: 100),
        CorrectionRule(id: "voicedock-voice-stock", pattern: "voice stock", replacement: "VoiceDock", matchType: .wordBoundaryPhrase, contextKeywords: ["recovery", "test", "makes", "Chinese", "English"], priority: 100),
        CorrectionRule(id: "voicedock-voice-stock-capitalized", pattern: "Voice Stock", replacement: "VoiceDock", matchType: .wordBoundaryPhrase, contextKeywords: ["recovery", "test", "makes", "Chinese", "English"], priority: 100),

        // Qwen aliases - requires context
        CorrectionRule(id: "qwen-kovan-contextual", pattern: "Kovan", replacement: "Qwen", matchType: .contextualPhrase, contextKeywords: ["recovery", "VoiceDock", "voice", "ASR", "model", "test"], priority: 90),
        CorrectionRule(id: "qwen-q-win", pattern: "Q Win", replacement: "Qwen", matchType: .caseInsensitivePhrase, priority: 90),
        CorrectionRule(id: "qwen-q-wen", pattern: "Q Wen", replacement: "Qwen", matchType: .caseInsensitivePhrase, priority: 90),

        // Technical terms - contextual
        CorrectionRule(id: "honor-tvt-to-owner-ptt", pattern: "Honor TVT", replacement: "Owner PTT", matchType: .caseInsensitivePhrase, priority: 80),
        CorrectionRule(id: "makes-chinese-english", pattern: "makes Chinese English", replacement: "mixed Chinese English", matchType: .caseInsensitivePhrase, priority: 80),
        CorrectionRule(id: "recopy-test", pattern: "recopy test", replacement: "recovery test", matchType: .caseInsensitivePhrase, priority: 80),
        CorrectionRule(id: "recopy", pattern: "recopy", replacement: "recovery", matchType: .wordBoundaryPhrase, contextKeywords: ["test"], priority: 80),
    ]

    public init() {
        // Start with builtin rules
        self.allRules = builtinRules.sorted { $0.priority > $1.priority }
        logger.info("PersonalTranscriptCorrectionEngine initialized with \(self.builtinRules.count) builtin rules")
    }

    public func loadUserCorrections() async throws {
        let url = URL(fileURLWithPath: PersonalTranscriptCorrectionEngine.userCorrectionsPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.debug("No user corrections file exists at \(url.path)")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let userCorrections = try JSONDecoder().decode(UserCorrectionsFile.self, from: data)

            let parsedRules = userCorrections.replacements.compactMap { replacement -> CorrectionRule? in
                guard let matchType = CorrectionMatchType(rawValue: replacement.match) else {
                    logger.warning("Invalid match type '\(replacement.match)' for rule \(replacement.id); skipping")
                    return nil
                }

                return CorrectionRule(
                    id: replacement.id,
                    pattern: replacement.from,
                    replacement: replacement.to,
                    matchType: matchType,
                    priority: replacement.priority ?? 50 // User rules default to lower priority than builtin
                )
            }

            self.userRules = parsedRules
            self.rebuildAllRules()
            logger.info("Loaded \(parsedRules.count) user correction rules")

        } catch let error as DecodingError {
            logger.error("Invalid user corrections JSON: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Failed to load user corrections: \(error.localizedDescription)")
            throw error
        }
    }

    public func reloadUserCorrections() async {
        do {
            try await loadUserCorrections()
        } catch {
            logger.error("Reload failed: \(error.localizedDescription); continuing with builtin rules only")
        }
    }

    public func correct(_ transcript: String) -> CorrectionResult {
        guard !transcript.isEmpty else {
            logger.debug("Empty transcript; nothing to correct")
            return CorrectionResult(rawTranscript: transcript, correctedTranscript: transcript, appliedCorrections: [])
        }

        var corrected = transcript
        var appliedCorrections: [AppliedCorrection] = []

        // Apply rules in priority order (highest first)
        for rule in allRules {
            let matches = findMatches(for: rule, in: corrected)

            for matchRange in matches.reversed() { // Reverse to preserve ranges
                let originalText = String(corrected[matchRange])

                // Apply the correction
                corrected.replaceSubrange(matchRange, with: rule.replacement)

                // Record the applied correction
                let correction = AppliedCorrection(
                    originalText: originalText,
                    replacementText: rule.replacement,
                    ruleIdentifier: rule.id,
                    range: matchRange
                )
                appliedCorrections.append(correction)

                logger.debug("Applied rule '\(rule.id)': '\(originalText)' → '\(rule.replacement)'")
            }
        }

        // Sort corrections by their original position (for logging)
        appliedCorrections.sort { correction1, correction2 in
            correction1.range.lowerBound < correction2.range.lowerBound
        }

        let result = CorrectionResult(
            rawTranscript: transcript,
            correctedTranscript: corrected,
            appliedCorrections: appliedCorrections
        )

        if result.didChange {
            logger.info("Corrected transcript: \(appliedCorrections.count) corrections applied")
        }

        return result
    }

    /// Find all matches for a rule in the text
    private func findMatches(for rule: CorrectionRule, in text: String) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []

        switch rule.matchType {
        case .exactPhrase:
            if let range = text.range(of: rule.pattern) {
                matches.append(range)
            }

        case .caseInsensitivePhrase:
            let lowercaseText = text.lowercased()
            let lowercasePattern = rule.pattern.lowercased()
            var searchStart = lowercaseText.startIndex

            while let range = lowercaseText.range(of: lowercasePattern, range: searchStart..<lowercaseText.endIndex) {
                // Map back to original text indices - safe since same string length
                let offsetLower = lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound)
                let offsetUpper = lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound)
                let originalRange = text.index(text.startIndex, offsetBy: offsetLower)..<text.index(text.startIndex, offsetBy: offsetUpper)
                matches.append(originalRange)
                searchStart = range.upperBound
            }

        case .wordBoundaryPhrase:
            // Use word boundary regex
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: rule.pattern) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let textRange = NSRange(text.startIndex..., in: text)
                let nsMatches = regex.matches(in: text, range: textRange)

                for nsMatch in nsMatches {
                    if let range = Range(nsMatch.range, in: text) {
                        // Check context keywords if required
                        if let keywords = rule.contextKeywords {
                            let context = extractContext(for: range, in: text)
                            if keywords.contains(where: { context.lowercased().contains($0.lowercased()) }) {
                                matches.append(range)
                            }
                        } else {
                            matches.append(range)
                        }
                    }
                }
            }

        case .contextualPhrase:
            // First find the pattern, then check context
            let lowercaseText = text.lowercased()
            let lowercasePattern = rule.pattern.lowercased()
            var searchStart = lowercaseText.startIndex

            while let range = lowercaseText.range(of: lowercasePattern, range: searchStart..<lowercaseText.endIndex) {
                // Map back to original text indices - safe since same string length
                let offsetLower = lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound)
                let offsetUpper = lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound)
                let originalRange = text.index(text.startIndex, offsetBy: offsetLower)..<text.index(text.startIndex, offsetBy: offsetUpper)

                // Check if context keywords are present nearby
                if let keywords = rule.contextKeywords {
                    let context = extractContext(for: originalRange, in: text, windowSize: 50)
                    if keywords.contains(where: { context.lowercased().contains($0.lowercased()) }) {
                        matches.append(originalRange)
                    }
                } else {
                    matches.append(originalRange)
                }

                searchStart = range.upperBound
            }
        }

        return matches
    }

    /// Extract surrounding context for a range
    private func extractContext(for range: Range<String.Index>, in text: String, windowSize: Int = 30) -> String {
        let startIndex = text.index(range.lowerBound, offsetBy: -min(windowSize, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let endIndex = text.index(range.upperBound, offsetBy: min(windowSize, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        return String(text[startIndex..<endIndex])
    }

    /// Rebuild the combined rules list with user rules appended
    private func rebuildAllRules() {
        self.allRules = (builtinRules + userRules).sorted { $0.priority > $1.priority }
    }
}

/// User corrections file schema
struct UserCorrectionsFile: Codable {
    let version: Int
    let replacements: [UserReplacement]

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case replacements = "replacements"
    }
}

/// A single user-defined replacement
struct UserReplacement: Codable {
    let id: String
    let from: String
    let to: String
    let match: String
    let priority: Int?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case from = "from"
        case to = "to"
        case match = "match"
        case priority = "priority"
    }
}