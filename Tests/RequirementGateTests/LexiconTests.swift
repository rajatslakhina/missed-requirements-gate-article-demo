import XCTest
@testable import RequirementGate

final class LexiconTests: XCTestCase {

    func testTokenizerSplitsCamelCaseAndPunctuation() {
        let tokens = Lexicon.tokenize("issuedInvoiceGross, refused_address (report)")
        XCTAssertEqual(tokens, ["issued", "Invoice", "Gross", "refused", "address", "report"])
    }

    func testStemmerCollapsesInflectionsOntoOneKey() {
        XCTAssertEqual(Lexicon.stem("taxes"), "tax")
        XCTAssertEqual(Lexicon.stem("taxed"), "tax")
        XCTAssertEqual(Lexicon.stem("tax"), "tax")
        XCTAssertEqual(Lexicon.stem("policies"), "policy")
        XCTAssertEqual(Lexicon.stem("billing"), "bill")
    }

    func testStemmerDoesNotMangleNonSibilantPlurals() {
        // "lines" must not become "lin": the "es" rule only fires after a sibilant.
        XCTAssertEqual(Lexicon.stem("lines"), "line")
        XCTAssertEqual(Lexicon.stem("invoices"), "invoice")
        // "address" must survive the trailing-s rule.
        XCTAssertEqual(Lexicon.stem("address"), "address")
    }

    func testTermsDropStopWordsAndShortFragments() {
        let terms = Lexicon.terms(in: "The invoice must show the ledger balance")
        XCTAssertEqual(terms, ["invoice", "show", "ledger", "balance"])
    }

    func testAggressiveStemmingCanProduceAShortStem() {
        // "filed" strips to "fil". Documented rather than hidden: the prefix matcher
        // below is what reconnects it to "file".
        XCTAssertEqual(Lexicon.terms(in: "the sale is filed"), ["sale", "fil"])
        XCTAssertTrue(Lexicon.termsMatch("fil", "file"))
    }

    func testTermsAreDeduplicatedButOrderPreserved() {
        let terms = Lexicon.terms(in: "invoice invoice ledger invoice")
        XCTAssertEqual(terms, ["invoice", "ledger"])
    }

    func testPrefixMatchingBridgesWhatStemmingCannot() {
        // "priced" stems to "pric"; "price" stems to "price". Prefix matching links them.
        XCTAssertTrue(Lexicon.termsMatch("pric", "price"))
        XCTAssertTrue(Lexicon.termsMatch("price", "pric"))
    }

    func testPrefixMatchingRejectsDistantCoincidences() {
        // The length gap is the guard: "tax" and "taxonomy" differ by five characters,
        // "led" and "ledger" by three. Neither is a match.
        XCTAssertFalse(Lexicon.termsMatch("tax", "taxonomy"))
        XCTAssertFalse(Lexicon.termsMatch("led", "ledger"))
        XCTAssertFalse(Lexicon.termsMatch("in", "invoice"))
    }

    func testEmptyAndPunctuationOnlyInputProducesNoTerms() {
        XCTAssertTrue(Lexicon.terms(in: "").isEmpty)
        XCTAssertTrue(Lexicon.terms(in: "   ---  ,;  ").isEmpty)
    }
}
