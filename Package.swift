// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VerbatimSwiftMVP",
  platforms: [
    .macOS("26.0"),
  ],
  products: [
    .executable(name: "VerbatimSwiftMVP", targets: ["VerbatimSwiftMVP"]),
  ],
  dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.4"),
  ],
  targets: [
    .binaryTarget(
      name: "whisper",
      path: "Vendor/whisper.xcframework"
    ),
    .executableTarget(
      name: "VerbatimSwiftMVP",
      dependencies: [
        "whisper",
        .product(name: "WhisperKit", package: "WhisperKit"),
      ],
      path: "Sources",
      exclude: [
        "VerbatimSwiftMVP/Services/AppleLocalTranscriptionService 2.swift",
        "VerbatimSwiftMVP/Services/OllamaLocalLogicService 2.swift",
        "VerbatimSwiftMVP/Services/OpenAITranscriptionService 2.swift",
        "VerbatimSwiftMVP/ViewModels/TranscriptionViewModel 2.swift",
        "VerbatimSwiftMVP/Views/ContentView 3.swift",
        "VerbatimSwiftMVP/Views/ContentView 4.swift",
      ],
      resources: [
        .process("VerbatimSwiftMVP/Resources")
      ],
      linkerSettings: [
        .linkedLibrary("sqlite3")
      ]
    ),
    .testTarget(
      name: "VerbatimSwiftMVPTests",
      dependencies: ["VerbatimSwiftMVP"],
      path: "Tests"
    ),
  ]
)
