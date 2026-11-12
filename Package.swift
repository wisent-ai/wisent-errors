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
    ],
    targets: [
        .target(name: "WisentErrors", path: "swift/Sources/WisentErrors"),
        .target(name: "WisentTelemetryUI", dependencies: ["WisentErrors"], path: "swift/Sources/WisentTelemetryUI"),
        // The tests live under tests/<area>/ beside the other runtimes' tests
        // of the same cause; the Swift files are named one by one.
        .testTarget(
            name: "WisentErrorsTests",
            dependencies: ["WisentErrors"],
            path: "tests",
            sources: ["envelope/BuildTests.swift", "declaration/PlaceholderTests.swift", "warnings/WarningTests.swift"]
        ),
        // Telemetry against the real Echo app collector (docs/telemetry.md).
        .testTarget(
            name: "TelemetryTests",
            dependencies: ["WisentErrors", "WisentTelemetryUI"],
            path: "tests/telemetry/swift"
        ),
    ]
)
