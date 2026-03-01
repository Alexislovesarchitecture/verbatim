import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func settings() -> AppSettings {
        if let existing = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            normalizeIfNeeded(existing)
            return existing
        }

        let settings = AppSettings()
        normalizeIfNeeded(settings)
        context.insert(LocalBehaviorSettings())
        context.insert(settings)
        save()
        return settings
    }

    func behaviorSettings() -> LocalBehaviorSettings {
        if let existing = (try? context.fetch(FetchDescriptor<LocalBehaviorSettings>()))?.first {
            return existing
        }

        let behavior = LocalBehaviorSettings()
        context.insert(behavior)
        save()
        return behavior
    }

    func save(settings: AppSettings) {
        save()
    }

    func save(behavior: LocalBehaviorSettings) {
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    private func normalizeIfNeeded(_ settings: AppSettings) {
        settings.openAIModel = settings.openAIModel ?? .gpt4oMiniTranscribe
        settings.whisperModelId = WhisperModelCatalog.normalizedModelId(settings.whisperModelId ?? WhisperLocalModel.defaultId.rawValue)

        let cleanedModelsDir = settings.whisperModelsDir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleanedModelsDir.isEmpty {
            settings.whisperModelsDir = WhisperModelDirectory.defaultPath
        } else {
            settings.whisperModelsDir = cleanedModelsDir
        }

        if (settings.whisperLocalThreads ?? 0) <= 0 {
            settings.whisperLocalThreads = 4
        }

        if settings.whisperCppPath == "/opt/homebrew/bin/whisper-cli",
           !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/whisper-cli") {
            settings.whisperCppPath = ""
        }

        settings.whisperServerAutoStart = settings.whisperServerAutoStart ?? true

        if settings.whisperBackend == nil {
            settings.whisperBackend = .server
        }

        if settings.whisperModelPath.isEmpty {
            settings.whisperModelPath = ""
        }
    }
}
