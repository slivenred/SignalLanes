// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SignalLanes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SignalLanesCore", targets: ["SignalLanesCore"]),
        .executable(name: "SignalLanes", targets: ["SignalLanes"]),
        .executable(name: "signallanesctl", targets: ["signallanesctl"]),
        .executable(name: "SignalLanesCoreSmokeTests", targets: ["SignalLanesCoreSmokeTests"])
    ],
    targets: [
        .target(name: "SignalLanesCore"),
        .executableTarget(
            name: "SignalLanes",
            dependencies: ["SignalLanesCore"]
        ),
        .executableTarget(
            name: "signallanesctl",
            dependencies: ["SignalLanesCore"]
        ),
        .executableTarget(
            name: "SignalLanesCoreSmokeTests",
            dependencies: ["SignalLanesCore"]
        )
    ]
)
