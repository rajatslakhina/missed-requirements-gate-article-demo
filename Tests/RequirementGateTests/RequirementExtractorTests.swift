import XCTest
@testable import RequirementGate

final class RequirementExtractorTests: XCTestCase {

    private let extractor = RequirementExtractor()

    func testAcceptanceCriteriaBulletsBecomeMustRequirements() {
        let ticket = """
        Acceptance criteria
        - Each business prices its invoice using its own configured rate.
        - Exempt customers are charged no tax.
        """
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 2)
        XCTAssertTrue(requirements.allSatisfy { $0.modality == .must })
        XCTAssertEqual(requirements.first?.origin.label, "acceptance criterion")
    }

    func testCoordinatedClauseIsSplitIntoTwoRequirements() {
        // The failure mode this library exists for: two obligations in one sentence.
        let ticket = """
        - The rate must appear on the invoice, and the sale must be filed to the ledger.
        """
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 2)
        XCTAssertTrue(requirements.contains { $0.text.contains("filed to the ledger") })
    }

    func testBareAndIsNotSplitBecauseItUsuallyJoinsNouns() {
        let ticket = "- The rate, the tax and the gross must appear on the invoice."
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 1, "A noun-phrase conjunction must not manufacture a second requirement")
    }

    func testCoordinatedClauseIsLeftWholeWhenOneSideIsTooThin() {
        // "and it works" carries fewer than two content terms, so no split.
        let ticket = "- The invoice must show the gross amount, and it must work."
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 1)
    }

    func testModalityDetection() {
        XCTAssertEqual(RequirementExtractor.modality(of: "the invoice must show the gross"), .must)
        XCTAssertEqual(RequirementExtractor.modality(of: "invoices should show VAT numbers"), .should)
        XCTAssertEqual(RequirementExtractor.modality(of: "if the authority refuses the address, report it"), .conditional)
    }

    func testProseWithoutAModalCueIsIgnored() {
        let ticket = "Invoice totals are wrong for business accounts."
        XCTAssertTrue(extractor.extract(from: ticket).isEmpty)
    }

    func testProseWithAModalCueIsPromoted() {
        let ticket = "Every business must settle its own tax rate before the invoice is issued."
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 1)
        XCTAssertEqual(requirements.first?.modality, .must)
    }

    func testDuplicateClausesCollapseAndKeepTheStrongerModality() {
        let ticket = """
        - Invoices should show both VAT registration numbers.
        - Invoices must show both VAT registration numbers.
        """
        let requirements = extractor.extract(from: ticket)
        XCTAssertEqual(requirements.count, 1)
        XCTAssertEqual(requirements.first?.modality, .must)
    }

    func testNumberedListsAreRecognised() {
        let ticket = """
        1. The gross must appear on the invoice.
        2) The sale must be filed to the ledger.
        """
        XCTAssertEqual(extractor.extract(from: ticket).count, 2)
    }

    func testEmptyTicketProducesNoRequirements() {
        XCTAssertTrue(extractor.extract(from: "").isEmpty)
        XCTAssertTrue(extractor.extract(from: "\n\n   \n").isEmpty)
    }

    func testRequirementIdentifiersAreSequentialAndUnique() {
        let requirements = extractor.extract(from: SampleScenarios.ticket)
        let ids = requirements.map(\.id)
        XCTAssertEqual(ids, (1...requirements.count).map { "R\($0)" })
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSampleTicketSplitsTheBuriedFilingObligation() {
        let requirements = extractor.extract(from: SampleScenarios.ticket)
        XCTAssertTrue(
            requirements.contains { $0.text.lowercased().contains("filed back to the ledger") },
            "The filing obligation is hidden inside a coordinated clause and must be surfaced separately"
        )
    }
}
