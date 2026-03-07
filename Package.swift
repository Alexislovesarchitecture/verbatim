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
  targets: [
    .executableTarget(
      name: "VerbatimSwiftMVP",
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
