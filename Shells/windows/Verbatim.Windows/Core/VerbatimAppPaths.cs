using System;
using System.IO;

namespace Verbatim.Windows.Core;

internal sealed class VerbatimAppPaths
{
    internal string Root { get; }
    internal string Models { get; }
    internal string WhisperModels { get; }
    internal string ParakeetModels { get; }
    internal string Runtime { get; }
    internal string Logs { get; }
    internal string Recordings { get; }
    internal string SettingsFile { get; }
    internal string HistoryDatabase { get; }

    private VerbatimAppPaths(string root)
    {
        Root = root;
        Models = Path.Combine(root, "Models");
        WhisperModels = Path.Combine(Models, "Whisper");
        ParakeetModels = Path.Combine(Models, "Parakeet");
        Runtime = Path.Combine(root, "Runtime");
        Logs = Path.Combine(root, "Logs");
        Recordings = Path.Combine(root, "Recordings");
        SettingsFile = Path.Combine(root, "settings.json");
        HistoryDatabase = Path.Combine(root, "history.sqlite");
    }

    internal static VerbatimAppPaths Current()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Verbatim");
        return new VerbatimAppPaths(root);
    }

    internal void EnsureDirectoriesExist()
    {
        Directory.CreateDirectory(Root);
        Directory.CreateDirectory(Models);
        Directory.CreateDirectory(WhisperModels);
        Directory.CreateDirectory(ParakeetModels);
        Directory.CreateDirectory(Runtime);
        Directory.CreateDirectory(Logs);
        Directory.CreateDirectory(Recordings);
    }
}
