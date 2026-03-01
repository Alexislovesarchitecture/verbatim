// swift-tools-version: 5.10
import PackageDescription

#if os(macOS)
let executableTargetName = "Verbatim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/Verbatim"
)
#else
let executableTargetName = "VerbumLinuxShim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/VerbatimLinuxShim"
)
#endif

let package = Package(
    name: "Verbatim",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Verbatim", targets: [executableTargetName])
    ],
    targets: [
        executableTarget,
        .testTarget(
            name: "VerbatimTests",
            dependencies: ["Verbatim"],
            path: "Tests/VerbatimAppTests"
        )
    ]
)
