import CryptoKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AppDatabase: TranscriptRecordStoreProtocol {
    private enum SchemaVersion {
        static let current = 5
    }

    private var db: OpaquePointer?
    private let fileManager: FileManager
    private let baseDirectoryURL: URL?

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL
        openDatabase()
        configureDatabase()
        migrateIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func fetchCachedResult(for key: LLMCacheKey) -> LLMResult? {
        guard let db else { return nil }

        let sql = """
        SELECT text, json, status, validation_status, tokens, cached_tokens, latency_ms
        FROM llm_cache
        WHERE profile_id = ? AND profile_version = ? AND model_id = ? AND context_signature_hash = ? AND transcript_hash = ?
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(key.profileID, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(key.profileVersion))
        bindText(key.modelID, to: statement, index: 3)
        bindText(key.contextSignatureHash, to: statement, index: 4)
        bindText(key.transcriptHash, to: statement, index: 5)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let text = stringColumn(statement, index: 0)
        let json = stringColumn(statement, index: 1)
        let statusRaw = stringColumn(statement, index: 2) ?? LLMResultStatus.success.rawValue
        let validationRaw = stringColumn(statement, index: 3) ?? LLMValidationStatus.notApplicable.rawValue
        let tokens = intColumn(statement, index: 4)
        let cachedTokens = intColumn(statement, index: 5)
        let latencyMs = intColumn(statement, index: 6)

        return LLMResult(
            text: text,
            json: json,
            status: LLMResultStatus(rawValue: statusRaw) ?? .success,
            validationStatus: LLMValidationStatus(rawValue: validationRaw) ?? .notApplicable,
            tokens: tokens,
            cachedTokens: cachedTokens,
            latencyMs: latencyMs,
            profileID: key.profileID,
            profileVersion: key.profileVersion,
            modelID: key.modelID,
            fromCache: true
        )
    }

    func saveCachedResult(_ result: LLMResult, for key: LLMCacheKey) {
        guard let db else { return }

        let sql = """
        INSERT INTO llm_cache (
            profile_id, profile_version, model_id, context_signature_hash, transcript_hash,
            text, json, status, validation_status, tokens, cached_tokens, latency_ms, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(profile_id, profile_version, model_id, context_signature_hash, transcript_hash)
        DO UPDATE SET
            text = excluded.text,
            json = excluded.json,
            status = excluded.status,
            validation_status = excluded.validation_status,
            tokens = excluded.tokens,
            cached_tokens = excluded.cached_tokens,
            latency_ms = excluded.latency_ms,
            updated_at = excluded.updated_at
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(key.profileID, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(key.profileVersion))
        bindText(key.modelID, to: statement, index: 3)
        bindText(key.contextSignatureHash, to: statement, index: 4)
        bindText(key.transcriptHash, to: statement, index: 5)
        bindOptionalText(result.text, to: statement, index: 6)
        bindOptionalText(result.json, to: statement, index: 7)
        bindText(result.status.rawValue, to: statement, index: 8)
        bindText(result.validationStatus.rawValue, to: statement, index: 9)
        sqlite3_bind_int(statement, 10, Int32(result.tokens))
        sqlite3_bind_int(statement, 11, Int32(result.cachedTokens))
        sqlite3_bind_int(statement, 12, Int32(result.latencyMs))
        sqlite3_bind_double(statement, 13, Date().timeIntervalSince1970)

        _ = sqlite3_step(statement)
    }

    func appendRecord(_ record: TranscriptRecord) {
        guard let db else { return }

        let sql = """
        INSERT INTO transcriptions (
            created_at, raw_text, deterministic_text, final_text, llm_text, llm_json, llm_status, validation_status,
            profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
            active_app_name, bundle_id, style_category, style_preset, window_title, focused_element_role, insertion_outcome
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, record.createdAt.timeIntervalSince1970)
        bindText(record.rawText, to: statement, index: 2)
        bindText(record.deterministicText, to: statement, index: 3)
        bindOptionalText(record.finalText, to: statement, index: 4)
        bindOptionalText(record.llmText, to: statement, index: 5)
        bindOptionalText(record.llmJSON, to: statement, index: 6)
        bindOptionalText(record.llmStatus?.rawValue, to: statement, index: 7)
        bindOptionalText(record.validationStatus?.rawValue, to: statement, index: 8)
        bindOptionalText(record.profileID, to: statement, index: 9)
        bindOptionalInt(record.profileVersion, to: statement, index: 10)
        bindOptionalText(record.modelID, to: statement, index: 11)
        bindOptionalInt(record.tokens, to: statement, index: 12)
        bindOptionalInt(record.cachedTokens, to: statement, index: 13)
        bindOptionalInt(record.latencyMs, to: statement, index: 14)
        bindText(record.activeAppName, to: statement, index: 15)
        bindText(record.bundleID, to: statement, index: 16)
        bindText(record.styleCategory.rawValue, to: statement, index: 17)
        bindOptionalText(record.stylePreset?.rawValue, to: statement, index: 18)
        bindOptionalText(record.windowTitle, to: statement, index: 19)
        bindOptionalText(record.focusedElementRole, to: statement, index: 20)
        bindOptionalText(record.insertionOutcome?.rawValue, to: statement, index: 21)

        _ = sqlite3_step(statement)
    }

    func fetchRecentRecords(limit: Int) -> [TranscriptRecord] {
        guard let db else { return [] }

        let sql = """
        SELECT created_at, raw_text, deterministic_text, final_text, llm_text, llm_json, llm_status, validation_status,
               profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
               active_app_name, bundle_id, style_category, style_preset, window_title, focused_element_role, insertion_outcome
        FROM transcriptions
        ORDER BY created_at DESC
        LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

        var records: [TranscriptRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let rawText = stringColumn(statement, index: 1) ?? ""
            let deterministicText = stringColumn(statement, index: 2) ?? ""
            let finalText = stringColumn(statement, index: 3)
            let llmText = stringColumn(statement, index: 4)
            let llmJSON = stringColumn(statement, index: 5)
            let llmStatus = stringColumn(statement, index: 6).flatMap(LLMResultStatus.init(rawValue:))
            let validationStatus = stringColumn(statement, index: 7).flatMap(LLMValidationStatus.init(rawValue:))
            let profileID = stringColumn(statement, index: 8)
            let profileVersion = optionalIntColumn(statement, index: 9)
            let modelID = stringColumn(statement, index: 10)
            let tokens = optionalIntColumn(statement, index: 11)
            let cachedTokens = optionalIntColumn(statement, index: 12)
            let latencyMs = optionalIntColumn(statement, index: 13)
            let activeAppName = stringColumn(statement, index: 14) ?? ""
            let bundleID = stringColumn(statement, index: 15) ?? ""
            let styleCategory = stringColumn(statement, index: 16).flatMap(StyleCategory.init(rawValue:)) ?? .other
            let stylePreset = stringColumn(statement, index: 17).flatMap(StylePreset.init(rawValue:))
            let windowTitle = stringColumn(statement, index: 18)
            let focusedElementRole = stringColumn(statement, index: 19)
            let insertionOutcome = stringColumn(statement, index: 20).flatMap(InsertionOutcome.init(rawValue:))

            records.append(
                TranscriptRecord(
                    createdAt: createdAt,
                    rawText: rawText,
                    deterministicText: deterministicText,
                    finalText: finalText,
                    llmText: llmText,
                    llmJSON: llmJSON,
                    llmStatus: llmStatus,
                    validationStatus: validationStatus,
                    profileID: profileID,
                    profileVersion: profileVersion,
                    modelID: modelID,
                    tokens: tokens,
                    cachedTokens: cachedTokens,
                    latencyMs: latencyMs,
                    activeAppName: activeAppName,
                    bundleID: bundleID,
                    styleCategory: styleCategory,
                    stylePreset: stylePreset,
                    windowTitle: windowTitle,
                    focusedElementRole: focusedElementRole,
                    insertionOutcome: insertionOutcome
                )
            )
        }

        return records
    }

    func appendDiagnosticSession(_ record: DiagnosticSessionRecord) {
        guard let db else { return }

        let sql = """
        INSERT OR REPLACE INTO recording_sessions (
            session_id, started_at, duration_ms, trigger_source, trigger_mode,
            transcription_engine, local_engine_mode, resolved_backend, server_connection_mode,
            model_id, local_model_lifecycle_state, logic_model_id, reasoning_effort, formatting_profile,
            transcription_latency_ms, llm_latency_ms, total_latency_ms,
            tokens_in, cached_tokens, insertion_outcome, fallback_reason,
            target_app, target_bundle_id, silence_peak, silence_average_rms,
            silence_voiced_ratio, skipped_for_silence, failure_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(record.sessionID.uuidString, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, record.startedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(record.durationMs))
        bindText(record.triggerSource.rawValue, to: statement, index: 4)
        bindOptionalText(record.triggerMode?.rawValue, to: statement, index: 5)
        bindOptionalText(record.transcriptionEngine, to: statement, index: 6)
        bindOptionalText(record.localEngineMode, to: statement, index: 7)
        bindOptionalText(record.resolvedBackend, to: statement, index: 8)
        bindOptionalText(record.serverConnectionMode, to: statement, index: 9)
        bindOptionalText(record.modelID, to: statement, index: 10)
        bindOptionalText(record.localModelLifecycleState, to: statement, index: 11)
        bindOptionalText(record.logicModelID, to: statement, index: 12)
        bindOptionalText(record.reasoningEffort, to: statement, index: 13)
        bindOptionalText(record.formattingProfile, to: statement, index: 14)
        bindOptionalInt(record.transcriptionLatencyMs, to: statement, index: 15)
        bindOptionalInt(record.llmLatencyMs, to: statement, index: 16)
        bindOptionalInt(record.totalLatencyMs, to: statement, index: 17)
        bindOptionalInt(record.tokensIn, to: statement, index: 18)
        bindOptionalInt(record.cachedTokens, to: statement, index: 19)
        bindOptionalText(record.insertionOutcome?.rawValue, to: statement, index: 20)
        bindOptionalText(record.fallbackReason?.databaseValue, to: statement, index: 21)
        bindOptionalText(record.targetApp, to: statement, index: 22)
        bindOptionalText(record.targetBundleID, to: statement, index: 23)
        bindOptionalDouble(record.silencePeak, to: statement, index: 24)
        bindOptionalDouble(record.silenceAverageRMS, to: statement, index: 25)
        bindOptionalDouble(record.silenceVoicedRatio, to: statement, index: 26)
        sqlite3_bind_int(statement, 27, record.skippedForSilence ? 1 : 0)
        bindOptionalText(record.failureMessage, to: statement, index: 28)

        _ = sqlite3_step(statement)
    }

    func fetchRecentDiagnosticSessions(limit: Int) -> [DiagnosticSessionRecord] {
        fetchRows(
            sql: """
            SELECT session_id, started_at, duration_ms, trigger_source, trigger_mode,
                   transcription_engine, local_engine_mode, resolved_backend, server_connection_mode,
                   model_id, local_model_lifecycle_state, logic_model_id, reasoning_effort, formatting_profile,
                   transcription_latency_ms, llm_latency_ms, total_latency_ms,
                   tokens_in, cached_tokens, insertion_outcome, fallback_reason,
                   target_app, target_bundle_id, silence_peak, silence_average_rms,
                   silence_voiced_ratio, skipped_for_silence, failure_message
            FROM recording_sessions
            ORDER BY started_at DESC
            LIMIT ?
            """,
            bind: { statement in sqlite3_bind_int(statement, 1, Int32(max(0, limit))) },
            map: { statement in
                DiagnosticSessionRecord(
                    sessionID: UUID(uuidString: stringColumn(statement, index: 0) ?? "") ?? UUID(),
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    durationMs: Int(sqlite3_column_int(statement, 2)),
                    triggerSource: stringColumn(statement, index: 3).flatMap(RecordingTriggerSource.init(rawValue:)) ?? .manual,
                    triggerMode: stringColumn(statement, index: 4).flatMap(HotkeyTriggerMode.init(rawValue:)),
                    transcriptionEngine: stringColumn(statement, index: 5),
                    localEngineMode: stringColumn(statement, index: 6),
                    resolvedBackend: stringColumn(statement, index: 7),
                    serverConnectionMode: stringColumn(statement, index: 8),
                    modelID: stringColumn(statement, index: 9),
                    localModelLifecycleState: stringColumn(statement, index: 10),
                    logicModelID: stringColumn(statement, index: 11),
                    reasoningEffort: stringColumn(statement, index: 12),
                    formattingProfile: stringColumn(statement, index: 13),
                    transcriptionLatencyMs: optionalIntColumn(statement, index: 14),
                    llmLatencyMs: optionalIntColumn(statement, index: 15),
                    totalLatencyMs: optionalIntColumn(statement, index: 16),
                    tokensIn: optionalIntColumn(statement, index: 17),
                    cachedTokens: optionalIntColumn(statement, index: 18),
                    insertionOutcome: stringColumn(statement, index: 19).flatMap(InsertionOutcome.init(rawValue:)),
                    fallbackReason: stringColumn(statement, index: 20).flatMap(ClipboardFallbackReason.init(databaseValue:)),
                    targetApp: stringColumn(statement, index: 21),
                    targetBundleID: stringColumn(statement, index: 22),
                    silencePeak: optionalDoubleColumn(statement, index: 23),
                    silenceAverageRMS: optionalDoubleColumn(statement, index: 24),
                    silenceVoicedRatio: optionalDoubleColumn(statement, index: 25),
                    skippedForSilence: sqlite3_column_int(statement, 26) != 0,
                    failureMessage: stringColumn(statement, index: 27)
                )
            }
        )
    }

    func fetchDiagnosticSessionSummary(limit: Int) -> DiagnosticSessionSummary {
        guard let db else { return .empty }

        let sql = """
        SELECT
            AVG(CASE WHEN total_latency_ms IS NOT NULL THEN total_latency_ms END),
            AVG(CASE
                    WHEN tokens_in IS NOT NULL AND tokens_in > 0 THEN CAST(cached_tokens AS REAL) / CAST(tokens_in AS REAL)
                    WHEN cached_tokens IS NOT NULL AND cached_tokens > 0 THEN 1.0
                    ELSE 0.0
                END),
            AVG(CASE WHEN skipped_for_silence = 1 THEN 1.0 ELSE 0.0 END),
            AVG(CASE WHEN insertion_outcome IN ('copied_only', 'copied_only_needs_permission', 'failed') THEN 1.0 ELSE 0.0 END),
            SUM(CASE WHEN fallback_reason = 'accessibility_permission_required' OR insertion_outcome = 'copied_only_needs_permission' THEN 1 ELSE 0 END)
        FROM (
            SELECT *
            FROM recording_sessions
            ORDER BY started_at DESC
            LIMIT ?
        )
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .empty
        }

        let averageLatency = optionalDoubleColumn(statement, index: 0).map { Int($0.rounded()) }
        let cacheHitRate = optionalDoubleColumn(statement, index: 1) ?? 0
        let silenceSkipRate = optionalDoubleColumn(statement, index: 2) ?? 0
        let pasteFailureRate = optionalDoubleColumn(statement, index: 3) ?? 0
        let permissionFallbackCount = optionalIntColumn(statement, index: 4) ?? 0

        return DiagnosticSessionSummary(
            averageTotalLatencyMs: averageLatency,
            cacheHitRate: cacheHitRate,
            silenceSkipRate: silenceSkipRate,
            pasteFailureRate: pasteFailureRate,
            permissionFallbackCount: permissionFallbackCount
        )
    }

    func fetchDictionaryEntries() -> [DictionaryEntryRecord] {
        guard let db else { return [] }

        let sql = """
        SELECT id, source_text, target_text, note, created_at, updated_at, archived
        FROM dictionary_entries
        WHERE archived = 0
        ORDER BY normalized_target ASC, normalized_source ASC, id ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [DictionaryEntryRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                DictionaryEntryRecord(
                    id: sqlite3_column_int64(statement, 0),
                    from: stringColumn(statement, index: 1) ?? "",
                    to: stringColumn(statement, index: 2) ?? "",
                    note: stringColumn(statement, index: 3),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    archived: sqlite3_column_int(statement, 6) != 0
                )
            )
        }

        return rows
    }

    func replaceDictionaryEntries(_ entries: [GlossaryEntry]) {
        guard let db else { return }
        execute("BEGIN IMMEDIATE TRANSACTION")
        defer { execute("COMMIT") }

        _ = sqlite3_exec(db, "DELETE FROM dictionary_entries", nil, nil, nil)
        let sql = """
        INSERT INTO dictionary_entries (
            source_text, target_text, normalized_source, normalized_target, note, archived, created_at, updated_at
        ) VALUES (?, ?, ?, ?, NULL, 0, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        for entry in entries {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(entry.from, to: statement, index: 1)
            bindText(entry.to, to: statement, index: 2)
            bindText(Self.normalize(entry.from), to: statement, index: 3)
            bindText(Self.normalize(entry.to), to: statement, index: 4)
            sqlite3_bind_double(statement, 5, now)
            sqlite3_bind_double(statement, 6, now)
            _ = sqlite3_step(statement)
        }
    }

    func upsertDictionaryEntry(from: String, to: String, note: String?) {
        guard let db else { return }

        let sql = """
        INSERT INTO dictionary_entries (
            source_text, target_text, normalized_source, normalized_target, note, archived, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(normalized_source) DO UPDATE SET
            source_text = excluded.source_text,
            target_text = excluded.target_text,
            normalized_target = excluded.normalized_target,
            note = excluded.note,
            archived = 0,
            updated_at = excluded.updated_at
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        bindText(from, to: statement, index: 1)
        bindText(to, to: statement, index: 2)
        bindText(Self.normalize(from), to: statement, index: 3)
        bindText(Self.normalize(to), to: statement, index: 4)
        bindOptionalText(note, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, now)
        sqlite3_bind_double(statement, 7, now)
        _ = sqlite3_step(statement)
    }

    func fetchFolders() -> [FolderRecord] {
        fetchRows(
            sql: "SELECT id, name, created_at, updated_at, archived FROM folders ORDER BY updated_at DESC",
            map: { statement in
                FolderRecord(
                    id: sqlite3_column_int64(statement, 0),
                    name: stringColumn(statement, index: 1) ?? "",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    archived: sqlite3_column_int(statement, 4) != 0
                )
            }
        )
    }

    func fetchNotes(limit: Int) -> [NoteRecord] {
        fetchRows(
            sql: """
            SELECT id, folder_id, transcription_id, title, body, created_at, updated_at, archived
            FROM notes
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bind: { statement in sqlite3_bind_int(statement, 1, Int32(max(0, limit))) },
            map: { statement in
                NoteRecord(
                    id: sqlite3_column_int64(statement, 0),
                    folderID: optionalInt64Column(statement, index: 1),
                    transcriptionID: optionalInt64Column(statement, index: 2),
                    title: stringColumn(statement, index: 3),
                    body: stringColumn(statement, index: 4) ?? "",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    archived: sqlite3_column_int(statement, 7) != 0
                )
            }
        )
    }

    func fetchActions(limit: Int) -> [ActionRecord] {
        fetchRows(
            sql: """
            SELECT id, folder_id, note_id, transcription_id, title, status, due_at, created_at, updated_at, archived
            FROM actions
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bind: { statement in sqlite3_bind_int(statement, 1, Int32(max(0, limit))) },
            map: { statement in
                ActionRecord(
                    id: sqlite3_column_int64(statement, 0),
                    folderID: optionalInt64Column(statement, index: 1),
                    noteID: optionalInt64Column(statement, index: 2),
                    transcriptionID: optionalInt64Column(statement, index: 3),
                    title: stringColumn(statement, index: 4) ?? "",
                    status: stringColumn(statement, index: 5).flatMap(ActionStatus.init(rawValue:)) ?? .open,
                    dueAt: optionalDateColumn(statement, index: 6),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                    archived: sqlite3_column_int(statement, 9) != 0
                )
            }
        )
    }

    func upsertFolder(id: Int64?, name: String, archived: Bool) -> Int64? {
        guard let db else { return nil }

        if let id {
            let sql = """
            UPDATE folders
            SET name = ?, archived = ?, updated_at = ?
            WHERE id = ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            let now = Date().timeIntervalSince1970
            bindText(name, to: statement, index: 1)
            sqlite3_bind_int(statement, 2, archived ? 1 : 0)
            sqlite3_bind_double(statement, 3, now)
            sqlite3_bind_int64(statement, 4, id)
            _ = sqlite3_step(statement)
            return id
        }

        let sql = """
        INSERT INTO folders (name, archived, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let now = Date().timeIntervalSince1970
        bindText(name, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, archived ? 1 : 0)
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_double(statement, 4, now)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }
        return sqlite3_last_insert_rowid(db)
    }

    func saveNote(
        id: Int64?,
        folderID: Int64?,
        transcriptionID: Int64?,
        title: String?,
        body: String,
        archived: Bool
    ) -> Int64? {
        guard let db else { return nil }
        let now = Date().timeIntervalSince1970

        if let id {
            let sql = """
            UPDATE notes
            SET folder_id = ?, transcription_id = ?, title = ?, body = ?, archived = ?, updated_at = ?
            WHERE id = ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            bindOptionalInt64(folderID, to: statement, index: 1)
            bindOptionalInt64(transcriptionID, to: statement, index: 2)
            bindOptionalText(title, to: statement, index: 3)
            bindText(body, to: statement, index: 4)
            sqlite3_bind_int(statement, 5, archived ? 1 : 0)
            sqlite3_bind_double(statement, 6, now)
            sqlite3_bind_int64(statement, 7, id)
            _ = sqlite3_step(statement)
            return id
        }

        let sql = """
        INSERT INTO notes (folder_id, transcription_id, title, body, archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bindOptionalInt64(folderID, to: statement, index: 1)
        bindOptionalInt64(transcriptionID, to: statement, index: 2)
        bindOptionalText(title, to: statement, index: 3)
        bindText(body, to: statement, index: 4)
        sqlite3_bind_int(statement, 5, archived ? 1 : 0)
        sqlite3_bind_double(statement, 6, now)
        sqlite3_bind_double(statement, 7, now)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }
        return sqlite3_last_insert_rowid(db)
    }

    func saveAction(
        id: Int64?,
        folderID: Int64?,
        noteID: Int64?,
        transcriptionID: Int64?,
        title: String,
        status: ActionStatus,
        dueAt: Date?,
        archived: Bool
    ) -> Int64? {
        guard let db else { return nil }
        let now = Date().timeIntervalSince1970

        if let id {
            let sql = """
            UPDATE actions
            SET folder_id = ?, note_id = ?, transcription_id = ?, title = ?, status = ?, due_at = ?, archived = ?, updated_at = ?
            WHERE id = ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            bindOptionalInt64(folderID, to: statement, index: 1)
            bindOptionalInt64(noteID, to: statement, index: 2)
            bindOptionalInt64(transcriptionID, to: statement, index: 3)
            bindText(title, to: statement, index: 4)
            bindText(status.rawValue, to: statement, index: 5)
            bindOptionalDate(dueAt, to: statement, index: 6)
            sqlite3_bind_int(statement, 7, archived ? 1 : 0)
            sqlite3_bind_double(statement, 8, now)
            sqlite3_bind_int64(statement, 9, id)
            _ = sqlite3_step(statement)
            return id
        }

        let sql = """
        INSERT INTO actions (folder_id, note_id, transcription_id, title, status, due_at, archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bindOptionalInt64(folderID, to: statement, index: 1)
        bindOptionalInt64(noteID, to: statement, index: 2)
        bindOptionalInt64(transcriptionID, to: statement, index: 3)
        bindText(title, to: statement, index: 4)
        bindText(status.rawValue, to: statement, index: 5)
        bindOptionalDate(dueAt, to: statement, index: 6)
        sqlite3_bind_int(statement, 7, archived ? 1 : 0)
        sqlite3_bind_double(statement, 8, now)
        sqlite3_bind_double(statement, 9, now)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }
        return sqlite3_last_insert_rowid(db)
    }

    func makeCacheKey(
        profile: PromptProfile,
        modelID: String,
        contextPack: ContextPack,
        deterministicText: String
    ) -> LLMCacheKey {
        LLMCacheKey(
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            contextSignatureHash: Self.sha256Hex(contextPack.signatureString),
            transcriptHash: Self.sha256Hex(deterministicText)
        )
    }

    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func openDatabase() {
        ensureDirectoryExists(at: databaseURL.deletingLastPathComponent())
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func configureDatabase() {
        execute("PRAGMA journal_mode = WAL;")
        execute("PRAGMA synchronous = NORMAL;")
        execute("PRAGMA foreign_keys = ON;")
        execute("PRAGMA busy_timeout = 5000;")
    }

    private func migrateIfNeeded() {
        guard let db else { return }

        let currentVersion = intPragma("user_version")
        if currentVersion < 1 {
            createVersion1Tables()
            setUserVersion(1)
        }
        if currentVersion < 2 {
            migrateLegacyTranscriptHistoryIfNeeded()
            setUserVersion(2)
        }
        if currentVersion < 3 {
            createRecordingSessionsTable()
            setUserVersion(3)
        }
        if currentVersion < 4 {
            migrateRecordingSessionsToVersion4()
            setUserVersion(4)
        }
        if currentVersion < 5 {
            migrateRecordingSessionsToVersion5()
            setUserVersion(5)
        }
        if currentVersion < 6 {
            migrateRecordingSessionsToVersion6()
            setUserVersion(6)
        }

        if tableExists("transcriptions") == false {
            createVersion1Tables()
        }
        if tableExists("recording_sessions") == false {
            createRecordingSessionsTable()
        }

        _ = db
    }

    private func createVersion1Tables() {
        let createTranscriptionsSQL = """
        CREATE TABLE IF NOT EXISTS transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            raw_text TEXT NOT NULL,
            deterministic_text TEXT NOT NULL,
            final_text TEXT,
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
            style_category TEXT NOT NULL,
            style_preset TEXT,
            window_title TEXT,
            focused_element_role TEXT,
            insertion_outcome TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_transcriptions_created_at ON transcriptions(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_transcriptions_bundle_id ON transcriptions(bundle_id);
        """

        let createCacheSQL = """
        CREATE TABLE IF NOT EXISTS llm_cache (
            profile_id TEXT NOT NULL,
            profile_version INTEGER NOT NULL,
            model_id TEXT NOT NULL,
            context_signature_hash TEXT NOT NULL,
            transcript_hash TEXT NOT NULL,
            text TEXT,
            json TEXT,
            status TEXT NOT NULL,
            validation_status TEXT NOT NULL,
            tokens INTEGER NOT NULL,
            cached_tokens INTEGER NOT NULL,
            latency_ms INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (profile_id, profile_version, model_id, context_signature_hash, transcript_hash)
        );
        """

        let createDictionarySQL = """
        CREATE TABLE IF NOT EXISTS dictionary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_text TEXT NOT NULL,
            target_text TEXT NOT NULL,
            normalized_source TEXT NOT NULL UNIQUE,
            normalized_target TEXT NOT NULL,
            note TEXT,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_dictionary_target ON dictionary_entries(normalized_target);
        """

        let createWorkspaceSQL = """
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER,
            transcription_id INTEGER,
            title TEXT,
            body TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE SET NULL,
            FOREIGN KEY(transcription_id) REFERENCES transcriptions(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);

        CREATE TABLE IF NOT EXISTS actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER,
            note_id INTEGER,
            transcription_id INTEGER,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            due_at REAL,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE SET NULL,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE SET NULL,
            FOREIGN KEY(transcription_id) REFERENCES transcriptions(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_actions_updated_at ON actions(updated_at DESC);
        """

        execute(createTranscriptionsSQL)
        execute(createCacheSQL)
        execute(createDictionarySQL)
        execute(createWorkspaceSQL)
        createRecordingSessionsTable()
    }

    private func createRecordingSessionsTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS recording_sessions (
            session_id TEXT PRIMARY KEY,
            started_at REAL NOT NULL,
            duration_ms INTEGER NOT NULL,
            trigger_source TEXT NOT NULL,
            trigger_mode TEXT,
            transcription_engine TEXT,
            local_engine_mode TEXT,
            resolved_backend TEXT,
            server_connection_mode TEXT,
            model_id TEXT,
            local_model_lifecycle_state TEXT,
            logic_model_id TEXT,
            reasoning_effort TEXT,
            formatting_profile TEXT,
            transcription_latency_ms INTEGER,
            llm_latency_ms INTEGER,
            total_latency_ms INTEGER,
            tokens_in INTEGER,
            cached_tokens INTEGER,
            insertion_outcome TEXT,
            fallback_reason TEXT,
            target_app TEXT,
            target_bundle_id TEXT,
            silence_peak REAL,
            silence_average_rms REAL,
            silence_voiced_ratio REAL,
            skipped_for_silence INTEGER NOT NULL DEFAULT 0,
            failure_message TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_recording_sessions_started_at ON recording_sessions(started_at DESC);
        """

        execute(sql)
    }

    private func migrateRecordingSessionsToVersion4() {
        guard tableExists("recording_sessions") else { return }
        addColumnIfNeeded(table: "recording_sessions", column: "logic_model_id", definition: "TEXT")
        addColumnIfNeeded(table: "recording_sessions", column: "reasoning_effort", definition: "TEXT")
    }

    private func migrateRecordingSessionsToVersion5() {
        guard tableExists("recording_sessions") else { return }
        addColumnIfNeeded(table: "recording_sessions", column: "local_model_lifecycle_state", definition: "TEXT")
        addColumnIfNeeded(table: "recording_sessions", column: "failure_message", definition: "TEXT")
    }

    private func migrateRecordingSessionsToVersion6() {
        guard tableExists("recording_sessions") else { return }
        addColumnIfNeeded(table: "recording_sessions", column: "local_engine_mode", definition: "TEXT")
        addColumnIfNeeded(table: "recording_sessions", column: "resolved_backend", definition: "TEXT")
        addColumnIfNeeded(table: "recording_sessions", column: "server_connection_mode", definition: "TEXT")
    }

    private func migrateLegacyTranscriptHistoryIfNeeded() {
        guard tableExists("transcript_records"), tableExists("transcriptions"), rowCount(for: "transcriptions") == 0 else {
            return
        }

        let sql = """
        INSERT INTO transcriptions (
            created_at, raw_text, deterministic_text, final_text, llm_text, llm_json, llm_status, validation_status,
            profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
            active_app_name, bundle_id, style_category, style_preset, window_title, focused_element_role, insertion_outcome
        )
        SELECT
            created_at,
            raw_text,
            deterministic_text,
            COALESCE(llm_text, deterministic_text),
            llm_text,
            llm_json,
            llm_status,
            validation_status,
            profile_id,
            profile_version,
            model_id,
            tokens,
            cached_tokens,
            latency_ms,
            active_app_name,
            bundle_id,
            style_category,
            NULL,
            NULL,
            NULL,
            NULL
        FROM transcript_records
        ORDER BY created_at ASC
        """

        execute(sql)
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        _ = sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) {
        guard columnExists(column, in: table) == false else { return }
        execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func intPragma(_ name: String) -> Int {
        guard let db else { return 0 }
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

    private func setUserVersion(_ version: Int) {
        execute("PRAGMA user_version = \(version);")
    }

    private func rowCount(for table: String) -> Int {
        guard let db else { return 0 }
        let sql = "SELECT COUNT(*) FROM \(table)"
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

    private func tableExists(_ name: String) -> Bool {
        guard let db else { return false }
        let sql = """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        bindText(name, to: statement, index: 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let db else { return false }
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if stringColumn(statement, index: 1) == column {
                return true
            }
        }

        return false
    }

    private func fetchRows<T>(
        sql: String,
        bind: ((OpaquePointer?) -> Void)? = nil,
        map: (OpaquePointer?) -> T
    ) -> [T] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind?(statement)
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(map(statement))
        }
        return rows
    }

    private var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("transcript_history.sqlite")
    }

    private var appSupportDirectory: URL {
        if let baseDirectoryURL {
            return baseDirectoryURL
        }
        if let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return root.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
    }

    private func ensureDirectoryExists(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: statement, index: index)
    }

    private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func bindOptionalInt64(_ value: Int64?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, value)
    }

    private func bindOptionalDouble(_ value: Double?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func bindOptionalDate(_ value: Date?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func intColumn(_ statement: OpaquePointer?, index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }

    private func optionalIntColumn(_ statement: OpaquePointer?, index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
    }

    private func optionalInt64Column(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private func optionalDoubleColumn(_ statement: OpaquePointer?, index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func optionalDateColumn(_ statement: OpaquePointer?, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

typealias TranscriptRecordStore = AppDatabase

private extension ClipboardFallbackReason {
    var databaseValue: String {
        switch self {
        case .autoPasteDisabled:
            return "auto_paste_disabled"
        case .accessibilityPermissionRequired:
            return "accessibility_permission_required"
        case .missingInsertionTarget:
            return "missing_insertion_target"
        case .invalidTargetApplication:
            return "invalid_target_application"
        case .targetRestoreFailed:
            return "target_restore_failed"
        case .pasteFailed:
            return "paste_failed"
        }
    }

    init?(databaseValue: String) {
        switch databaseValue {
        case "auto_paste_disabled":
            self = .autoPasteDisabled
        case "accessibility_permission_required":
            self = .accessibilityPermissionRequired
        case "missing_insertion_target":
            self = .missingInsertionTarget
        case "invalid_target_application":
            self = .invalidTargetApplication
        case "target_restore_failed":
            self = .targetRestoreFailed
        case "paste_failed":
            self = .pasteFailed
        default:
            return nil
        }
    }
}
