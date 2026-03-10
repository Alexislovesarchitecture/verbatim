// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Verbatim",
  platforms: [
    .macOS("26.0"),
  ],
  products: [
    .executable(name: "Verbatim", targets: ["Verbatim"]),
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "Verbatim",
      dependencies: [],
      path: "Verbatim",
      exclude: [
        "Assets.xcassets",
      ],
      resources: [
        .process("Resources")
      ],
      linkerSettings: [
        .linkedLibrary("sqlite3"),
        .linkedFramework("Carbon"),
      ]
    ),
    .testTarget(
      name: "VerbatimTests",
      dependencies: ["Verbatim"],
      path: "NativeTests"
    ),
  ]
)
