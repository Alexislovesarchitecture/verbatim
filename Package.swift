// swift-tools-version: 5.10
import PackageDescription

#if os(macOS)
let executableTargetName = "Verbatim"
let executableTarget: Target = .executableTarget(
    name: executableTargetName,
    path: "Sources/Verbatim",
    exclude: [
        "App/VerbatimStore.swift",
        "Models/Models.swift",
        "Services/DataStore.swift",
        "Services/FormatterPipeline.swift",
        "Services/HotkeyMonitor.swift",
        "Services/InsertionService.swift",
        "Services/OverlayController.swift",
        "Services/TranscriptionEngines.swift",
        "Views/DictionaryView.swift",
        "Views/HomeView.swift",
        "Views/NotesView.swift",
        "Views/RootView.swift",
        "Views/SettingsView.swift",
        "Views/SnippetsView.swift",
        "Views/StyleView.swift"
    ]
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
