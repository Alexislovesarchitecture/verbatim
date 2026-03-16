using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace Verbatim.Windows.Core;

internal sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    private readonly string settingsPath;

    internal SettingsStore(VerbatimAppPaths paths)
    {
        paths.EnsureDirectoriesExist();
        settingsPath = paths.SettingsFile;
    }

    internal AppSettings Load()
    {
        if (!File.Exists(settingsPath))
        {
            var defaults = new AppSettings();
            defaults.Normalize();
            Save(defaults);
            return defaults;
        }

        var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(settingsPath), JsonOptions) ?? new AppSettings();
        settings.Normalize();
        return settings;
    }

    internal void Save(AppSettings settings)
    {
        settings.Normalize();
        File.WriteAllText(settingsPath, JsonSerializer.Serialize(settings, JsonOptions));
    }
}

internal sealed class HistoryStore
{
    private readonly string connectionString;

    internal HistoryStore(VerbatimAppPaths paths)
    {
        paths.EnsureDirectoriesExist();
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = paths.HistoryDatabase,
        }.ToString();

        using var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp_ms INTEGER NOT NULL,
                provider TEXT NOT NULL,
                language TEXT NOT NULL,
                original_text TEXT NOT NULL,
                final_pasted_text TEXT NOT NULL,
                error TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS dictionary_entries (
                id TEXT PRIMARY KEY,
                phrase TEXT NOT NULL,
                hint TEXT NOT NULL
            );
            """;
        command.ExecuteNonQuery();
    }

    internal IReadOnlyList<HistoryItem> FetchHistory(int limit = 50)
    {
        var items = new List<HistoryItem>();
        using var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, timestamp_ms, provider, language, original_text, final_pasted_text, error
            FROM history
            ORDER BY timestamp_ms DESC
            LIMIT $limit
            """;
        command.Parameters.AddWithValue("$limit", limit);
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            items.Add(new HistoryItem
            {
                Id = reader.GetInt64(0),
                TimestampMs = reader.GetInt64(1),
                Provider = reader.GetString(2),
                Language = reader.GetString(3),
                OriginalText = reader.GetString(4),
                FinalPastedText = reader.GetString(5),
                Error = reader.IsDBNull(6) ? null : reader.GetString(6),
            });
        }
        return items;
    }

    internal HistoryItem SaveHistory(string provider, string language, string originalText, string finalText, string? error)
    {
        var timestampMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        using var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO history(timestamp_ms, provider, language, original_text, final_pasted_text, error)
            VALUES($timestamp, $provider, $language, $original, $final, $error);
            SELECT last_insert_rowid();
            """;
        command.Parameters.AddWithValue("$timestamp", timestampMs);
        command.Parameters.AddWithValue("$provider", provider);
        command.Parameters.AddWithValue("$language", language);
        command.Parameters.AddWithValue("$original", originalText);
        command.Parameters.AddWithValue("$final", finalText);
        command.Parameters.AddWithValue("$error", (object?)error ?? DBNull.Value);
        var id = (long)(command.ExecuteScalar() ?? 0L);
        return new HistoryItem
        {
            Id = id,
            TimestampMs = timestampMs,
            Provider = provider,
            Language = language,
            OriginalText = originalText,
            FinalPastedText = finalText,
            Error = error,
        };
    }

    internal IReadOnlyList<DictionaryEntry> FetchDictionary()
    {
        var items = new List<DictionaryEntry>();
        using var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, phrase, hint
            FROM dictionary_entries
            ORDER BY phrase COLLATE NOCASE ASC
            """;
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            items.Add(new DictionaryEntry
            {
                Id = Guid.Parse(reader.GetString(0)),
                Phrase = reader.GetString(1),
                Hint = reader.GetString(2),
            });
        }
        return items;
    }

    internal void UpsertDictionary(DictionaryEntry entry)
    {
        using var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO dictionary_entries(id, phrase, hint)
            VALUES($id, $phrase, $hint)
            ON CONFLICT(id) DO UPDATE SET phrase = excluded.phrase, hint = excluded.hint
            """;
        command.Parameters.AddWithValue("$id", entry.Id.ToString());
        command.Parameters.AddWithValue("$phrase", entry.Phrase);
        command.Parameters.AddWithValue("$hint", entry.Hint);
        command.ExecuteNonQuery();
    }
}
