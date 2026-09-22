import SwiftUI
import RequirementGate

/// Thin shell. Every line worth reading lives in the RequirementGate package,
/// which this project consumes through a local package reference (`../`), so the
/// repo clones, opens and runs in one go.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RequirementGateDemoView()
        }
    }
}
