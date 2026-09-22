import Foundation

/// The verdict for one requirement against one change set.
///
/// The four scored cases map onto the failure taxonomy that benchmarks of coding agents
/// on real codebases keep reporting: `.missed` is a missed requirement, `.asserted` is
/// an unverified assumption. Collapsing those two into one "fail" throws away the only
/// piece of information that tells a reviewer what to do next.
public enum CoverageVerdict: String, Sendable, Codable, CaseIterable {
    /// Strong lexical overlap *and* at least one executable (test) match.
    case covered
    /// Strong overlap, but nothing executable claims it. The code says it does this.
    case asserted
    /// Partial overlap. Something adjacent moved; the clause is not clearly handled.
    case weak
    /// Little or no overlap anywhere in the change set.
    case missed
    /// The clause produced no scorable terms. A tooling gap, not a coverage gap.
    case unscorable

    public var isBlockingCandidate: Bool {
        self == .missed || self == .asserted || self == .weak
    }
}

public struct RequirementFinding: Sendable, Equatable, Codable, Identifiable {
    public let requirement: Requirement
    public let verdict: CoverageVerdict
    public let score: Double
    public let matchedTerms: [String]
    public let unmatchedTerms: [String]
    public let evidence: [String]

    public var id: String { requirement.id }

    public init(
        requirement: Requirement,
        verdict: CoverageVerdict,
        score: Double,
        matchedTerms: [String],
        unmatchedTerms: [String],
        evidence: [String]
    ) {
        self.requirement = requirement
        self.verdict = verdict
        self.score = score
        self.matchedTerms = matchedTerms
        self.unmatchedTerms = unmatchedTerms
        self.evidence = evidence
    }
}

/// Scores requirements against an evidence index.
public struct CoverageMatcher: Sendable {

    public struct Thresholds: Sendable {
        /// At or above this score a requirement is considered addressed.
        public var covered: Double
        /// Below this score a requirement is considered missing outright.
        public var weak: Double
        /// Cap on how many locators a finding carries, so the report stays readable.
        public var maximumEvidencePerRequirement: Int

        public init(covered: Double = 0.60, weak: Double = 0.30, maximumEvidencePerRequirement: Int = 4) {
            self.covered = covered
            self.weak = weak
            self.maximumEvidencePerRequirement = maximumEvidencePerRequirement
        }

        public static let `default` = Thresholds()
    }

    private let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func evaluate(_ requirements: [Requirement], against index: EvidenceIndex) -> [RequirementFinding] {
        requirements.map { evaluate($0, against: index) }
    }

    public func evaluate(_ requirement: Requirement, against index: EvidenceIndex) -> RequirementFinding {
        guard requirement.isScorable else {
            return RequirementFinding(
                requirement: requirement,
                verdict: .unscorable,
                score: 0,
                matchedTerms: [],
                unmatchedTerms: [],
                evidence: []
            )
        }

        var bestWeightPerTerm: [String: Double] = [:]
        var executableTerms = Set<String>()
        var locatorScores: [String: Double] = [:]

        for item in index.items {
            var itemHits = 0
            for term in requirement.terms {
                guard item.terms.contains(where: { Lexicon.termsMatch(term, $0) }) else { continue }
                itemHits += 1
                let weight = item.kind.weight
                if weight > (bestWeightPerTerm[term] ?? 0) {
                    bestWeightPerTerm[term] = weight
                }
                if item.kind.isExecutable {
                    executableTerms.insert(term)
                }
            }
            if itemHits > 0 {
                let contribution = Double(itemHits) * item.kind.weight
                locatorScores[item.locator] = max(locatorScores[item.locator] ?? 0, contribution)
            }
        }

        let termCount = Double(requirement.terms.count)
        let earned = requirement.terms.reduce(0.0) { $0 + (bestWeightPerTerm[$1] ?? 0) }
        let score = termCount > 0 ? earned / termCount : 0

        let matched = requirement.terms.filter { bestWeightPerTerm[$0] != nil }
        let unmatched = requirement.terms.filter { bestWeightPerTerm[$0] == nil }

        let evidence = locatorScores
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(max(0, thresholds.maximumEvidencePerRequirement))
            .map(\.key)

        let verdict: CoverageVerdict
        if score >= thresholds.covered {
            // A requirement is only "covered" when something executable touches it.
            // Half the terms matching test names is enough — a test rarely names every
            // noun in a sentence, and demanding that just pushes teams to write
            // sentence-shaped test names.
            let executableShare = termCount > 0 ? Double(executableTerms.count) / termCount : 0
            verdict = executableShare >= 0.5 ? .covered : .asserted
        } else if score >= thresholds.weak {
            verdict = .weak
        } else {
            verdict = .missed
        }

        return RequirementFinding(
            requirement: requirement,
            verdict: verdict,
            score: score,
            matchedTerms: matched,
            unmatchedTerms: unmatched,
            evidence: Array(evidence)
        )
    }
}
