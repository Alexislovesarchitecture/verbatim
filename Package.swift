// swift-tools-version: 5.10
import PackageDescription

#if os(macOS)
let executableTargetName = "Verbum"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/Verbum"
)
#else
let executableTargetName = "VerbumLinuxShim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/VerbumLinuxShim"
)
#endif

let package = Package(
    name: "Verbum",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Verbum", targets: [executableTargetName])
    ],
    targets: [
        executableTarget
    ]
)
