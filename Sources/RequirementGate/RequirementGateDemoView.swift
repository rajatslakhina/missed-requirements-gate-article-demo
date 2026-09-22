#if canImport(SwiftUI)
import SwiftUI

/// The demo surface ships with the library, so the `Demo.xcodeproj` app is a thin
/// `@main` shell and everything worth reading lives in the package.
public struct RequirementGateDemoView: View {

    @State private var scenarioIndex = 0
    @State private var splitCoordinatedClauses = true

    public init() {}

    private var scenario: SampleScenario {
        let scenarios = SampleScenarios.all
        guard scenarios.indices.contains(scenarioIndex) else { return SampleScenarios.partial }
        return scenarios[scenarioIndex]
    }

    private func makeReport() -> GateReport {
        RequirementGate(
            extractor: RequirementExtractor(
                options: .init(splitCoordinatedClauses: splitCoordinatedClauses)
            )
        )
        .run(ticket: scenario.ticket, changeSet: scenario.changeSet)
    }

    public var body: some View {
        let report = makeReport()

        NavigationStack {
            List {
                Section {
                    Picker("Change set", selection: $scenarioIndex) {
                        ForEach(SampleScenarios.all.indices, id: \.self) { index in
                            Text(SampleScenarios.all[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Split coordinated clauses", isOn: $splitCoordinatedClauses)
                } header: {
                    Text("Input")
                } footer: {
                    Text("Turn splitting off to watch the same diff pass with a requirement missing.")
                }

                Section("Verdict") {
                    HStack(spacing: 10) {
                        Image(systemName: report.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                            .font(.title2)
                            .foregroundStyle(report.passed ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.passed ? "Gate passed" : "Gate blocked")
                                .font(.headline)
                            Text("\(report.findings.count) requirements extracted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(report.blockingReasons.enumerated()), id: \.offset) { _, reason in
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(Color.red)
                    }
                }

                Section("Requirements") {
                    ForEach(report.findings) { finding in
                        FindingRow(finding: finding)
                    }
                }
            }
            .navigationTitle("Requirement Gate")
        }
    }
}

private struct FindingRow: View {
    let finding: RequirementFinding

    private var tint: Color {
        switch finding.verdict {
        case .covered: return .green
        case .asserted: return .orange
        case .weak: return .yellow
        case .missed: return .red
        case .unscorable: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(finding.verdict.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
                Text(finding.requirement.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(finding.requirement.modality.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((finding.score * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(finding.requirement.text)
                .font(.subheadline)

            if !finding.unmatchedTerms.isEmpty {
                Text("no evidence for: " + finding.unmatchedTerms.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let locator = finding.evidence.first {
                Text(locator)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RequirementGateDemoView()
}
#endif
