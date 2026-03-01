import Foundation

@MainActor
protocol CaptureRepository {
    func all() -> [CaptureRecord]
    func filtered(status: CaptureStatus?) -> [CaptureRecord]
    func latest() -> CaptureRecord?
    func add(_ record: CaptureRecord)
    func update(_ record: CaptureRecord)
    func delete(_ record: CaptureRecord)
    func deleteAll()
    func purge(before date: Date)
}

protocol DictionaryRepository {
    func all(scope: DictionaryScope?) -> [DictionaryEntry]
    func search(_ query: String, scope: DictionaryScope?) -> [DictionaryEntry]
    func add(_ entry: DictionaryEntry)
    func update(_ entry: DictionaryEntry)
    func delete(_ entry: DictionaryEntry)
}

protocol SnippetRepository {
    func all(scope: SnippetScope?) -> [SnippetEntry]
    func search(_ query: String, scope: SnippetScope?) -> [SnippetEntry]
    func add(_ entry: SnippetEntry)
    func update(_ entry: SnippetEntry)
    func delete(_ entry: SnippetEntry)
}

protocol StyleRepository {
    func all() -> [StyleProfile]
    func profile(for category: StyleCategory) -> StyleProfile?
    func upsert(_ profile: StyleProfile)
}

protocol NoteRepository {
    func all() -> [NoteEntry]
    func add(_ note: NoteEntry)
    func update(_ note: NoteEntry)
    func delete(_ note: NoteEntry)
    func find(_ id: UUID) -> NoteEntry?
}

@MainActor
protocol SettingsRepository {
    func settings() -> AppSettings
    func behaviorSettings() -> LocalBehaviorSettings
    func save(settings: AppSettings)
    func save(behavior: LocalBehaviorSettings)
}
