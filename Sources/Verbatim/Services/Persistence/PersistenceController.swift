import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    private let keyStore = OpenAIKeyStore()

    let modelContainer: ModelContainer
    var modelContext: ModelContext { modelContainer.mainContext }

    init(inMemory: Bool = false) {
        let schema = Schema([
            CaptureRecord.self,
            DictionaryEntry.self,
            SnippetEntry.self,
            StyleProfile.self,
            NoteEntry.self,
            LocalBehaviorSettings.self,
            AppSettings.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not initialize SwiftData container: \(error)")
        }

        if !inMemory {
            migrateLegacyJSONIfNeeded()
        }
    }

    private func migrateLegacyJSONIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "VerbatimLegacyImportCompleted") else { return }

        let context = modelContext
        if (try? context.fetchCount(FetchDescriptor<AppSettings>())) ?? 0 > 0 {
            UserDefaults.standard.set(true, forKey: "VerbatimLegacyImportCompleted")
            return
        }

        let maybeLegacy = loadLegacyState()
        let behavior = LocalBehaviorSettings(
            biasTranscriptionWithDictionary: true,
            applyReplacementsAfterTranscription: true,
            enableSnippetExpansion: true,
            globalRequireExactMatch: false
        )

        let settings = AppSettings()
        context.insert(behavior)
        context.insert(settings)

        let styleProfiles: [StyleProfile] = StyleCategory.allCases.map {
            StyleProfile(category: $0, tone: .casual)
        }
        styleProfiles.forEach(context.insert)

        if let legacy = maybeLegacy {
            importDictionary(legacy.dictionaryEntries, into: context)
            importSnippets(legacy.snippetEntries, into: context)
            importNotes(legacy.noteEntries, into: context)
            importCaptures(legacy.entries, into: context, settings: settings)
            applyLegacySettings(legacy.settings, to: settings)
        } else {
            seedStarterData(context)
        }

        do {
            try context.save()
        } catch {
            print("Verbatim migration save error: \(error)")
        }

        UserDefaults.standard.set(true, forKey: "VerbatimLegacyImportCompleted")
    }

    private func importDictionary(_ old: [LegacyDictionaryEntry], into context: ModelContext) {
        for item in old {
            let kind: DictionaryKind = item.replacement == nil || item.replacement?.isEmpty == true ? .term : .replacement
            let entry = DictionaryEntry(
                scope: .personal,
                kind: kind,
                input: item.phrase,
                output: item.replacement
            )
            context.insert(entry)
        }
    }

    private func importSnippets(_ old: [LegacySnippetEntry], into context: ModelContext) {
        for item in old {
            let entry = SnippetEntry(scope: .personal, trigger: item.trigger, content: item.expansion)
            context.insert(entry)
        }
    }

    private func importNotes(_ old: [LegacyNoteEntry], into context: ModelContext) {
        for item in old {
            context.insert(
                NoteEntry(
                    createdAt: item.createdAt,
                    updatedAt: item.createdAt,
                    title: item.title,
                    body: item.body
                )
            )
        }
    }

    private func importCaptures(_ old: [LegacyHistoryEntry], into context: ModelContext, settings: AppSettings) {
        for item in old {
                context.insert(
                    CaptureRecord(
                        createdAt: item.createdAt,
                        sourceAppName: item.destinationApp,
                        sourceBundleId: nil,
                        durationMs: Int(item.durationSeconds * 1000),
                        wordCount: item.formattedText.split(whereSeparator: { $0.isWhitespace }).count,
                        wpm: Double(item.wordsPerMinute),
                        rawText: item.rawText,
                        formattedText: item.formattedText,
                        resultStatus: {
                            switch item.result {
                            case .inserted:
                                return .inserted
                            case .clipboardOnly, .pastedViaClipboard:
                                return .clipboard
                            case .failed:
                                return .failed
                            }
                        }(),
                        errorMessage: item.inputWasSilent ? "Audio was silent." : nil,
                        audioWasSilent: item.inputWasSilent,
                        engineUsed: settings.provider == .openai ? .openai : .whispercpp,
                        wasLockedMode: false
                    )
            )
        }
    }

    private func applyLegacySettings(_ legacy: LegacySettings, to settings: AppSettings) {
        settings.provider = legacy.provider
        settings.openAIModel = OpenAITranscriptionModel(rawValue: legacy.openAIModel) ?? .gpt4oMiniTranscribe
        settings.language = legacy.languageCode
        settings.autoInsertEnabled = legacy.autoInsert
        settings.clipboardFallbackEnabled = legacy.autoPasteFallback
        settings.showCapturedToastEnabled = true
        settings.startSoundEnabled = legacy.playStartSound
        settings.stopSoundEnabled = true
        settings.doubleTapFnLockEnabled = true
        settings.overlayMeterEnabled = true
        settings.whisperBackend = .server
        settings.whisperModelId = WhisperLocalModel.defaultId.rawValue
        settings.whisperModelsDir = WhisperModelDirectory.defaultPath
        settings.whisperServerAutoStart = true
        settings.whisperLocalThreads = 4
        settings.whisperCppPath = ""
        settings.whisperModelPath = ""

        let trimmedCliPath = legacy.whisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelPath = legacy.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCliPath.isEmpty && !trimmedModelPath.isEmpty
            && FileManager.default.fileExists(atPath: (trimmedCliPath as NSString).expandingTildeInPath)
            && FileManager.default.fileExists(atPath: (trimmedModelPath as NSString).expandingTildeInPath) {
            settings.whisperBackend = .cli
            settings.whisperCppPath = trimmedCliPath
            settings.whisperModelPath = trimmedModelPath
        }

        let trimmedKey = legacy.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            settings.openAIKeyRef = ""
        } else {
            settings.openAIKeyRef = "openai-api-key"
            do {
                try keyStore.save(trimmedKey)
            } catch {
                print("Failed to restore legacy OpenAI key: \(error)")
            }
        }
    }

    private func seedStarterData(_ context: ModelContext) {
        context.insert(DictionaryEntry(scope: .personal, kind: .term, input: "Verbatim"))
        context.insert(DictionaryEntry(scope: .personal, kind: .replacement, input: "whispr", output: "Wispr"))
        context.insert(DictionaryEntry(scope: .personal, kind: .expansion, input: "btw", output: "by the way"))
        context.insert(SnippetEntry(scope: .personal, trigger: "my email", content: "alexis@studio.com"))
    }

    private func loadLegacyState() -> LegacyDump? {
        let url = legacyStateURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LegacyDump.self, from: data)
    }

    private func legacyStateURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folder = (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("Verbatim", isDirectory: true)
        return folder.appendingPathComponent("verbatim-state.json")
    }
}

private struct LegacyDump: Codable {
    let settings: LegacySettings
    let entries: [LegacyHistoryEntry]
    let dictionaryEntries: [LegacyDictionaryEntry]
    let snippetEntries: [LegacySnippetEntry]
    let noteEntries: [LegacyNoteEntry]
}

private struct LegacySettings: Codable {
    let provider: TranscriptionProvider
    let openAIAPIKey: String
    let openAIModel: String
    let whisperCLIPath: String
    let whisperModelPath: String
    let languageCode: String
    let autoInsert: Bool
    let autoPasteFallback: Bool
    let playStartSound: Bool
}

private struct LegacyHistoryEntry: Codable {
    let createdAt: Date
    let destinationApp: String
    let durationSeconds: Double
    let wordsPerMinute: Int
    let rawText: String
    let formattedText: String
    let result: LegacyInsertResult
    let inputWasSilent: Bool
}

private struct LegacyDictionaryEntry: Codable {
    let phrase: String
    let replacement: String?
    let isLearned: Bool
}

private struct LegacySnippetEntry: Codable {
    let trigger: String
    let expansion: String
}

private struct LegacyNoteEntry: Codable {
    let createdAt: Date
    let title: String
    let body: String
}

private enum LegacyInsertResult: String, Codable {
    case inserted
    case pastedViaClipboard
    case clipboardOnly
    case failed
}
