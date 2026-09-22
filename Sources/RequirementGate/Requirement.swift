import Foundation

/// How binding a clause is. Modality drives gate policy: a missed `.must` blocks,
/// a missed `.should` reports.
public enum RequirementModality: String, Sendable, Codable, CaseIterable {
    /// "must", "shall", "required", "has to", and bare imperative acceptance criteria.
    case must
    /// "should", "prefer", "ideally", "where possible".
    case should
    /// Clauses whose applicability is gated ("if", "unless", "when", "whichever").
    /// Kept separate because a conditional branch is the easiest requirement to
    /// implement halfway — the happy path lands, the guard does not.
    case conditional

    /// Strength ordering used when de-duplicating clauses that normalise identically.
    var strength: Int {
        switch self {
        case .must: return 3
        case .conditional: return 2
        case .should: return 1
        }
    }
}

/// Where in the ticket a requirement came from. Retained so a reviewer can jump from
/// a red line in the report back to the sentence that produced it.
public enum RequirementOrigin: Sendable, Equatable, Codable {
    case acceptanceCriterion(line: Int)
    case listItem(line: Int)
    case prose(line: Int, sentence: Int)

    public var line: Int {
        switch self {
        case .acceptanceCriterion(let line): return line
        case .listItem(let line): return line
        case .prose(let line, _): return line
        }
    }

    public var label: String {
        switch self {
        case .acceptanceCriterion: return "acceptance criterion"
        case .listItem: return "list item"
        case .prose: return "prose"
        }
    }
}

/// One atomic, checkable claim taken from a ticket.
public struct Requirement: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    /// The clause verbatim, minus list markers. Shown in the report so nobody has to
    /// trust the extractor's paraphrase — there is none.
    public let text: String
    public let modality: RequirementModality
    public let origin: RequirementOrigin
    public let terms: [String]

    public init(
        id: String,
        text: String,
        modality: RequirementModality,
        origin: RequirementOrigin,
        terms: [String]
    ) {
        self.id = id
        self.text = text
        self.modality = modality
        self.origin = origin
        self.terms = terms
    }

    /// A clause made entirely of stop words cannot be scored. It is reported as
    /// `.unscorable` rather than `.missed`, because "the tool could not read this"
    /// and "the change does not do this" are different messages to a reviewer.
    public var isScorable: Bool { !terms.isEmpty }

    /// Order-independent key used to collapse clauses that say the same thing twice.
    var signature: String { terms.sorted().joined(separator: "|") }
}
