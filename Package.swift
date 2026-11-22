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
        // The package's own command line, driving the three libraries the way
        // an app drives them (docs/guides/swift-reporter.md, "The command line").
        .executable(name: "wisent-errors-swift", targets: ["wisent-errors-swift"]),
    ],
    targets: [
        .target(name: "WisentErrors", path: "swift/Sources/WisentErrors"),
        .target(name: "WisentTelemetryUI", dependencies: ["WisentErrors"], path: "swift/Sources/WisentTelemetryUI"),
        .target(name: "WisentProgram", dependencies: ["WisentErrors"], path: "swift/Sources/WisentProgram"),
        .executableTarget(
            name: "wisent-errors-swift",
            dependencies: ["WisentErrors", "WisentTelemetryUI", "WisentProgram"],
            path: "swift/Sources/wisent-errors-swift"
        ),
        // The tests live under tests/<area>/ beside the other runtimes' tests
        // of the same cause, and run wisent-errors-swift as a process from
        // the products directory beside the test bundle
        // (tests/swift-cli/CommandCase.swift): depending on it is what makes
        // `swift test` build it. Programs a run needs are real ones copied
        // into a home under .build: the node WISENT_PROGRAM_TEST_NODE names,
        // which Node.js signs, and the fleet's stado WISENT_PROGRAM_TEST_STADO
        // names; telemetry and support reach the real Echo app collector and
        // support service (docs/telemetry.md, docs/support.md).
        .testTarget(
            name: "WisentErrorsTests",
            dependencies: ["WisentErrors", "wisent-errors-swift"],
            path: "tests",
            sources: [
                "swift-cli/CommandCase.swift",
                "envelope/EnvelopeBuildTests.swift", "declaration/DeclarationRuleTests.swift",
                "warnings/WarningDeclarationTests.swift",
                "explained/ExplainedTests.swift", "explained/DescribedTests.swift",
                "program/ProgramCase.swift", "program/AdmissionTests.swift", "program/RunOutputTests.swift",
                "program/RunStopTests.swift",
                "telemetry/swift/TelemetryCase.swift", "telemetry/swift/ConsentAndStoreTests.swift",
                "telemetry/swift/DeliveryTests.swift", "telemetry/swift/SettingsWindowTests.swift",
                "telemetry/swift/SupportReportTests.swift",
            ]
        ),
    ]
)
