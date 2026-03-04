// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VerbatimSwiftMVP",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "VerbatimSwiftMVP", targets: ["VerbatimSwiftMVP"]),
  ],
  targets: [
    .executableTarget(
      name: "VerbatimSwiftMVP",
      path: "Sources"
    ),
  ]
)
