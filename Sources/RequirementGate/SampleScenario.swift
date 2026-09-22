import Foundation

/// A ticket-plus-change-set pair used by the demo app and the tests.
public struct SampleScenario: Sendable, Equatable {
    public let name: String
    public let ticket: String
    public let changeSet: ChangeSet

    public init(name: String, ticket: String, changeSet: ChangeSet) {
        self.name = name
        self.ticket = ticket
        self.changeSet = changeSet
    }
}

public enum SampleScenarios {

    /// A deliberately ordinary billing ticket (the original task is a NestJS service;
    /// the shape is what matters here, not the stack): several clauses, one buried in a
    /// coordinated sentence, one conditional, one "should".
    ///
    /// Adapted from the sample billing task published with Real-SWE
    /// (https://withspecific.com/benchmarks/real-swe), because that task has exactly the
    /// shape this library exists for — two obligations welded into one sentence.
    public static let ticket = """
    Invoice totals are wrong for business accounts.

    Acceptance criteria
    - Each business must price its invoice using its own configured tax rate.
    - A customer holding an exemption certificate is charged no tax, whichever way \
    its business is configured.
    - The rate, the tax and the gross must appear on the issued invoice, and once an \
    invoice is settled the sale must be filed back to the ledger under that invoice number.
    - An address the tax authority refuses must be reported without failing the invoice.
    - Invoices between European parties should show both VAT registration numbers.
    """

    /// What an agent actually shipped: the happy path, one test, and no filing step.
    public static let partialChangeSet = ChangeSet(files: [
        ChangeSet.File(
            path: "Sources/Billing/TaxRateResolver.swift",
            symbols: [
                "resolveConfiguredRate(for:)",
                "BusinessTaxConfiguration",
                "exemptionCertificate"
            ],
            docComments: ["Resolves the tax rate configured on a business account."]
        ),
        ChangeSet.File(
            path: "Sources/Billing/InvoiceTotals.swift",
            symbols: [
                "applyRate(_:to:)",
                "issuedInvoiceGross",
                "issuedInvoiceTaxAmount",
                "exemptCustomerChargedNoTax"
            ]
        ),
        ChangeSet.File(
            path: "Sources/Billing/AddressValidation.swift",
            symbols: ["refusedAddressReport"]
        ),
        ChangeSet.File(
            path: "Tests/BillingTests/InvoiceTotalsTests.swift",
            testNames: [
                "testBusinessPricesInvoiceWithConfiguredRate",
                "testExemptCustomerIsChargedNoTaxWhateverBusinessConfiguration"
            ]
        )
    ])

    /// The follow-up commit: the filing code now exists, but nothing executable claims
    /// it works. This is the shape of an unverified assumption, and it is a different
    /// conversation with the author than "you forgot this entirely".
    public static let untestedChangeSet = ChangeSet(files: [
        ChangeSet.File(
            path: "Sources/Billing/TaxRateResolver.swift",
            symbols: ["resolveConfiguredRate(for:)", "BusinessTaxConfiguration", "exemptionCertificate"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/InvoiceTotals.swift",
            symbols: ["applyRate(_:to:)", "issuedInvoiceGross", "issuedInvoiceTaxAmount"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/LedgerFiling.swift",
            symbols: [
                "fileSettledSaleBackToLedger(invoiceNumber:)",
                "settledSaleFiling",
                "ledgerInvoiceNumber"
            ]
        ),
        ChangeSet.File(
            path: "Sources/Billing/AddressValidation.swift",
            symbols: ["refusedAddressReport"]
        ),
        ChangeSet.File(
            path: "Tests/BillingTests/InvoiceTotalsTests.swift",
            testNames: [
                "testBusinessPricesInvoiceWithConfiguredRate",
                "testExemptCustomerIsChargedNoTaxWhateverBusinessConfiguration"
            ]
        )
    ])

    /// The same ticket after the gaps are closed: the filing step exists and is tested,
    /// the refused-address path is tested, and the VAT line is implemented.
    public static let completeChangeSet = ChangeSet(files: [
        ChangeSet.File(
            path: "Sources/Billing/TaxRateResolver.swift",
            symbols: ["resolveConfiguredRate(for:)", "BusinessTaxConfiguration", "exemptionCertificate"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/InvoiceTotals.swift",
            symbols: ["applyRate(_:to:)", "issuedInvoiceGross", "issuedInvoiceTaxAmount"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/LedgerFiling.swift",
            symbols: ["fileSettledSaleToLedger(invoiceNumber:)", "settledSaleFiling"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/AddressValidation.swift",
            symbols: ["refusedAddressReport", "reportRefusedAddressWithoutFailingInvoice"]
        ),
        ChangeSet.File(
            path: "Sources/Billing/EuropeanVATLines.swift",
            symbols: ["bothPartyVATRegistrationNumbers"]
        ),
        ChangeSet.File(
            path: "Tests/BillingTests/InvoiceTotalsTests.swift",
            testNames: [
                "testBusinessPricesInvoiceWithConfiguredRate",
                "testExemptCustomerIsChargedNoTaxWhateverBusinessConfiguration",
                "testIssuedInvoiceShowsRateTaxAndGross",
                "testSettledSaleIsFiledBackToLedgerUnderInvoiceNumber",
                "testRefusedAddressIsReportedWithoutFailingInvoice",
                "testEuropeanPartiesShowBothVATRegistrationNumbers"
            ]
        )
    ])

    public static let partial = SampleScenario(
        name: "What the agent shipped",
        ticket: ticket,
        changeSet: partialChangeSet
    )

    public static let untested = SampleScenario(
        name: "Implemented, not tested",
        ticket: ticket,
        changeSet: untestedChangeSet
    )

    public static let complete = SampleScenario(
        name: "After the gaps are closed",
        ticket: ticket,
        changeSet: completeChangeSet
    )

    public static let all: [SampleScenario] = [partial, untested, complete]
}
