import XCTest
@testable import RequirementGate

final class CoverageMatcherTests: XCTestCase {

    private let matcher = CoverageMatcher()

    private func requirement(_ text: String, modality: RequirementModality = .must) -> Requirement {
        Requirement(
            id: "R1",
            text: text,
            modality: modality,
            origin: .listItem(line: 1),
            terms: Lexicon.terms(in: text)
        )
    }

    func testTestEvidencePromotesToCovered() {
        let index = EvidenceIndex.index(ChangeSet(files: [
            ChangeSet.File(
                path: "Tests/BillingTests/LedgerTests.swift",
                testNames: ["testSettledSaleIsFiledBackToLedger"]
            )
        ]))
        let finding = matcher.evaluate(requirement("the settled sale is filed back to the ledger"), against: index)
        XCTAssertEqual(finding.verdict, .covered)
    }

    func testImplementationOnlyEvidenceStopsAtAsserted() {
        // The distinction the whole library exists to make: code says it, nothing proves it.
        let index = EvidenceIndex.index(ChangeSet(files: [
            ChangeSet.File(
                path: "Sources/Billing/LedgerFiling.swift",
                symbols: ["fileSettledSaleBackToLedger"]
            )
        ]))
        let finding = matcher.evaluate(requirement("the settled sale is filed back to the ledger"), against: index)
        XCTAssertEqual(finding.verdict, .asserted)
        XCTAssertGreaterThanOrEqual(finding.score, 0.6)
    }

    func testUnrelatedChangeSetYieldsMissed() {
        let index = EvidenceIndex.index(ChangeSet(files: [
            ChangeSet.File(path: "Sources/Profile/AvatarCropper.swift", symbols: ["cropAvatar"])
        ]))
        let finding = matcher.evaluate(requirement("the settled sale is filed back to the ledger"), against: index)
        XCTAssertEqual(finding.verdict, .missed)
        XCTAssertFalse(finding.unmatchedTerms.isEmpty)
    }

    func testEmptyChangeSetMissesEverything() {
        let index = EvidenceIndex.index(.empty)
        let finding = matcher.evaluate(requirement("the gross appears on the invoice"), against: index)
        XCTAssertEqual(finding.verdict, .missed)
        XCTAssertEqual(finding.score, 0)
        XCTAssertTrue(finding.evidence.isEmpty)
    }

    func testUnscorableClauseIsNotReportedAsMissed() {
        let stopWordsOnly = Requirement(
            id: "R1",
            text: "it is what it is",
            modality: .must,
            origin: .prose(line: 1, sentence: 1),
            terms: []
        )
        let finding = matcher.evaluate(stopWordsOnly, against: EvidenceIndex.index(.empty))
        XCTAssertEqual(finding.verdict, .unscorable)
    }

    func testEvidenceListIsCappedAndOrdered() {
        let matcher = CoverageMatcher(thresholds: .init(maximumEvidencePerRequirement: 2))
        let index = EvidenceIndex.index(ChangeSet(files: [
            ChangeSet.File(path: "Sources/Billing/A.swift", symbols: ["invoiceLedger"]),
            ChangeSet.File(path: "Sources/Billing/B.swift", symbols: ["invoiceLedger"]),
            ChangeSet.File(path: "Sources/Billing/C.swift", symbols: ["invoiceLedger"])
        ]))
        let finding = matcher.evaluate(requirement("the invoice ledger"), against: index)
        XCTAssertLessThanOrEqual(finding.evidence.count, 2)
    }
}

final class RequirementGateTests: XCTestCase {

    func testPartialChangeSetFailsAndNamesTheMissingWork() {
        let report = RequirementGate().run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        XCTAssertFalse(report.passed)
        XCTAssertFalse(report.blockingReasons.isEmpty)
        XCTAssertGreaterThan(report.count(of: .missed) + report.count(of: .asserted), 0)
    }

    func testTheBuriedLedgerFilingClauseIsTheOneThatFails() {
        let report = RequirementGate().run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        let failed = report.findings.filter { $0.verdict == .missed || $0.verdict == .asserted }
        XCTAssertTrue(
            failed.contains { $0.requirement.text.lowercased().contains("ledger") },
            "The obligation hidden in the coordinated clause is exactly the one that should surface"
        )
    }

    /// The central claim of this library, pinned so it cannot quietly regress.
    ///
    /// Left whole, the coordinated clause averages its two halves into one partial
    /// score and slips through as a tolerated "weak". Split, the unimplemented half
    /// scores on its own and blocks. Same ticket, same diff, opposite verdict.
    func testMergingTheCoordinatedClauseLetsTheGateGoGreenOnAHalfDoneTicket() {
        let merged = RequirementGate(
            extractor: RequirementExtractor(options: .init(splitCoordinatedClauses: false))
        )
        let mergedReport = merged.run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        XCTAssertEqual(mergedReport.findings.count, 5)
        XCTAssertTrue(mergedReport.passed, "Averaging the two halves hides the missing one")

        let splitReport = RequirementGate().run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        XCTAssertEqual(splitReport.findings.count, 6)
        XCTAssertFalse(splitReport.passed, "Scored on its own, the missing half blocks")
    }

    func testUntestedImplementationIsAssertedNotCovered() {
        let report = RequirementGate().run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.untestedChangeSet
        )
        XCTAssertEqual(report.count(of: .asserted), 1)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.blockingReasons.contains { $0.contains("not tested") })
    }

    func testCompleteChangeSetPasses() {
        let report = RequirementGate().run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.completeChangeSet
        )
        XCTAssertTrue(report.passed, report.renderPlainText())
    }

    func testEmptyTicketBlocksRatherThanPassingVacuously() {
        // A gate that goes green because it parsed nothing manufactures confidence.
        let report = RequirementGate().run(ticket: "", changeSet: SampleScenarios.completeChangeSet)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.blockingReasons.contains { $0.contains("No requirements") })
    }

    func testChangeSetWithNoTestsIsBlockedExplicitly() {
        let noTests = ChangeSet(files: [
            ChangeSet.File(path: "Sources/Billing/InvoiceTotals.swift", symbols: ["applyRate"])
        ])
        let report = RequirementGate().run(ticket: SampleScenarios.ticket, changeSet: noTests)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.blockingReasons.contains { $0.contains("no test files") })
    }

    func testAdvisoryPolicyNeverBlocks() {
        let report = RequirementGate(policy: .advisory).run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        XCTAssertTrue(report.passed)
        XCTAssertFalse(report.findings.isEmpty, "Advisory mode still produces every finding")
    }

    func testSummaryLineAccountsForEveryFinding() {
        let report = RequirementGate(policy: .advisory).run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        let total = CoverageVerdict.allCases.reduce(0) { $0 + report.count(of: $1) }
        XCTAssertEqual(total, report.findings.count)
        XCTAssertTrue(report.summaryLine.contains("\(report.findings.count) requirements"))
    }

    func testPlainTextReportNamesUnmatchedTerms() {
        let report = RequirementGate(policy: .advisory).run(
            ticket: SampleScenarios.ticket,
            changeSet: SampleScenarios.partialChangeSet
        )
        let text = report.renderPlainText()
        XCTAssertTrue(text.contains("no evidence for:"))
    }

    func testReportIsDeterministicAcrossRuns() {
        let gate = RequirementGate()
        let first = gate.run(ticket: SampleScenarios.ticket, changeSet: SampleScenarios.partialChangeSet)
        let second = gate.run(ticket: SampleScenarios.ticket, changeSet: SampleScenarios.partialChangeSet)
        XCTAssertEqual(first, second)
    }
}
