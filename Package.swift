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
        .library(name: "WisentErrors", targets: ["WisentErrors"])
    ],
    targets: [
        .target(name: "WisentErrors", path: "swift/Sources/WisentErrors")
    ]
)
