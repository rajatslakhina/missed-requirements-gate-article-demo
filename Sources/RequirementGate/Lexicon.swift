import Foundation

/// Term normalisation shared by the requirement extractor and the evidence index.
///
/// Deliberately lexical, not semantic. The gate has to run on every push, offline,
/// with a stable verdict — an embedding model would make the output non-reproducible
/// across versions and turn a red gate into an argument about the model rather than
/// about the ticket.
public enum Lexicon {

    /// Words that carry no requirement content. Kept small on purpose: an aggressive
    /// stop list silently deletes requirement terms and inflates the coverage score.
    public static let defaultStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "do",
        "does", "each", "for", "from", "has", "have", "if", "in", "into", "is", "it",
        "its", "must", "need", "needs", "not", "of", "on", "once", "or", "our", "out",
        "over", "shall", "should", "so", "that", "the", "their", "them", "then",
        "there", "these", "they", "this", "to", "under", "up", "was", "we", "were",
        "when", "where", "which", "while", "will", "with", "would", "you", "your"
    ]

    /// Minimum length of a normalised term. Two-character fragments match almost
    /// anything and are the main source of false "covered" verdicts.
    public static let minimumTermLength = 3

    /// Minimum shared prefix length before two different terms are treated as related.
    public static let minimumPrefixMatch = 3

    /// How many characters longer the longer term may be before a prefix match is
    /// rejected. Without this, every three-letter stem swallows an unrelated word.
    public static let maximumPrefixLengthGap = 2

    /// Splits free text into ordered, de-duplicated, normalised content terms.
    public static func terms(in text: String, stopWords: Set<String> = defaultStopWords) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for token in tokenize(text) {
            guard let normalized = normalize(token, stopWords: stopWords) else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    /// Splits on non-alphanumerics and on camelCase / PascalCase boundaries, so that
    /// `issuedInvoiceTotal` and "issued invoice total" produce the same terms.
    /// This is what lets an identifier in a diff count as evidence for a prose clause.
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        var previous: Character?
        for character in text {
            if character.isLetter || character.isNumber {
                if let previous, previous.isLowercase, character.isUppercase {
                    flush()
                }
                current.append(character)
            } else {
                flush()
            }
            previous = character
        }
        flush()
        return tokens
    }

    /// Lowercases, stems, and rejects stop words and short fragments.
    /// Returns `nil` when the token carries no requirement content.
    public static func normalize(_ token: String, stopWords: Set<String> = defaultStopWords) -> String? {
        let lowered = token.lowercased()
        guard !lowered.isEmpty else { return nil }
        guard !stopWords.contains(lowered) else { return nil }
        let stemmed = stem(lowered)
        guard stemmed.count >= minimumTermLength else { return nil }
        guard !stopWords.contains(stemmed) else { return nil }
        return stemmed
    }

    /// Light, documented suffix stripping. Not a linguistic stemmer — the goal is only
    /// that `taxed`, `taxes` and `tax` land on one key, and that the rule set is short
    /// enough that a reviewer can predict a verdict without running the tool.
    public static func stem(_ word: String) -> String {
        var stem = word

        if stem.count > 4, stem.hasSuffix("ies") {
            stem = String(stem.dropLast(3)) + "y"
            return stem
        }
        if stem.count > 5, stem.hasSuffix("ing") {
            return String(stem.dropLast(3))
        }
        if stem.count > 4, stem.hasSuffix("ed"), !stem.hasSuffix("eed") {
            return String(stem.dropLast(2))
        }
        // Only strip "es" after a sibilant, so "taxes" -> "tax" but "lines" -> "line".
        let sibilantPlural = ["ses", "xes", "zes", "ches", "shes"]
        if stem.count > 4, sibilantPlural.contains(where: { stem.hasSuffix($0) }) {
            return String(stem.dropLast(2))
        }
        if stem.count > 3, stem.hasSuffix("s"), !stem.hasSuffix("ss"), !stem.hasSuffix("us") {
            return String(stem.dropLast(1))
        }
        return stem
    }

    /// Two terms match when they are equal, or when one is a short prefix of the other.
    ///
    /// Prefix matching exists because suffix stripping cannot reconcile `price` with
    /// `priced` (which stems to `pric`) without a dictionary. The length gap is what
    /// makes it safe: `pric` and `price` differ by one character and match, while `led`
    /// and `ledger` differ by three and do not.
    public static func termsMatch(
        _ lhs: String,
        _ rhs: String,
        minimumPrefix: Int = minimumPrefixMatch,
        maximumLengthGap: Int = maximumPrefixLengthGap
    ) -> Bool {
        if lhs == rhs { return true }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        guard shorter.count >= minimumPrefix else { return false }
        guard longer.count - shorter.count <= maximumLengthGap else { return false }
        return longer.hasPrefix(shorter)
    }
}
