import Foundation

struct WhisperModelDescriptor: Identifiable {
    let id: String
    let title: String
    let fileName: String
    let downloadURL: URL
    let expectedSizeBytes: Int64
    let recommended: Bool
}

enum WhisperModelCatalog {
    static let allModels: [WhisperModelDescriptor] = [
        WhisperModelDescriptor(
            id: "tiny",
            title: "Tiny",
            fileName: "ggml-tiny.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            expectedSizeBytes: 78_000_000,
            recommended: false
        ),
        WhisperModelDescriptor(
            id: "base",
            title: "Base",
            fileName: "ggml-base.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            expectedSizeBytes: 148_000_000,
            recommended: true
        ),
        WhisperModelDescriptor(
            id: "small",
            title: "Small",
            fileName: "ggml-small.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            expectedSizeBytes: 488_000_000,
            recommended: false
        ),
        WhisperModelDescriptor(
            id: "medium",
            title: "Medium",
            fileName: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            expectedSizeBytes: 1_570_000_000,
            recommended: false
        ),
        WhisperModelDescriptor(
            id: "large",
            title: "Large",
            fileName: "ggml-large-v3.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            expectedSizeBytes: 3_140_000_000,
            recommended: false
        ),
        WhisperModelDescriptor(
            id: "turbo",
            title: "Turbo",
            fileName: "ggml-large-v3-turbo.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            expectedSizeBytes: 1_670_000_000,
            recommended: false
        )
    ]

    static var modelIds: [String] { allModels.map(\.id) }

    static func model(for id: String) -> WhisperModelDescriptor? {
        allModels.first { $0.id == id }
    }

    static func normalizedModelId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty, model(for: trimmed) != nil { return trimmed }
        return WhisperLocalModel.defaultId.rawValue
    }

    static var defaultModelId: String { WhisperLocalModel.defaultId.rawValue }
}
