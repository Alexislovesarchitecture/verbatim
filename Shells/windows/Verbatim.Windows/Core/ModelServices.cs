using SharpCompress.Archives;
using SharpCompress.Common;
using System.Net.Http;

namespace Verbatim.Windows.Core;

internal sealed class WindowsModelCatalog
{
    private readonly VerbatimAppPaths paths;
    private readonly List<ModelDescriptor> models;

    internal WindowsModelCatalog(VerbatimAppPaths paths, IEnumerable<ModelDescriptor> descriptors)
    {
        this.paths = paths;
        models = descriptors.OrderBy(descriptor => descriptor.Provider).ThenBy(descriptor => descriptor.Name).ToList();
        this.paths.EnsureDirectoriesExist();
    }

    internal IReadOnlyList<ModelDescriptor> ModelsForProvider(string providerId)
        => models.Where(model => model.Provider == providerId).ToList();

    internal IReadOnlyList<ProviderModelStatusInput> BuildStatuses(string providerId)
        => ModelsForProvider(providerId)
            .Select(model => new ProviderModelStatusInput
            {
                Id = model.Id,
                Name = model.Name,
                SupportedLanguageIds = model.SupportedLanguageIds,
                IsInstalled = IsInstalled(model),
            })
            .ToList();

    internal bool IsInstalled(ModelDescriptor model)
    {
        var target = InstallTarget(model);
        return model.Provider switch
        {
            ProviderIds.Parakeet => Directory.Exists(target),
            _ => File.Exists(target),
        };
    }

    internal string InstallTarget(ModelDescriptor model)
    {
        var root = model.Provider == ProviderIds.Parakeet ? paths.ParakeetModels : paths.WhisperModels;
        var leaf = model.Provider == ProviderIds.Parakeet
            ? model.ExtractDirectory ?? model.Id
            : model.FileName ?? model.Id;
        return Path.Combine(root, leaf);
    }
}

internal sealed class ModelInstallService
{
    private static readonly HttpClient HttpClient = new(new HttpClientHandler
    {
        AutomaticDecompression = System.Net.DecompressionMethods.All,
    });

    private readonly WindowsModelCatalog catalog;

    internal ModelInstallService(WindowsModelCatalog catalog)
    {
        this.catalog = catalog;
    }

    internal async Task<string> InstallAsync(ModelDescriptor descriptor, IProgress<double?>? progress, CancellationToken cancellationToken)
    {
        var destination = catalog.InstallTarget(descriptor);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        if (catalog.IsInstalled(descriptor))
        {
            progress?.Report(1);
            return destination;
        }

        if (string.IsNullOrWhiteSpace(descriptor.DownloadUrl))
        {
            throw new InvalidOperationException($"{descriptor.Name} does not declare a download URL.");
        }

        using var response = await HttpClient.GetAsync(
            descriptor.DownloadUrl,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();

        var expected = response.Content.Headers.ContentLength;
        var tempFile = Path.Combine(Path.GetTempPath(), $"verbatim-{descriptor.Id}-{Guid.NewGuid():N}.download");
        await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var sink = File.Create(tempFile))
        {
            var buffer = new byte[1024 * 128];
            long written = 0;
            while (true)
            {
                var read = await source.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
                if (read == 0)
                {
                    break;
                }

                await sink.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                written += read;
                progress?.Report(expected.HasValue && expected.Value > 0 ? (double)written / expected.Value : null);
            }
        }

        if (descriptor.Provider == ProviderIds.Parakeet)
        {
            ExtractArchive(tempFile, destination);
            File.Delete(tempFile);
            progress?.Report(1);
            return destination;
        }

        if (File.Exists(destination))
        {
            File.Delete(destination);
        }

        File.Move(tempFile, destination);
        progress?.Report(1);
        return destination;
    }

    private static void ExtractArchive(string archivePath, string destination)
    {
        if (Directory.Exists(destination))
        {
            Directory.Delete(destination, recursive: true);
        }

        Directory.CreateDirectory(destination);
        using var archive = ArchiveFactory.Open(archivePath);
        foreach (var entry in archive.Entries.Where(entry => !entry.IsDirectory))
        {
            entry.WriteToDirectory(destination, new ExtractionOptions
            {
                ExtractFullPath = true,
                Overwrite = true,
            });
        }
    }
}
