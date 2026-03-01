// swift-tools-version: 5.10
import PackageDescription

#if os(macOS)
let executableTargetName = "Verbatim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/Verbatim"
)
let packageTargets: [Target] = [
    executableTarget,
    .testTarget(
        name: "VerbatimTests",
        dependencies: [
            .target(name: executableTargetName)
        ],
        path: "Tests/VerbatimAppTests"
    )
]
#else
let executableTargetName = "VerbumLinuxShim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/VerbatimLinuxShim"
)
let packageTargets: [Target] = [
    executableTarget
]
#endif

let package = Package(
    name: "Verbatim",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Verbatim", targets: [executableTargetName])
    ],
    targets: packageTargets
)
