import Foundation
import CryptoKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol TranscriptRecordStoreProtocol: AnyObject {
    func fetchCachedResult(for key: LLMCacheKey) -> LLMResult?
    func saveCachedResult(_ result: LLMResult, for key: LLMCacheKey)
    func appendRecord(_ record: TranscriptRecord)
    func fetchRecentRecords(limit: Int) -> [TranscriptRecord]
    func makeCacheKey(profile: PromptProfile, modelID: String, contextPack: ContextPack, deterministicText: String) -> LLMCacheKey
}

final class TranscriptRecordStore: TranscriptRecordStoreProtocol {
    private var db: OpaquePointer?
    private let fileManager: FileManager
    private let baseDirectoryURL: URL?

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL
        openDatabase()
        createTablesIfNeeded()
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
        INSERT INTO transcript_records (
            created_at, raw_text, deterministic_text, llm_text, llm_json, llm_status, validation_status,
            profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
            active_app_name, bundle_id, style_category
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, record.createdAt.timeIntervalSince1970)
        bindText(record.rawText, to: statement, index: 2)
        bindText(record.deterministicText, to: statement, index: 3)
        bindOptionalText(record.llmText, to: statement, index: 4)
        bindOptionalText(record.llmJSON, to: statement, index: 5)
        bindOptionalText(record.llmStatus?.rawValue, to: statement, index: 6)
        bindOptionalText(record.validationStatus?.rawValue, to: statement, index: 7)
        bindOptionalText(record.profileID, to: statement, index: 8)
        bindOptionalInt(record.profileVersion, to: statement, index: 9)
        bindOptionalText(record.modelID, to: statement, index: 10)
        bindOptionalInt(record.tokens, to: statement, index: 11)
        bindOptionalInt(record.cachedTokens, to: statement, index: 12)
        bindOptionalInt(record.latencyMs, to: statement, index: 13)
        bindText(record.activeAppName, to: statement, index: 14)
        bindText(record.bundleID, to: statement, index: 15)
        bindText(record.styleCategory.rawValue, to: statement, index: 16)

        _ = sqlite3_step(statement)
    }

    func fetchRecentRecords(limit: Int) -> [TranscriptRecord] {
        guard let db else { return [] }

        let sql = """
        SELECT created_at, raw_text, deterministic_text, llm_text, llm_json, llm_status, validation_status,
               profile_id, profile_version, model_id, tokens, cached_tokens, latency_ms,
               active_app_name, bundle_id, style_category
        FROM transcript_records
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
            let llmText = stringColumn(statement, index: 3)
            let llmJSON = stringColumn(statement, index: 4)
            let llmStatus = stringColumn(statement, index: 5).flatMap(LLMResultStatus.init(rawValue:))
            let validationStatus = stringColumn(statement, index: 6).flatMap(LLMValidationStatus.init(rawValue:))
            let profileID = stringColumn(statement, index: 7)
            let profileVersion = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
            let modelID = stringColumn(statement, index: 9)
            let tokens = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 10))
            let cachedTokens = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11))
            let latencyMs = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 12))
            let activeAppName = stringColumn(statement, index: 13) ?? ""
            let bundleID = stringColumn(statement, index: 14) ?? ""
            let styleCategory = stringColumn(statement, index: 15).flatMap(StyleCategory.init(rawValue:)) ?? .other

            records.append(
                TranscriptRecord(
                    createdAt: createdAt,
                    rawText: rawText,
                    deterministicText: deterministicText,
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
                    styleCategory: styleCategory
                )
            )
        }

        return records
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

    private func createTablesIfNeeded() {
        guard let db else { return }

        let createRecordsSQL = """
        CREATE TABLE IF NOT EXISTS transcript_records (
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

        _ = sqlite3_exec(db, createRecordsSQL, nil, nil, nil)
        _ = sqlite3_exec(db, createCacheSQL, nil, nil, nil)
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

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func intColumn(_ statement: OpaquePointer?, index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }
}
