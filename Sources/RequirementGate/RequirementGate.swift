import Foundation

/// What turns findings into a red or green build.
public struct GatePolicy: Sendable {
    /// A `.must` with no matching evidence blocks.
    public var failOnMissedMust: Bool
    /// A `.must` that only implementation code claims — nothing executable — blocks.
    /// This is the setting teams argue about, and the one that catches the failure
    /// mode where an agent writes the feature and no test for it.
    public var failOnAssertedMust: Bool
    /// More than this many partially-covered `.must` clauses blocks.
    public var maximumWeakMusts: Int
    /// A ticket that produced no requirements blocks.
    ///
    /// A gate that goes green because it parsed nothing is worse than no gate: it
    /// manufactures confidence. This defaults to `true` and should stay there.
    public var failOnEmptyExtraction: Bool
    /// A change set with no test files at all blocks.
    public var requireExecutableEvidence: Bool

    public init(
        failOnMissedMust: Bool = true,
        failOnAssertedMust: Bool = true,
        maximumWeakMusts: Int = 2,
        failOnEmptyExtraction: Bool = true,
        requireExecutableEvidence: Bool = true
    ) {
        self.failOnMissedMust = failOnMissedMust
        self.failOnAssertedMust = failOnAssertedMust
        self.maximumWeakMusts = maximumWeakMusts
        self.failOnEmptyExtraction = failOnEmptyExtraction
        self.requireExecutableEvidence = requireExecutableEvidence
    }

    public static let `default` = GatePolicy()

    /// Report-only: every finding is produced, nothing blocks. The right starting
    /// posture when introducing the gate to a team that has not seen it before.
    public static let advisory = GatePolicy(
        failOnMissedMust: false,
        failOnAssertedMust: false,
        maximumWeakMusts: .max,
        failOnEmptyExtraction: false,
        requireExecutableEvidence: false
    )
}

public struct GateReport: Sendable, Equatable, Codable {
    public let findings: [RequirementFinding]
    public let blockingReasons: [String]

    public init(findings: [RequirementFinding], blockingReasons: [String]) {
        self.findings = findings
        self.blockingReasons = blockingReasons
    }

    public var passed: Bool { blockingReasons.isEmpty }

    public func count(of verdict: CoverageVerdict) -> Int {
        findings.filter { $0.verdict == verdict }.count
    }

    public func findings(for verdict: CoverageVerdict) -> [RequirementFinding] {
        findings.filter { $0.verdict == verdict }
    }

    /// One line, for a CI annotation or a PR comment header.
    public var summaryLine: String {
        let status = passed ? "PASS" : "FAIL"
        return "\(status) — \(findings.count) requirements: "
            + "\(count(of: .covered)) covered, "
            + "\(count(of: .asserted)) asserted, "
            + "\(count(of: .weak)) weak, "
            + "\(count(of: .missed)) missed, "
            + "\(count(of: .unscorable)) unscorable"
    }

    /// Plain-text report suitable for a CI log or a PR comment body.
    public func renderPlainText() -> String {
        var lines = [summaryLine, ""]
        for reason in blockingReasons {
            lines.append("BLOCKING: \(reason)")
        }
        if !blockingReasons.isEmpty { lines.append("") }

        for finding in findings {
            let verdict = finding.verdict.rawValue.uppercased()
            let percent = Int((finding.score * 100).rounded())
            lines.append("[\(verdict)] \(finding.requirement.id) (\(finding.requirement.modality.rawValue), \(percent)%) \(finding.requirement.text)")
            if !finding.unmatchedTerms.isEmpty {
                lines.append("    no evidence for: \(finding.unmatchedTerms.joined(separator: ", "))")
            }
            if let locator = finding.evidence.first {
                lines.append("    nearest evidence: \(locator)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// End-to-end: ticket text plus a change set in, gate report out.
///
/// Deterministic and offline. The same ticket and the same change set produce the same
/// verdict on every machine and every run — which is the property that lets a team argue
/// about the requirement instead of about the tool.
public struct RequirementGate: Sendable {
    private let extractor: RequirementExtractor
    private let matcher: CoverageMatcher
    private let policy: GatePolicy

    public init(
        extractor: RequirementExtractor = RequirementExtractor(),
        matcher: CoverageMatcher = CoverageMatcher(),
        policy: GatePolicy = .default
    ) {
        self.extractor = extractor
        self.matcher = matcher
        self.policy = policy
    }

    public func run(ticket: String, changeSet: ChangeSet) -> GateReport {
        let requirements = extractor.extract(from: ticket)
        let index = EvidenceIndex.index(changeSet)
        let findings = matcher.evaluate(requirements, against: index)

        var reasons: [String] = []

        if requirements.isEmpty, policy.failOnEmptyExtraction {
            reasons.append("No requirements could be extracted from the ticket — the gate cannot vouch for this change.")
        }

        if policy.requireExecutableEvidence, !requirements.isEmpty, !index.hasExecutableEvidence {
            reasons.append("The change set contains no test files, so no requirement can reach 'covered'.")
        }

        let missedMusts = findings.filter { $0.verdict == .missed && $0.requirement.modality == .must }
        if policy.failOnMissedMust, !missedMusts.isEmpty {
            let ids = missedMusts.map(\.requirement.id).joined(separator: ", ")
            reasons.append("\(missedMusts.count) required clause(s) have no matching evidence: \(ids).")
        }

        let assertedMusts = findings.filter { $0.verdict == .asserted && $0.requirement.modality == .must }
        if policy.failOnAssertedMust, !assertedMusts.isEmpty {
            let ids = assertedMusts.map(\.requirement.id).joined(separator: ", ")
            reasons.append("\(assertedMusts.count) required clause(s) are implemented but not tested: \(ids).")
        }

        let weakMusts = findings.filter { $0.verdict == .weak && $0.requirement.modality == .must }
        if weakMusts.count > policy.maximumWeakMusts {
            reasons.append("\(weakMusts.count) required clause(s) are only partially covered (limit \(policy.maximumWeakMusts)).")
        }

        return GateReport(findings: findings, blockingReasons: reasons)
    }
}
