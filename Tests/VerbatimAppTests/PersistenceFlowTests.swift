import XCTest
import Foundation
import SwiftData
@testable import Verbatim

@MainActor
final class PersistenceFlowTests: XCTestCase {
    private func inMemoryContext() -> ModelContext {
        let schema = Schema([
            CaptureRecord.self,
            DictionaryEntry.self,
            SnippetEntry.self,
            StyleProfile.self,
            NoteEntry.self,
            LocalBehaviorSettings.self,
            AppSettings.self
        ])
        let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return container.mainContext
    }

    func testDictionaryCrudAndSearch() {
        let context = inMemoryContext()
        let repository = SwiftDataDictionaryRepository(context: context)

        repository.add(DictionaryEntry(scope: .personal, kind: .replacement, input: "btw", output: "by the way", createdAt: .now, updatedAt: .now))
        repository.add(DictionaryEntry(scope: .personal, kind: .replacement, input: "ty", output: "thank you", createdAt: .now, updatedAt: .now))

        XCTAssertEqual(repository.all(scope: .personal).count, 2)
        XCTAssertEqual(repository.search("thank", scope: .personal).count, 1)

        repository.delete(repository.all(scope: .personal).first!)
        XCTAssertEqual(repository.all(scope: .personal).count, 1)
    }

    func testSnippetAndNoteCrud() {
        let context = inMemoryContext()
        let snippetRepo = SwiftDataSnippetRepository(context: context)
        snippetRepo.add(SnippetEntry(scope: .personal, trigger: "sig", content: "signature", createdAt: .now, updatedAt: .now))
        snippetRepo.add(SnippetEntry(scope: .sharedStub, trigger: "tbh", content: "to be honest", createdAt: .now, updatedAt: .now))

        XCTAssertEqual(snippetRepo.all(scope: .personal).count, 1)
        XCTAssertEqual(snippetRepo.search("signature", scope: nil).count, 1)
        snippetRepo.delete(snippetRepo.all(scope: nil).first { $0.trigger == "sig" }!)
        XCTAssertEqual(snippetRepo.all(scope: .personal).count, 0)

        let noteRepo = SwiftDataNoteRepository(context: context)
        noteRepo.add(NoteEntry(title: "Draft", body: "hello world"))
        let note = noteRepo.all().first!
        note.title = "Updated"
        noteRepo.update(note)
        XCTAssertEqual(noteRepo.all().first?.title, "Updated")
        noteRepo.delete(noteRepo.all().first!)
        XCTAssertTrue(noteRepo.all().isEmpty)
    }

    func testHistoryRetention() {
        let context = inMemoryContext()
        let captureRepo = SwiftDataCaptureRepository(context: context)
        let now = Date()
        let old = now.addingTimeInterval(-60 * 60 * 24 * 10)
        captureRepo.add(CaptureRecord(createdAt: old, sourceAppName: "Test", durationMs: 1000, wordCount: 1, wpm: 10, rawText: "old", formattedText: "old", resultStatus: .inserted, engineUsed: .openai))
        captureRepo.add(CaptureRecord(createdAt: now, sourceAppName: "Test", durationMs: 1000, wordCount: 1, wpm: 10, rawText: "new", formattedText: "new", resultStatus: .inserted, engineUsed: .openai))

        let cutoff = now.addingTimeInterval(-60 * 60 * 24 * 5)
        captureRepo.purge(before: cutoff)
        let items = captureRepo.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.formattedText, "new")
    }

    func testWhisperDefaultsPersist() {
        let context = inMemoryContext()
        let settingsRepo = SwiftDataSettingsRepository(context: context)
        let settings = settingsRepo.settings()

        XCTAssertEqual(settings.whisperBackend ?? .server, .server)
        XCTAssertEqual(settings.whisperModelId, WhisperLocalModel.defaultId.rawValue)
        XCTAssertFalse((settings.whisperModelsDir ?? "").isEmpty)
        XCTAssertEqual(settings.whisperServerAutoStart ?? true, true)
        XCTAssertEqual(settings.whisperLocalThreads ?? 4, 4)
    }
}
