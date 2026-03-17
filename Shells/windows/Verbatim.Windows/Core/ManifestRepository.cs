using System.Text.Json;

namespace Verbatim.Windows.Core;

internal static class ManifestRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    internal static ModelManifestEnvelope LoadModelManifest()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", "ModelManifest.json");
        if (!File.Exists(path))
        {
            return new ModelManifestEnvelope();
        }

        return JsonSerializer.Deserialize<ModelManifestEnvelope>(File.ReadAllText(path), JsonOptions)
            ?? new ModelManifestEnvelope();
    }

    internal static CapabilityManifest LoadCapabilityManifest()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", "CapabilityManifest.json");
        if (!File.Exists(path))
        {
            return new CapabilityManifest();
        }

        return JsonSerializer.Deserialize<CapabilityManifest>(File.ReadAllText(path), JsonOptions) ?? new CapabilityManifest();
    }
}
