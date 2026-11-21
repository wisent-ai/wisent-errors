// swift-tools-version:5.9
//
// A package manifest at the repository root so a SwiftPM dependency resolves,
// beside the Cargo workspace and the npm manifest that exist for the same reason.
// Two native clients hold their own copies of this envelope -- oko-desktop and
// wisent-ios -- and neither can adopt a package it cannot name.

import PackageDescription

let package = Package(
    name: "wisent-errors",
    // iOS 13, not 16: nothing in `WisentErrors` uses an API newer than that,
    // and `wisent-ios` — one of the two clients this runtime was written for —
    // deploys to 15.8. A floor picked from taste rather than from the sources
    // refused the product it was built for.
    platforms: [.macOS(.v13), .iOS(.v13)],
    products: [
        .library(name: "WisentErrors", targets: ["WisentErrors"]),
        // The telemetry section every app's Settings window shows.
        .library(name: "WisentTelemetryUI", targets: ["WisentTelemetryUI"]),
        // A product's installed CLI and one run of it, for the macOS apps that
        // drive their product through it; it says its failures through
        // WisentErrors, so it lives beside it.
        .library(name: "WisentProgram", targets: ["WisentProgram"]),
    ],
    targets: [
        .target(name: "WisentErrors", path: "swift/Sources/WisentErrors"),
        .target(name: "WisentTelemetryUI", dependencies: ["WisentErrors"], path: "swift/Sources/WisentTelemetryUI"),
        .target(name: "WisentProgram", dependencies: ["WisentErrors"], path: "swift/Sources/WisentProgram"),
        // The tests live under tests/<area>/ beside the other runtimes' tests
        // of the same cause; the Swift files are named one by one.
        .testTarget(
            name: "WisentErrorsTests",
            dependencies: ["WisentErrors"],
            path: "tests",
            sources: [
                "envelope/EnvelopeBuildTests.swift", "declaration/DeclarationRuleTests.swift",
                "warnings/WarningDeclarationTests.swift",
                "explained/ExplainedTests.swift", "explained/DescribedTests.swift",
            ]
        ),
        // Telemetry and support reports, on disk and against the real Echo
        // app collector and support service (docs/telemetry.md, docs/support.md).
        .testTarget(
            name: "TelemetryTests",
            dependencies: ["WisentErrors", "WisentTelemetryUI"],
            path: "tests/telemetry/swift"
        ),
        // Runs of real programs copied into a home under .build: the node
        // WISENT_PROGRAM_TEST_NODE names, which Node.js signs, and the fleet's
        // stado WISENT_PROGRAM_TEST_STADO names.
        .testTarget(
            name: "WisentProgramTests",
            dependencies: ["WisentProgram"],
            path: "tests/program"
        ),
    ]
)
