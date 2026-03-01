import Foundation

struct WhisperModelStatus: Identifiable {
    let id: String
    let path: URL
    let isDownloaded: Bool
    let fileSizeBytes: Int64?
}

enum WhisperModelManagerError: Error {
    case modelNotFound(String)
    case failedToDownload(String)
}

final class WhisperModelManager {
    struct DownloadConfig {
        let timeout: TimeInterval
        let progressBytes: ((Int64, Int64) -> Void)?
    }

    func availableModels() -> [WhisperModelDescriptor] {
        WhisperModelCatalog.allModels
    }

    func normalizeModelId(_ raw: String) -> String {
        WhisperModelCatalog.normalizedModelId(raw)
    }

    func descriptor(for modelId: String) -> WhisperModelDescriptor? {
        WhisperModelCatalog.model(for: WhisperModelCatalog.normalizedModelId(modelId))
    }

    func modelDirectory(from path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return URL(fileURLWithPath: WhisperModelDirectory.defaultPath)
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    func modelPath(for modelId: String, modelsDirectory: String) -> URL {
        let normalizedId = normalizeModelId(modelId)
        let directory = modelDirectory(from: modelsDirectory)
        guard let descriptor = descriptor(for: normalizedId) else {
            return directory.appendingPathComponent(WhisperModelCatalog.defaultModelId)
        }
        return directory.appendingPathComponent(descriptor.fileName)
    }

    func status(for modelId: String, modelsDirectory: String) -> WhisperModelStatus {
        let normalizedId = normalizeModelId(modelId)
        let file = modelPath(for: normalizedId, modelsDirectory: modelsDirectory)
        let isDownloaded: Bool
        let size: Int64?

        if let stats = try? FileManager.default.attributesOfItem(atPath: file.path),
           let fileSize = stats[.size] as? NSNumber {
            isDownloaded = fileSize.intValue > 0
            size = fileSize.int64Value
        } else {
            isDownloaded = false
            size = nil
        }

        return WhisperModelStatus(
            id: normalizedId,
            path: file,
            isDownloaded: isDownloaded,
            fileSizeBytes: size
        )
    }

    func isModelDownloaded(_ modelId: String, modelsDirectory: String) -> Bool {
        status(for: modelId, modelsDirectory: modelsDirectory).isDownloaded
    }

    func listStatuses(modelsDirectory: String) -> [WhisperModelStatus] {
        WhisperModelCatalog.allModels.map { model in
            let descriptor = descriptor(for: model.id) ?? model
            return status(for: descriptor.id, modelsDirectory: modelsDirectory)
        }
    }

    func downloadModel(
        _ modelId: String,
        modelsDirectory: String,
        config: DownloadConfig = .init(timeout: 1200, progressBytes: nil)
    ) async throws -> URL {
        let normalizedId = normalizeModelId(modelId)
        guard let descriptor = descriptor(for: normalizedId) else {
            throw WhisperModelManagerError.modelNotFound(modelId)
        }

        let directory = modelDirectory(from: modelsDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(descriptor.fileName)

        if let stats = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let existingSize = stats[.size] as? NSNumber,
           existingSize.int64Value >= 1_000_000 {
            return destination
        }

        var request = URLRequest(url: descriptor.downloadURL)
        request.timeoutInterval = config.timeout
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhisperModelManagerError.failedToDownload("HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func deleteModel(_ modelId: String, modelsDirectory: String) {
        let file = modelPath(for: modelId, modelsDirectory: modelsDirectory)
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
