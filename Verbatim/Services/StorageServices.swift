import Foundation
import SQLite3
import Carbon

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let nativeDictionaryTable = "native_dictionary_entries"

private struct ModelManifestEnvelope: Codable {
    var models: [ModelDescriptor]
}

private struct CapabilityManifestEnvelope: Codable {
    var providers: [ProviderCapabilityDescriptor]
    var features: [FeatureCapabilityDescriptor]
}

enum ModelManifestRepository {
    static func load() -> [ModelDescriptor] {
        guard let url = VerbatimBundle.current.url(forResource: "ModelManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(ModelManifestEnvelope.self, from: data) else {
            return []
        }
        return envelope.models
    }
}

enum CapabilityManifestRepository {
    static func load() -> CapabilityManifest {
        guard let url = VerbatimBundle.current.url(forResource: "CapabilityManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CapabilityManifestEnvelope.self, from: data) else {
            return CapabilityManifest(providers: [], features: [])
        }

        return CapabilityManifest(
            providers: envelope.providers,
            features: envelope.features
        )
    }
}

final class SettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "Verbatim.NativeSettings"
    private let legacyMigrationKey = "Verbatim.LegacySettingsMigratedV1"
    private var cachedSettings: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            cachedSettings = decoded
        } else if defaults.bool(forKey: legacyMigrationKey) == false,
                  let migrated = LegacySettingsMigrator.migrate(defaults: defaults) {
            cachedSettings = migrated
            if let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: key)
            }
            defaults.set(true, forKey: legacyMigrationKey)
        } else {
            cachedSettings = AppSettings()
            defaults.set(true, forKey: legacyMigrationKey)
        }
    }

    var settings: AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return cachedSettings
    }

    func replace(_ settings: AppSettings) {
        lock.lock()
        cachedSettings = settings
        lock.unlock()
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}

private enum LegacySettingsMigrator {
    private static let localEngineModeKey = "VerbatimSwiftMVP.LocalEngineMode"
    private static let localModelIDKey = "VerbatimSwiftMVP.LocalModelID"
    private static let setupCompletedKey = "VerbatimSwiftMVP.SetupCompleted"
    private static let interactionSettingsKey = "VerbatimSwiftMVP.InteractionSettingsV1"

    private enum LegacyWhisperModel: String {
        case whisperTiny = "whisper-tiny"
        case whisperBase = "whisper-base"
        case whisperSmall = "whisper-small"
        case whisperMedium = "whisper-medium"
        case whisperLargeV3 = "whisper-large-v3"

        var releaseID: String {
            switch self {
            case .whisperTiny: return "tiny"
            case .whisperBase: return "base"
            case .whisperSmall: return "small"
            case .whisperMedium: return "medium"
            case .whisperLargeV3: return "large"
            }
        }
    }

    private struct LegacyInteractionSettings: Decodable {
        var hotkeyBinding: LegacyHotkeyBinding?
        var showListeningIndicator: Bool?
        var autoPasteAfterInsert: Bool?
    }

    private struct LegacyHotkeyBinding: Decodable {
        var keyCode: UInt16
        var modifierFlagsRawValue: UInt
        var modifierKeyRawValue: UInt?
    }

    private enum LegacyModifierFlags {
        static let command: UInt = 1 << 20
        static let option: UInt = 1 << 19
        static let control: UInt = 1 << 18
        static let shift: UInt = 1 << 17
        static let function: UInt = 1 << 23
    }

    static func migrate(defaults: UserDefaults) -> AppSettings? {
        var settings = AppSettings()
        var didChange = false

        if let legacyEngine = defaults.string(forKey: localEngineModeKey) {
            switch legacyEngine {
            case "apple_speech":
                settings.selectedProvider = .appleSpeech
                didChange = true
            case "whisperkit", "legacy_whisper":
                settings.selectedProvider = .whisper
                didChange = true
            default:
                break
            }
        }

        if let legacyModelID = defaults.string(forKey: localModelIDKey) {
            if legacyModelID == "apple-on-device" {
                settings.selectedProvider = .appleSpeech
                didChange = true
            } else if let mappedModel = LegacyWhisperModel(rawValue: legacyModelID) {
                settings.selectedProvider = .whisper
                settings.selectedWhisperModelID = mappedModel.releaseID
                didChange = true
            }
        }

        if let onboardingCompleted = defaults.object(forKey: setupCompletedKey) as? Bool {
            settings.onboardingCompleted = onboardingCompleted
            didChange = true
        }

        if let data = defaults.data(forKey: interactionSettingsKey),
           let interaction = try? JSONDecoder().decode(LegacyInteractionSettings.self, from: data) {
            if let showListeningIndicator = interaction.showListeningIndicator {
                settings.showOverlay = showListeningIndicator
                didChange = true
            }
            if let autoPasteAfterInsert = interaction.autoPasteAfterInsert {
                settings.pasteMode = autoPasteAfterInsert ? .autoPaste : .clipboardOnly
                didChange = true
            }
            if let legacyHotkey = interaction.hotkeyBinding,
               let shortcut = keyboardShortcut(from: legacyHotkey) {
                settings.hotkey = shortcut
                didChange = true
            }
        }

        return didChange ? settings : nil
    }

    private static func keyboardShortcut(from legacy: LegacyHotkeyBinding) -> KeyboardShortcut? {
        guard legacy.modifierKeyRawValue == nil else { return nil }
        guard legacy.modifierFlagsRawValue & LegacyModifierFlags.function == 0 else { return nil }

        var modifiers: UInt32 = 0
        if legacy.modifierFlagsRawValue & LegacyModifierFlags.command != 0 { modifiers |= UInt32(cmdKey) }
        if legacy.modifierFlagsRawValue & LegacyModifierFlags.option != 0 { modifiers |= UInt32(optionKey) }
        if legacy.modifierFlagsRawValue & LegacyModifierFlags.control != 0 { modifiers |= UInt32(controlKey) }
        if legacy.modifierFlagsRawValue & LegacyModifierFlags.shift != 0 { modifiers |= UInt32(shiftKey) }

        guard modifiers != 0 else { return nil }
        return KeyboardShortcut(keyCode: UInt32(legacy.keyCode), modifiers: modifiers)
    }
}

final class HistoryStore: HistoryStoreProtocol, @unchecked Sendable {
    private let dbLock = NSLock()
    private var db: OpaquePointer?
    private let paths: VerbatimPaths

    init(paths: VerbatimPaths = VerbatimPaths()) {
        self.paths = paths
        try? paths.ensureDirectoriesExist()
        sqlite3_open(paths.databaseURL.path, &db)
        configure()
        migrateLegacyDataIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func fetchHistory(limit: Int = 200) -> [HistoryItem] {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return [] }

        let sql = """
        SELECT id, timestamp, provider, language, original_text, final_pasted_text, error
        FROM history_items
        ORDER BY timestamp DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(
                HistoryItem(
                    id: sqlite3_column_int64(statement, 0),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    provider: string(statement, index: 2) ?? "legacy",
                    language: string(statement, index: 3) ?? "",
                    originalText: string(statement, index: 4) ?? "",
                    finalPastedText: string(statement, index: 5) ?? "",
                    error: string(statement, index: 6)
                )
            )
        }
        return items
    }

    @discardableResult
    func save(
        provider: ProviderID,
        language: LanguageSelection,
        originalText: String,
        finalText: String,
        error: String?
    ) -> HistoryItem {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else {
            return HistoryItem(id: -1, timestamp: Date(), provider: provider.rawValue, language: language.identifier, originalText: originalText, finalPastedText: finalText, error: error)
        }
        let now = Date()
        let sql = """
        INSERT INTO history_items (timestamp, provider, language, original_text, final_pasted_text, error)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        bind(provider.rawValue, to: statement, index: 2)
        bind(language.identifier, to: statement, index: 3)
        bind(originalText, to: statement, index: 4)
        bind(finalText, to: statement, index: 5)
        bind(error, to: statement, index: 6)
        _ = sqlite3_step(statement)
        let identifier = sqlite3_last_insert_rowid(db)
        return HistoryItem(id: identifier, timestamp: now, provider: provider.rawValue, language: language.identifier, originalText: originalText, finalPastedText: finalText, error: error)
    }

    func deleteHistory(id: Int64) {
        execute("DELETE FROM history_items WHERE id = \(id);")
    }

    func clearHistory() {
        execute("DELETE FROM history_items;")
    }

    func fetchDictionary() -> [DictionaryEntry] {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return [] }
        let sql = """
        SELECT id, phrase, hint
        FROM \(nativeDictionaryTable)
        ORDER BY phrase COLLATE NOCASE ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var items: [DictionaryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = UUID(uuidString: string(statement, index: 0) ?? "") ?? UUID()
            items.append(
                DictionaryEntry(
                    id: id,
                    phrase: string(statement, index: 1) ?? "",
                    hint: string(statement, index: 2) ?? ""
                )
            )
        }
        return items
    }

    func upsertDictionary(entry: DictionaryEntry) {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return }
        let sql = """
        INSERT INTO \(nativeDictionaryTable) (id, phrase, hint)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            phrase = excluded.phrase,
            hint = excluded.hint
        """
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        bind(entry.id.uuidString, to: statement, index: 1)
        bind(entry.phrase, to: statement, index: 2)
        bind(entry.hint, to: statement, index: 3)
        _ = sqlite3_step(statement)
    }

    func deleteDictionary(id: UUID) {
        execute("DELETE FROM \(nativeDictionaryTable) WHERE id = '\(id.uuidString)';")
    }

    func resetAll() {
        execute("DELETE FROM history_items; DELETE FROM \(nativeDictionaryTable);")
    }

    private func configure() {
        execute("PRAGMA journal_mode=WAL;")
        execute("PRAGMA foreign_keys=ON;")
        execute("""
        CREATE TABLE IF NOT EXISTS history_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            provider TEXT NOT NULL,
            language TEXT NOT NULL,
            original_text TEXT NOT NULL,
            final_pasted_text TEXT NOT NULL,
            error TEXT
        );
        CREATE TABLE IF NOT EXISTS \(nativeDictionaryTable) (
            id TEXT PRIMARY KEY,
            phrase TEXT NOT NULL,
            hint TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS \(nativeDictionaryTable)_phrase_idx
        ON \(nativeDictionaryTable)(phrase COLLATE NOCASE);
        """)
    }

    private func migrateLegacyDataIfNeeded() {
        guard fetchHistory(limit: 1).isEmpty else { return }
        guard tableExists("transcriptions") else { return }

        execute("""
        INSERT INTO history_items (timestamp, provider, language, original_text, final_pasted_text, error)
        SELECT
            COALESCE(created_at, strftime('%s','now')),
            COALESCE(model_id, 'legacy'),
            '',
            COALESCE(raw_text, ''),
            COALESCE(final_text, deterministic_text, raw_text, ''),
            NULL
        FROM transcriptions
        ORDER BY created_at DESC;
        """)

        if fetchDictionary().isEmpty, tableExists("dictionary_entries") {
            execute("""
            INSERT OR IGNORE INTO \(nativeDictionaryTable) (id, phrase, hint)
            SELECT lower(hex(randomblob(16))), COALESCE(target_text, ''), COALESCE(source_text, '')
            FROM dictionary_entries AS legacy_dictionary
            WHERE target_text IS NOT NULL;
            """)
        }
    }

    private func tableExists(_ name: String) -> Bool {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return false }
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(name, to: statement, index: 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func execute(_ sql: String) {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func string(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
}
