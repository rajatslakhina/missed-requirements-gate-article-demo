import Foundation

/// What kind of claim a piece of evidence makes.
///
/// The distinction is the whole point of the library: a test name is an *executable*
/// claim that behaviour exists, a symbol name is only an *intention* that it exists,
/// and a doc comment is a claim about intent with no enforcement at all.
public enum EvidenceKind: String, Sendable, Codable, CaseIterable {
    case test
    case implementation
    case documentation

    /// Weight applied to a match from this source.
    public var weight: Double {
        switch self {
        case .test: return 1.0
        case .implementation: return 0.7
        case .documentation: return 0.4
        }
    }

    /// Only tests can promote a requirement to `.covered`.
    public var isExecutable: Bool { self == .test }
}

/// A single addressable thing in the change set that a requirement can match against.
public struct EvidenceItem: Sendable, Equatable, Codable {
    public let kind: EvidenceKind
    public let locator: String
    public let terms: [String]

    public init(kind: EvidenceKind, locator: String, text: String) {
        self.kind = kind
        self.locator = locator
        self.terms = Lexicon.terms(in: text)
    }

    public init(kind: EvidenceKind, locator: String, terms: [String]) {
        self.kind = kind
        self.locator = locator
        self.terms = terms
    }
}

/// The change under review, described structurally rather than as a raw diff.
///
/// Structure rather than diff text is a deliberate call: a diff is mostly punctuation
/// and unchanged context, and scoring against it buries every real signal in noise.
public struct ChangeSet: Sendable, Equatable, Codable {

    public struct File: Sendable, Equatable, Codable {
        public let path: String
        public let symbols: [String]
        public let testNames: [String]
        public let docComments: [String]

        public init(
            path: String,
            symbols: [String] = [],
            testNames: [String] = [],
            docComments: [String] = []
        ) {
            self.path = path
            self.symbols = symbols
            self.testNames = testNames
            self.docComments = docComments
        }

        /// Path-based test detection, so a change set produced by a script that does not
        /// know what a test is still classifies correctly.
        public var isTestFile: Bool {
            let lowered = path.lowercased()
            return lowered.contains("/tests/")
                || lowered.hasPrefix("tests/")
                || lowered.hasSuffix("tests.swift")
                || lowered.hasSuffix("test.swift")
                || lowered.contains("spec")
        }
    }

    public let files: [File]

    public init(files: [File]) {
        self.files = files
    }

    public static let empty = ChangeSet(files: [])
}

/// Flattened, searchable view of a change set.
public struct EvidenceIndex: Sendable, Equatable {
    public let items: [EvidenceItem]

    public init(items: [EvidenceItem]) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }

    public var hasExecutableEvidence: Bool { items.contains { $0.kind.isExecutable } }

    public static func index(_ changeSet: ChangeSet) -> EvidenceIndex {
        var items: [EvidenceItem] = []

        for file in changeSet.files {
            let fileIsTest = file.isTestFile

            for symbol in file.symbols where !symbol.isEmpty {
                items.append(
                    EvidenceItem(
                        kind: fileIsTest ? .test : .implementation,
                        locator: "\(file.path)#\(symbol)",
                        text: symbol
                    )
                )
            }

            // Explicit test names are always executable evidence, wherever they live.
            for testName in file.testNames where !testName.isEmpty {
                items.append(
                    EvidenceItem(kind: .test, locator: "\(file.path)#\(testName)", text: testName)
                )
            }

            for (offset, comment) in file.docComments.enumerated() where !comment.isEmpty {
                items.append(
                    EvidenceItem(
                        kind: .documentation,
                        locator: "\(file.path):doc\(offset + 1)",
                        text: comment
                    )
                )
            }

            // The path itself is weak implementation evidence — `Billing/TaxRate.swift`
            // is a real signal that tax rates were touched.
            let pathTerms = Lexicon.terms(in: file.path)
            if !pathTerms.isEmpty {
                items.append(
                    EvidenceItem(
                        kind: fileIsTest ? .test : .implementation,
                        locator: file.path,
                        terms: pathTerms
                    )
                )
            }
        }

        return EvidenceIndex(items: items)
    }
}
