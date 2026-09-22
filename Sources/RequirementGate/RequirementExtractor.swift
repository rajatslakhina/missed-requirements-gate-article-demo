import Foundation

/// Turns ticket prose into atomic requirements.
///
/// The extractor is conservative by design. A false split invents a requirement that
/// will be reported missing on every run forever, which teaches the team to ignore the
/// gate; a false merge hides exactly one item and is caught the first time someone
/// reads the clause. Those costs are not symmetric, so neither are the rules.
public struct RequirementExtractor: Sendable {

    public struct Options: Sendable {
        /// Split clauses joined by ", and" / "; and" / ";" into separate requirements.
        public var splitCoordinatedClauses: Bool
        /// Each side of a split must carry at least this many content terms, otherwise
        /// the clause is left whole.
        public var minimumTermsPerSide: Int
        /// Prose sentences are only promoted to requirements when they contain a modal
        /// cue. List items and acceptance criteria are promoted unconditionally.
        public var requireModalCueInProse: Bool

        public init(
            splitCoordinatedClauses: Bool = true,
            minimumTermsPerSide: Int = 2,
            requireModalCueInProse: Bool = true
        ) {
            self.splitCoordinatedClauses = splitCoordinatedClauses
            self.minimumTermsPerSide = minimumTermsPerSide
            self.requireModalCueInProse = requireModalCueInProse
        }

        public static let `default` = Options()
    }

    private static let mustCues = ["must", "shall", "required", "requires", "has to", "have to", "needs to", "need to"]
    private static let shouldCues = ["should", "prefer", "ideally", "where possible", "nice to have"]
    private static let conditionalCues = ["if ", "unless ", "when ", "whenever ", "whichever", "otherwise", "except when", "in case"]

    private static let criteriaHeaders = [
        "acceptance criteria", "acceptance criterion", "requirements", "done when",
        "definition of done", "must have", "scope"
    ]

    private static let listMarkers = ["- [ ]", "- [x]", "-", "*", "+", "•"]

    private let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    public func extract(from ticket: String) -> [Requirement] {
        var clauses: [(text: String, origin: RequirementOrigin)] = []
        var inCriteriaBlock = false

        let lines = ticket.components(separatedBy: .newlines)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let header = Self.criteriaHeader(in: line) {
                inCriteriaBlock = true
                // A header that also carries content ("Acceptance criteria: ships a receipt")
                // keeps its tail as a clause rather than dropping it.
                let tail = line.dropFirst(header.count).trimmingCharacters(in: CharacterSet(charactersIn: " :-—"))
                if tail.count > 2 {
                    clauses.append((tail, .acceptanceCriterion(line: lineNumber)))
                }
                continue
            }

            if let item = Self.listItemBody(in: line) {
                let origin: RequirementOrigin = inCriteriaBlock
                    ? .acceptanceCriterion(line: lineNumber)
                    : .listItem(line: lineNumber)
                clauses.append((item, origin))
                continue
            }

            // A non-empty, non-list line ends an acceptance-criteria block.
            inCriteriaBlock = false

            for (index, sentence) in Self.sentences(in: line).enumerated() {
                let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                guard trimmed.count > 2 else { continue }
                if options.requireModalCueInProse, !Self.containsModalCue(trimmed) { continue }
                clauses.append((trimmed, .prose(line: lineNumber, sentence: index + 1)))
            }
        }

        var requirements: [Requirement] = []
        var seenSignatures: [String: Int] = [:]

        for clause in clauses {
            let pieces = options.splitCoordinatedClauses
                ? split(clause.text)
                : [clause.text]

            for piece in pieces {
                let text = piece.trimmingCharacters(in: CharacterSet(charactersIn: " \t.,;:"))
                guard !text.isEmpty else { continue }
                let terms = Lexicon.terms(in: text)
                let modality = Self.modality(of: text)
                let candidate = Requirement(
                    id: "R\(requirements.count + 1)",
                    text: text,
                    modality: modality,
                    origin: clause.origin,
                    terms: terms
                )

                // De-duplicate on the normalised term set; keep the stronger modality.
                if !candidate.signature.isEmpty, let existingIndex = seenSignatures[candidate.signature] {
                    guard requirements.indices.contains(existingIndex) else { continue }
                    if modality.strength > requirements[existingIndex].modality.strength {
                        let existing = requirements[existingIndex]
                        requirements[existingIndex] = Requirement(
                            id: existing.id,
                            text: existing.text,
                            modality: modality,
                            origin: existing.origin,
                            terms: existing.terms
                        )
                    }
                    continue
                }

                if !candidate.signature.isEmpty {
                    seenSignatures[candidate.signature] = requirements.count
                }
                requirements.append(
                    Requirement(
                        id: "R\(requirements.count + 1)",
                        text: text,
                        modality: modality,
                        origin: clause.origin,
                        terms: terms
                    )
                )
            }
        }

        return requirements
    }

    // MARK: - Clause splitting

    /// Splits on ", and", "; and" and ";" only. Bare " and " is left alone because in
    /// ticket prose it usually joins nouns ("the rate, the tax and the gross"), not
    /// predicates, and splitting there manufactures requirements nobody wrote.
    private func split(_ clause: String) -> [String] {
        var parts = [clause]
        for separator in [", and ", "; and ", "; "] {
            parts = parts.flatMap { part -> [String] in
                let candidates = part.components(separatedBy: separator)
                guard candidates.count > 1 else { return [part] }
                let viable = candidates.allSatisfy {
                    Lexicon.terms(in: $0).count >= options.minimumTermsPerSide
                }
                return viable ? candidates : [part]
            }
        }
        return parts
    }

    // MARK: - Line classification

    private static func criteriaHeader(in line: String) -> String? {
        let lowered = line.lowercased()
        let stripped = lowered.drop { $0 == "#" || $0 == " " || $0 == "*" }
        for header in criteriaHeaders where stripped.hasPrefix(header) {
            // Return the matched span measured against the original line.
            let leading = lowered.count - stripped.count
            return String(line.prefix(leading + header.count))
        }
        return nil
    }

    private static func listItemBody(in line: String) -> String? {
        for marker in listMarkers where line.hasPrefix(marker) {
            let body = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? nil : body
        }
        // Numbered lists: "1. ", "2) "
        let leadingDigits = line.prefix { $0.isNumber }
        if !leadingDigits.isEmpty, leadingDigits.count <= 3 {
            let rest = line.dropFirst(leadingDigits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                let body = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : body
            }
        }
        return nil
    }

    /// Sentence boundaries without a full tokenizer: break after `.`/`!`/`?` when the
    /// next non-space character starts a new sentence, which keeps "e.g." intact.
    private static func sentences(in line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            current.append(character)

            if character == "." || character == "!" || character == "?" {
                let nextIndex = index + 1
                let followerIndex = index + 2
                let nextIsSpace = nextIndex < characters.count && characters[nextIndex] == " "
                let followerStartsSentence: Bool = {
                    guard followerIndex < characters.count else { return true }
                    let follower = characters[followerIndex]
                    return follower.isUppercase || follower.isNumber
                }()
                let atEnd = nextIndex >= characters.count

                if atEnd || (nextIsSpace && followerStartsSentence) {
                    result.append(current)
                    current = ""
                    index = nextIndex
                    continue
                }
            }
            index += 1
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current)
        }
        characters = []
        return result
    }

    private static func containsModalCue(_ text: String) -> Bool {
        let lowered = " " + text.lowercased() + " "
        return (mustCues + shouldCues + conditionalCues).contains { lowered.contains($0) }
    }

    static func modality(of text: String) -> RequirementModality {
        let lowered = " " + text.lowercased() + " "
        if mustCues.contains(where: { lowered.contains($0) }) { return .must }
        if shouldCues.contains(where: { lowered.contains($0) }) { return .should }
        if conditionalCues.contains(where: { lowered.contains($0) }) { return .conditional }
        // Acceptance criteria and list items are imperative by convention.
        return .must
    }
}
