// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RequirementGate",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RequirementGate", targets: ["RequirementGate"])
    ],
    targets: [
        .target(
            name: "RequirementGate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RequirementGateTests",
            dependencies: ["RequirementGate"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
