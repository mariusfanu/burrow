// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Burrow",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BurrowCore", targets: ["BurrowCore"]),
        .executable(name: "Burrow", targets: ["Burrow"]),
    ],
    targets: [
        .target(name: "CPTY"),
        .target(name: "BurrowCore", dependencies: ["CPTY"]),
        .executableTarget(name: "Burrow", dependencies: ["BurrowCore"]),
        .testTarget(name: "BurrowCoreTests", dependencies: ["BurrowCore"]),
        .testTarget(name: "BurrowTests", dependencies: ["Burrow"]),
    ]
)
