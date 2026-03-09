import XCTest
import SQLite3
@testable import VerbatimSwiftMVP

final class TranscriptRecordStoreTests: XCTestCase {
    func testCacheRoundTrip() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        let profile = PromptProfile(
            id: "cleanup",
            version: 1,
            name: "Cleanup",
            styleCategory: nil,
            enabled: true,
            outputMode: .text,
            instructionPrefix: "x",
            schema: nil,
            options: nil
        )

        let context = ContextPack(
            activeAppName: "Mail",
            bundleID: "com.apple.mail",
            styleCategory: .email,
            stylePreset: .formal,
            styleSummary: "Caps: full. Punctuation: full. Format: email. Structure: greeting, body, sign-off.",
            windowTitle: "Inbox",
            focusedElementRole: "AXTextArea",
            punctuationMode: "sentence",
            fillerRemovalEnabled: true,
            autoDetectLists: false,
            outputFormat: .auto,
            selfCorrectionMode: .keepFinal,
            flagLowConfidenceWords: false,
            reasoningEffort: .modelDefault,
            glossary: [],
            sessionMemory: []
        )

        let key = sut.makeCacheKey(profile: profile, modelID: "gpt-5-mini", contextPack: context, deterministicText: "hello")
        let original = LLMResult(
            text: "hello.",
            json: nil,
            status: .success,
            validationStatus: .notApplicable,
            tokens: 11,
            cachedTokens: 9,
            latencyMs: 120,
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: "gpt-5-mini",
            fromCache: false
        )

        sut.saveCachedResult(original, for: key)
        let cached = sut.fetchCachedResult(for: key)

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.text, "hello.")
        XCTAssertEqual(cached?.tokens, 11)
        XCTAssertEqual(cached?.cachedTokens, 9)
        XCTAssertEqual(cached?.fromCache, true)
    }

    func testRecentRecordsReturnNewestFirst() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        sut.appendRecord(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 100),
                rawText: "first raw",
                deterministicText: "first clean",
                finalText: "first clean",
                llmText: nil,
                llmJSON: nil,
                llmStatus: nil,
                validationStatus: nil,
                profileID: nil,
                profileVersion: nil,
                modelID: nil,
                tokens: nil,
                cachedTokens: nil,
                latencyMs: nil,
                activeAppName: "Mail",
                bundleID: "com.apple.mail",
                styleCategory: .email,
                stylePreset: nil,
                windowTitle: nil,
                focusedElementRole: nil,
                insertionOutcome: nil
            )
        )

        sut.appendRecord(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 200),
                rawText: "second raw",
                deterministicText: "second clean",
                finalText: "second formatted",
                llmText: "second formatted",
                llmJSON: nil,
                llmStatus: .success,
                validationStatus: .notApplicable,
                profileID: "auto-style",
                profileVersion: 1,
                modelID: "gpt-5-mini",
                tokens: 8,
                cachedTokens: 0,
                latencyMs: 32,
                activeAppName: "Messages",
                bundleID: "com.apple.MobileSMS",
                styleCategory: .personal,
                stylePreset: nil,
                windowTitle: nil,
                focusedElementRole: nil,
                insertionOutcome: .inserted
            )
        )

        let records = sut.fetchRecentRecords(limit: 10)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.rawText, "second raw")
        XCTAssertEqual(records.first?.llmText, "second formatted")
        XCTAssertEqual(records.last?.rawText, "first raw")
    }

    func testDatabaseEnablesWALAndSchemaVersion() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = tempRoot.appendingPathComponent("transcript_history.sqlite")
        _ = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        XCTAssertEqual(stringPragma("journal_mode", db: db), "wal")
        XCTAssertEqual(intPragma("user_version", db: db), 7)
    }

    func testLegacyTranscriptTableMigratesIntoTranscriptions() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let databaseURL = tempRoot.appendingPathComponent("transcript_history.sqlite")

        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        defer { sqlite3_close(legacyDB) }

        XCTAssertEqual(sqlite3_exec(legacyDB, """
        CREATE TABLE transcript_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            raw_text TEXT NOT NULL,
            deterministic_text TEXT NOT NULL,
            llm_text TEXT,
            llm_json TEXT,
            llm_status TEXT,
            validation_status TEXT,
            profile_id TEXT,
            profile_version INTEGER,
            model_id TEXT,
            tokens INTEGER,
            cached_tokens INTEGER,
            latency_ms INTEGER,
            active_app_name TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            style_category TEXT NOT NULL
        );
        INSERT INTO transcript_records (
            created_at, raw_text, deterministic_text, llm_text, llm_json, llm_status, validation_status,
            profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
            active_app_name, bundle_id, style_category
        ) VALUES (
            200, 'legacy raw', 'legacy clean', 'legacy final', NULL, 'success', 'not_applicable',
            'cleanup', 1, 'gpt-5-mini', 12, 0, 45, 'Mail', 'com.apple.mail', 'email'
        );
        """, nil, nil, nil), SQLITE_OK)

        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)
        let records = sut.fetchRecentRecords(limit: 10)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.rawText, "legacy raw")
        XCTAssertEqual(records.first?.finalText, "legacy final")
        XCTAssertEqual(records.first?.styleCategory, .email)
    }

    func testDictionaryRoundTripUsesDedicatedTable() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        sut.replaceDictionaryEntries([
            GlossaryEntry(from: "adu", to: "ADU"),
            GlossaryEntry(from: "site scape", to: "Sitescape"),
        ])
        sut.upsertDictionaryEntry(from: "adu", to: "ADU Permit", note: "preferred expansion")

        let entries = sut.fetchDictionaryEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.from, "adu")
        XCTAssertEqual(entries.first?.to, "ADU Permit")
    }

    func testWorkspaceTablesSupportBasicSaveAndFetch() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        let folderID = sut.upsertFolder(id: nil, name: "Client Follow Up", archived: false)
        let noteID = sut.saveNote(
            id: nil,
            folderID: folderID,
            transcriptionID: nil,
            title: "Call summary",
            body: "Need revised permit notes.",
            archived: false
        )
        let actionID = sut.saveAction(
            id: nil,
            folderID: folderID,
            noteID: noteID,
            transcriptionID: nil,
            title: "Draft permit response",
            status: .open,
            dueAt: nil,
            archived: false
        )

        XCTAssertNotNil(folderID)
        XCTAssertNotNil(noteID)
        XCTAssertNotNil(actionID)
        XCTAssertEqual(sut.fetchFolders().first?.name, "Client Follow Up")
        XCTAssertEqual(sut.fetchNotes(limit: 10).first?.title, "Call summary")
        XCTAssertEqual(sut.fetchActions(limit: 10).first?.title, "Draft permit response")
    }

    func testDiagnosticSessionsRoundTripAndSummary() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

        sut.appendDiagnosticSession(
            DiagnosticSessionRecord(
                sessionID: UUID(),
                startedAt: Date(timeIntervalSince1970: 100),
                durationMs: 500,
                triggerSource: .hotkey,
                triggerMode: .holdToTalk,
                transcriptionEngine: "remote",
                localEngineMode: "whisper_auto",
                resolvedBackend: "whisperkit_sdk",
                transport: "managed_helper",
                serverConnectionMode: nil,
                modelID: "gpt-4o-mini-transcribe",
                localModelLifecycleState: "ready",
                helperState: "running",
                prewarmState: "ready",
                failureStage: "inference",
                logicModelID: "gpt-5-mini",
                reasoningEffort: "medium",
                formattingProfile: "cleanup",
                transcriptionLatencyMs: 120,
                llmLatencyMs: 80,
                totalLatencyMs: 240,
                tokensIn: 20,
                cachedTokens: 10,
                insertionOutcome: .copiedOnlyNeedsPermission,
                fallbackReason: .accessibilityPermissionRequired,
                targetApp: "Messages",
                targetBundleID: "com.apple.MobileSMS",
                silencePeak: 0.02,
                silenceAverageRMS: 0.01,
                silenceVoicedRatio: 0.12,
                skippedForSilence: false,
                failureMessage: "sample failure"
            )
        )
        sut.appendDiagnosticSession(
            DiagnosticSessionRecord(
                sessionID: UUID(),
                startedAt: Date(timeIntervalSince1970: 200),
                durationMs: 300,
                triggerSource: .hotkey,
                triggerMode: .holdToTalk,
                transcriptionEngine: "remote",
                localEngineMode: "whisperkit_server",
                resolvedBackend: "whisperkit_server",
                transport: "external_server",
                serverConnectionMode: "external_server",
                modelID: "gpt-4o-mini-transcribe",
                localModelLifecycleState: "downloading",
                helperState: nil,
                prewarmState: nil,
                failureStage: nil,
                logicModelID: "gpt-5-mini",
                reasoningEffort: "medium",
                formattingProfile: nil,
                transcriptionLatencyMs: nil,
                llmLatencyMs: nil,
                totalLatencyMs: 300,
                tokensIn: nil,
                cachedTokens: nil,
                insertionOutcome: nil,
                fallbackReason: nil,
                targetApp: "Messages",
                targetBundleID: "com.apple.MobileSMS",
                silencePeak: 0.0,
                silenceAverageRMS: 0.0,
                silenceVoicedRatio: 0.0,
                skippedForSilence: true,
                failureMessage: nil
            )
        )

        let sessions = sut.fetchRecentDiagnosticSessions(limit: 10)
        let summary = sut.fetchDiagnosticSessionSummary(limit: 10)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.first?.skippedForSilence ?? false)
        XCTAssertEqual(sessions.first?.serverConnectionMode, "external_server")
        XCTAssertEqual(sessions.first?.transport, "external_server")
        XCTAssertEqual(sessions.last?.logicModelID, "gpt-5-mini")
        XCTAssertEqual(sessions.last?.localEngineMode, "whisper_auto")
        XCTAssertEqual(sessions.last?.resolvedBackend, "whisperkit_sdk")
        XCTAssertEqual(sessions.last?.transport, "managed_helper")
        XCTAssertEqual(sessions.last?.localModelLifecycleState, "ready")
        XCTAssertEqual(sessions.last?.helperState, "running")
        XCTAssertEqual(sessions.last?.prewarmState, "ready")
        XCTAssertEqual(sessions.last?.failureStage, "inference")
        XCTAssertEqual(sessions.last?.reasoningEffort, "medium")
        XCTAssertEqual(sessions.last?.failureMessage, "sample failure")
        XCTAssertEqual(summary.averageTotalLatencyMs, 270)
        XCTAssertEqual(summary.permissionFallbackCount, 1)
        XCTAssertEqual(summary.silenceSkipRate, 0.5, accuracy: 0.001)
    }

    private func stringPragma(_ name: String, db: OpaquePointer?) -> String? {
        let sql = "PRAGMA \(name);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    private func intPragma(_ name: String, db: OpaquePointer?) -> Int {
        let sql = "PRAGMA \(name);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
