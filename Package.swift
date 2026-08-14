// swift-tools-version:5.9
//
// A package manifest at the repository root so a SwiftPM dependency resolves,
// beside the Cargo workspace and the npm manifest that exist for the same reason.
// Two native clients hold their own copies of this envelope -- oko-desktop and
// wisent-ios -- and neither can adopt a package it cannot name.

import PackageDescription

let package = Package(
    name: "wisent-errors",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "WisentErrors", targets: ["WisentErrors"])
    ],
    targets: [
        .target(name: "WisentErrors", path: "swift/Sources/WisentErrors"),
        // The conformance emitter. It prints every golden case and the derived
        // vocabulary so the harness can compare this runtime against the other
        // three byte for byte, rather than each runtime asserting its own
        // behaviour and agreeing with nobody.
        .executableTarget(name: "emit", dependencies: ["WisentErrors"], path: "swift/Sources/emit")
    ]
)
