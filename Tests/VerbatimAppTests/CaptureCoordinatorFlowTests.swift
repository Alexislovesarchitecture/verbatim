import XCTest
import Foundation
import SwiftData
@testable import Verbatim

private final class FakeTranscriptionCoordinatorInsertionService: TextInsertionServicing {
    var copyText: String?
    var hasTarget = false
    var shouldInsert = false
    var insertedText: String?

    func requestAccessibilityIfNeeded() { }
    func copyToClipboard(_ text: String) { copyText = text }
    func hasEditableTarget() -> Bool { hasTarget }
    func insert(_ text: String) -> Bool {
        insertedText = text
        return shouldInsert
    }
    func frontmostApplicationName() -> String { "Tests" }
    func frontmostBundleIdentifier() -> String? { "com.tests" }
    func inferStyleCategory() -> StyleCategory { .personal }
}

@MainActor
final class CaptureCoordinatorFlowTests: XCTestCase {
    private func coordinatorWithFakeInsertion(_ fake: FakeTranscriptionCoordinatorInsertionService) -> CaptureCoordinator {
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
        let context = container.mainContext

        return CaptureCoordinator(
            insertionService: fake,
            hotkeyMonitor: FunctionKeyMonitor(),
            overlay: OverlayController(),
            formattingPipeline: FormattingPipeline(),
            captureRepository: SwiftDataCaptureRepository(context: context),
            dictionaryRepository: SwiftDataDictionaryRepository(context: context),
            snippetRepository: SwiftDataSnippetRepository(context: context),
            styleRepository: SwiftDataStyleRepository(context: context),
            noteRepository: SwiftDataNoteRepository(context: context),
            settingsRepository: SwiftDataSettingsRepository(context: context),
            keyStore: OpenAIKeyStore()
        )
    }

    func testAutoInsertPath() {
        let fake = FakeTranscriptionCoordinatorInsertionService()
        fake.hasTarget = true
        fake.shouldInsert = true
        let coordinator = coordinatorWithFakeInsertion(fake)
        let settings = coordinator.settingsRepository.settings()
        settings.autoInsertEnabled = true
        settings.clipboardFallbackEnabled = true
        settings.insertionModePreferred = .accessibilityFirst
        coordinator.settingsRepository.save(settings: settings)

        let result = coordinator.applyInsertionDecisionTree(
            text: "hello",
            settings: settings,
            engineUsed: .openai
        )
        XCTAssertEqual(result.status, .inserted)
        XCTAssertEqual(fake.insertedText, "hello")
    }

    func testClipboardFallbackWhenNoTarget() {
        let fake = FakeTranscriptionCoordinatorInsertionService()
        fake.hasTarget = false
        let coordinator = coordinatorWithFakeInsertion(fake)
        let settings = coordinator.settingsRepository.settings()
        settings.autoInsertEnabled = false
        settings.clipboardFallbackEnabled = true
        coordinator.settingsRepository.save(settings: settings)

        let result = coordinator.applyInsertionDecisionTree(
            text: "hello",
            settings: settings,
            engineUsed: .openai
        )
        XCTAssertEqual(result.status, .clipboard)
        XCTAssertEqual(fake.copyText, "hello")
    }

    func testFailureWhenNoTargetAndNoFallback() {
        let fake = FakeTranscriptionCoordinatorInsertionService()
        fake.hasTarget = false
        let coordinator = coordinatorWithFakeInsertion(fake)
        let settings = coordinator.settingsRepository.settings()
        settings.autoInsertEnabled = true
        settings.clipboardFallbackEnabled = false
        coordinator.settingsRepository.save(settings: settings)

        let result = coordinator.applyInsertionDecisionTree(
            text: "hello",
            settings: settings,
            engineUsed: .openai
        )
        XCTAssertEqual(result.status, .failed)
        XCTAssertNotNil(result.errorMessage)
    }
}
