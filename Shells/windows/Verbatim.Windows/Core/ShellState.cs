namespace Verbatim.Windows.Core;

internal sealed class WindowsShellState
{
    private readonly VerbatimAppPaths paths;
    private readonly SettingsStore settingsStore;
    private readonly HistoryStore historyStore;
    private readonly CapabilityManifest capabilityManifest;
    private readonly WindowsSystemProfileService systemProfileService;
    private readonly WindowsPermissionsManager permissionsManager;
    private readonly WindowsFocusContextService focusContextService;
    private readonly WindowsPasteService pasteService;
    private readonly WindowsRecordingManager recordingManager;
    private readonly WindowsRuntimeHealthService runtimeHealthService;
    private readonly WindowsModelCatalog modelCatalog;
    private readonly ModelInstallService modelInstallService;

    internal WindowsShellState()
    {
        paths = VerbatimAppPaths.Current();
        paths.EnsureDirectoriesExist();
        settingsStore = new SettingsStore(paths);
        historyStore = new HistoryStore(paths);
        capabilityManifest = ManifestRepository.LoadCapabilityManifest();
        var models = ManifestRepository.LoadModelManifest().Models;
        systemProfileService = new WindowsSystemProfileService();
        permissionsManager = new WindowsPermissionsManager();
        focusContextService = new WindowsFocusContextService();
        pasteService = new WindowsPasteService();
        recordingManager = new WindowsRecordingManager();
        runtimeHealthService = new WindowsRuntimeHealthService(paths);
        modelCatalog = new WindowsModelCatalog(paths, models);
        modelInstallService = new ModelInstallService(modelCatalog);
    }

    internal AppSettings Settings { get; private set; } = new();

    internal async Task<WindowsShellSnapshot> LoadAsync()
    {
        Settings = settingsStore.Load();
        return await BuildSnapshotAsync(statusMessage: null);
    }

    internal async Task<WindowsShellSnapshot> ReloadAsync(string? statusMessage = null)
        => await BuildSnapshotAsync(statusMessage);

    internal async Task<WindowsShellSnapshot> SetSelectedProviderAsync(string providerId)
    {
        Settings.SelectedProvider = providerId;
        settingsStore.Save(Settings);
        return await BuildSnapshotAsync($"Selected {ProviderTitle(providerId)} as the preferred provider.");
    }

    internal async Task<WindowsShellSnapshot> SetLanguageAsync(string languageIdentifier)
    {
        Settings.PreferredLanguages.SetForProvider(Settings.SelectedProvider, languageIdentifier);
        settingsStore.Save(Settings);
        return await BuildSnapshotAsync($"Updated {ProviderTitle(Settings.SelectedProvider)} language preference.");
    }

    internal async Task<WindowsShellSnapshot> SetModelAsync(string providerId, string modelId)
    {
        if (providerId == ProviderIds.Parakeet)
        {
            Settings.SelectedParakeetModelID = modelId;
        }
        else
        {
            Settings.SelectedWhisperModelID = modelId;
        }

        settingsStore.Save(Settings);
        return await BuildSnapshotAsync($"Updated {ProviderTitle(providerId)} model selection.");
    }

    internal async Task<WindowsShellSnapshot> InstallSelectedModelAsync(IProgress<double?> progress, CancellationToken cancellationToken)
    {
        var descriptor = CurrentModelDescriptor();
        if (descriptor is null)
        {
            return await BuildSnapshotAsync("No downloadable model is selected for the current provider.");
        }

        var providerTitle = ProviderTitle(descriptor.Provider);
        try
        {
            await modelInstallService.InstallAsync(descriptor, progress, cancellationToken);
            return await BuildSnapshotAsync($"{providerTitle} model {descriptor.Name} is ready.");
        }
        catch (Exception error)
        {
            return await BuildSnapshotAsync($"{providerTitle} model install failed: {error.Message}");
        }
    }

    internal async Task<WindowsShellSnapshot> CopyLatestTranscriptAsync()
    {
        var latest = historyStore.FetchHistory(limit: 1).FirstOrDefault();
        if (latest is null)
        {
            return await BuildSnapshotAsync("No history item is available to copy.");
        }

        var result = await pasteService.CopyAsync(latest.FinalPastedText);
        return await BuildSnapshotAsync(result.Message);
    }

    internal async Task<WindowsShellSnapshot> ToggleRecordingAsync()
    {
        if (!recordingManager.IsRecording)
        {
            var file = recordingManager.Start(paths);
            return await BuildSnapshotAsync($"Recording started: {file}");
        }

        var filePath = recordingManager.Stop();
        return await BuildSnapshotAsync(filePath is null ? "Recording stopped." : $"Recording saved to {filePath}");
    }

    private async Task<WindowsShellSnapshot> BuildSnapshotAsync(string? statusMessage)
    {
        Settings.Normalize();
        settingsStore.Save(Settings);

        var permission = permissionsManager.CheckMicrophone();
        var runtimeSnapshots = await runtimeHealthService.CaptureAsync();
        var capabilityRequest = new CapabilityResolutionRequest
        {
            Manifest = capabilityManifest,
            Profile = systemProfileService.Current(),
            StoredProvider = Settings.SelectedProvider,
            FallbackOrder = [ProviderIds.Whisper, ProviderIds.AppleSpeech, ProviderIds.Parakeet],
            Availability = BuildAvailability(permission),
            Readiness = BuildReadiness(runtimeSnapshots),
        };

        SharedCoreCapabilityResolution capabilityResolution;
        SharedCoreSelectionResolution selectionResolution;
        ProviderModelSelectionResolution modelSelection;
        List<ProviderDiagnosticReduction> diagnostics;
        string? bridgeError = null;

        try
        {
            capabilityResolution = VerbatimCoreBridge.ResolveCapabilities(capabilityRequest);
            selectionResolution = VerbatimCoreBridge.ResolveSelection(new SelectionResolutionRequest
            {
                StoredProvider = Settings.SelectedProvider,
                FallbackOrder = [ProviderIds.Whisper, ProviderIds.AppleSpeech, ProviderIds.Parakeet],
                Capabilities = capabilityResolution.ProviderCapabilities,
                PreferredLanguages = Settings.PreferredLanguages,
                AppleInstalledLanguages = AppleLanguageOptions().Where(language => !language.IsAuto).ToList(),
            });
            modelSelection = VerbatimCoreBridge.ResolveProviderModelSelection(new ProviderModelSelectionRequest
            {
                SelectedProvider = Settings.SelectedProvider,
                SelectedWhisperModelID = Settings.SelectedWhisperModelID,
                SelectedParakeetModelID = Settings.SelectedParakeetModelID,
                WhisperStatuses = modelCatalog.BuildStatuses(ProviderIds.Whisper).ToList(),
                ParakeetStatuses = modelCatalog.BuildStatuses(ProviderIds.Parakeet).ToList(),
                AppleInstalledLanguages = AppleLanguageOptions().Where(language => !language.IsAuto).ToList(),
            });
            diagnostics = VerbatimCoreBridge.ReduceProviderDiagnostics(new ProviderDiagnosticsRequest
            {
                Inputs = ProviderIds.All.Select(providerId => new ProviderDiagnosticInput
                {
                    Provider = providerId,
                    Capability = capabilityResolution.ProviderCapabilities.GetValueOrDefault(providerId) ?? new CapabilityStatus(),
                    Availability = capabilityRequest.Availability.GetValueOrDefault(providerId) ?? new ProviderAvailability(),
                    Readiness = capabilityRequest.Readiness.GetValueOrDefault(providerId) ?? new ProviderReadiness(),
                    RuntimeStateLabel = runtimeSnapshots.TryGetValue(providerId, out var runtime) ? runtime.State : null,
                    RuntimeError = runtimeSnapshots.TryGetValue(providerId, out runtime) ? runtime.LastError : null,
                }).ToList(),
            }).ToList();
        }
        catch (Exception error)
        {
            bridgeError = error.Message;
            capabilityResolution = new SharedCoreCapabilityResolution
            {
                EffectiveProvider = Settings.SelectedProvider,
            };
            selectionResolution = new SharedCoreSelectionResolution
            {
                EffectiveProvider = Settings.SelectedProvider,
                EffectiveLanguages = Settings.PreferredLanguages,
                EffectiveProviderMessage = error.Message,
            };
            modelSelection = new ProviderModelSelectionResolution
            {
                CurrentLanguageOptions = CurrentLanguageOptions(Settings.SelectedProvider),
                SelectedWhisperDescription = SelectedModelDescription(ProviderIds.Whisper, Settings.SelectedWhisperModelID),
                SelectedWhisperInstalled = modelCatalog.BuildStatuses(ProviderIds.Whisper).Any(item => item.Id == Settings.SelectedWhisperModelID && item.IsInstalled),
                SelectedParakeetDescription = SelectedModelDescription(ProviderIds.Parakeet, Settings.SelectedParakeetModelID),
                SelectedParakeetInstalled = modelCatalog.BuildStatuses(ProviderIds.Parakeet).Any(item => item.Id == Settings.SelectedParakeetModelID && item.IsInstalled),
            };
            diagnostics =
            [
                new ProviderDiagnosticReduction
                {
                    Provider = Settings.SelectedProvider,
                    SummaryLine = error.Message,
                    LastError = error.Message,
                }
            ];
        }

        var historyItems = historyStore.FetchHistory();
        var dictionaryEntries = historyStore.FetchDictionary();
        var focus = focusContextService.Capture();
        var providerSnapshots = BuildProviderSnapshots(capabilityRequest, capabilityResolution, selectionResolution, modelSelection, runtimeSnapshots);
        var tips = BuildTips(selectionResolution, permission, bridgeError);

        return new WindowsShellSnapshot
        {
            StatusMessage = statusMessage ?? selectionResolution.EffectiveProviderMessage ?? bridgeError,
            Settings = Settings,
            SelectedProvider = Settings.SelectedProvider,
            EffectiveProvider = selectionResolution.EffectiveProvider,
            Providers = providerSnapshots,
            CurrentLanguageOptions = modelSelection.CurrentLanguageOptions.Count > 0
                ? modelSelection.CurrentLanguageOptions
                : CurrentLanguageOptions(Settings.SelectedProvider),
            WhisperModels = modelCatalog.ModelsForProvider(ProviderIds.Whisper).ToList(),
            ParakeetModels = modelCatalog.ModelsForProvider(ProviderIds.Parakeet).ToList(),
            Diagnostics = diagnostics,
            HistoryItems = historyItems,
            DictionaryEntries = dictionaryEntries,
            Paths = paths,
            RuntimeSnapshots = runtimeSnapshots,
            Permission = permission,
            FocusContext = focus,
            Tips = tips,
            IsRecording = recordingManager.IsRecording,
        };
    }

    private Dictionary<string, ProviderAvailability> BuildAvailability(PermissionStatus permission)
    {
        var whisperBinary = File.Exists(Path.Combine(paths.Runtime, "whisper-server-windows-x64.exe"));
        var parakeetBinary = File.Exists(Path.Combine(paths.Runtime, "sherpa-onnx-ws-windows-x64.exe"));
        var hasNvidia = systemProfileService.Current().Accelerator == "nvidia_cuda";

        return new Dictionary<string, ProviderAvailability>
        {
            [ProviderIds.AppleSpeech] = new() { IsAvailable = false, Reason = "Apple Speech is not available on Windows." },
            [ProviderIds.Whisper] = new()
            {
                IsAvailable = permission.IsGranted && whisperBinary,
                Reason = !permission.IsGranted
                    ? permission.Message
                    : whisperBinary
                        ? null
                        : "whisper-server is not staged in Verbatim Runtime.",
            },
            [ProviderIds.Parakeet] = new()
            {
                IsAvailable = permission.IsGranted && hasNvidia && parakeetBinary,
                Reason = !permission.IsGranted
                    ? permission.Message
                    : hasNvidia
                        ? (parakeetBinary ? null : "sherpa-onnx runtime is not staged in Verbatim Runtime.")
                        : "Parakeet requires an NVIDIA CUDA-capable Windows system.",
            },
        };
    }

    private Dictionary<string, ProviderReadiness> BuildReadiness(Dictionary<string, RuntimeHealthSnapshot> runtimeSnapshots)
    {
        var whisperInstalled = modelCatalog.BuildStatuses(ProviderIds.Whisper)
            .Any(model => model.Id == Settings.SelectedWhisperModelID && model.IsInstalled);
        var parakeetInstalled = modelCatalog.BuildStatuses(ProviderIds.Parakeet)
            .Any(model => model.Id == Settings.SelectedParakeetModelID && model.IsInstalled);
        var hasNvidia = systemProfileService.Current().Accelerator == "nvidia_cuda";

        return new Dictionary<string, ProviderReadiness>
        {
            [ProviderIds.AppleSpeech] = new()
            {
                Kind = ProviderReadinessKinds.Unavailable,
                Message = "Apple Speech is only available on Apple Silicon Macs.",
            },
            [ProviderIds.Whisper] = WhisperReadiness(runtimeSnapshots.GetValueOrDefault(ProviderIds.Whisper), whisperInstalled),
            [ProviderIds.Parakeet] = ParakeetReadiness(runtimeSnapshots.GetValueOrDefault(ProviderIds.Parakeet), parakeetInstalled, hasNvidia),
        };
    }

    private static ProviderReadiness WhisperReadiness(RuntimeHealthSnapshot? runtime, bool installed)
    {
        if (runtime?.BinaryPresent != true)
        {
            return new ProviderReadiness
            {
                Kind = ProviderReadinessKinds.Unavailable,
                Message = "whisper-server is missing from the runtime bundle.",
            };
        }

        if (!installed)
        {
            return new ProviderReadiness
            {
                Kind = ProviderReadinessKinds.Installable,
                Message = "Download the selected Whisper model first.",
                ActionTitle = "Download",
            };
        }

        return new ProviderReadiness
        {
            Kind = ProviderReadinessKinds.Ready,
            Message = runtime?.State == "ready"
                ? "Whisper runtime is healthy."
                : "Whisper is ready. Runtime will launch when you start transcription.",
        };
    }

    private static ProviderReadiness ParakeetReadiness(RuntimeHealthSnapshot? runtime, bool installed, bool hasNvidia)
    {
        if (!hasNvidia)
        {
            return new ProviderReadiness
            {
                Kind = ProviderReadinessKinds.Unavailable,
                Message = "Parakeet currently requires Windows with an NVIDIA CUDA-compatible system.",
            };
        }

        if (runtime?.BinaryPresent != true)
        {
            return new ProviderReadiness
            {
                Kind = ProviderReadinessKinds.Unavailable,
                Message = "sherpa-onnx runtime is missing from the runtime bundle.",
            };
        }

        if (!installed)
        {
            return new ProviderReadiness
            {
                Kind = ProviderReadinessKinds.Installable,
                Message = "Download the selected Parakeet model first.",
                ActionTitle = "Download",
            };
        }

        return new ProviderReadiness
        {
            Kind = ProviderReadinessKinds.Ready,
            Message = runtime?.State == "ready"
                ? "Parakeet runtime is healthy."
                : "Parakeet is ready. Runtime will launch when you start transcription.",
        };
    }

    private IReadOnlyList<ProviderShellSnapshot> BuildProviderSnapshots(
        CapabilityResolutionRequest capabilityRequest,
        SharedCoreCapabilityResolution capabilityResolution,
        SharedCoreSelectionResolution selectionResolution,
        ProviderModelSelectionResolution modelSelection,
        Dictionary<string, RuntimeHealthSnapshot> runtimeSnapshots)
    {
        return capabilityManifest.Providers.Select(provider => new ProviderShellSnapshot
        {
            ProviderId = provider.Provider,
            Title = provider.Title,
            IsSelected = Settings.SelectedProvider == provider.Provider,
            IsEffective = selectionResolution.EffectiveProvider == provider.Provider,
            Capability = capabilityResolution.ProviderCapabilities.GetValueOrDefault(provider.Provider) ?? new CapabilityStatus(),
            Availability = capabilityRequest.Availability.GetValueOrDefault(provider.Provider) ?? new ProviderAvailability(),
            Readiness = capabilityRequest.Readiness.GetValueOrDefault(provider.Provider) ?? new ProviderReadiness(),
            Runtime = runtimeSnapshots.GetValueOrDefault(provider.Provider),
            SelectedLanguage = Settings.PreferredLanguages.ForProvider(provider.Provider),
            CurrentLanguageOptions = provider.Provider == Settings.SelectedProvider
                ? (modelSelection.CurrentLanguageOptions.Count > 0 ? modelSelection.CurrentLanguageOptions : CurrentLanguageOptions(provider.Provider))
                : CurrentLanguageOptions(provider.Provider),
            Models = modelCatalog.ModelsForProvider(provider.Provider).ToList(),
        }).ToList();
    }

    private IReadOnlyList<string> BuildTips(
        SharedCoreSelectionResolution selectionResolution,
        PermissionStatus permission,
        string? bridgeError)
    {
        var tips = new List<string>
        {
            "Apple Speech requires an explicit language and defaults to English.",
            "Whisper auto-detect preserves the spoken language and does not translate.",
            "Parakeet is auto-detect only and activates only on Windows with NVIDIA CUDA support.",
            permission.IsGranted
                ? "Microphone capture is available."
                : $"Microphone capture is unavailable. Open {permission.ActionUri ?? "Windows settings"} to enable it.",
        };

        if (!string.IsNullOrWhiteSpace(selectionResolution.EffectiveProviderMessage))
        {
            tips.Add(selectionResolution.EffectiveProviderMessage!);
        }

        if (!string.IsNullOrWhiteSpace(bridgeError))
        {
            tips.Add($"Shared Rust contract fallback: {bridgeError}");
        }

        return tips;
    }

    private IReadOnlyList<LanguageSelection> CurrentLanguageOptions(string providerId)
        => providerId switch
        {
            ProviderIds.AppleSpeech => AppleLanguageOptions(),
            ProviderIds.Parakeet => [LanguageSelection.Auto],
            _ => WhisperLanguageOptions(),
        };

    private static List<LanguageSelection> AppleLanguageOptions()
        => [
            new LanguageSelection { Identifier = "en-US" },
            new LanguageSelection { Identifier = "es-ES" },
            new LanguageSelection { Identifier = "pt-BR" },
            new LanguageSelection { Identifier = "ru-RU" },
        ];

    private static List<LanguageSelection> WhisperLanguageOptions()
        => [
            LanguageSelection.Auto,
            new LanguageSelection { Identifier = "en" },
            new LanguageSelection { Identifier = "es" },
            new LanguageSelection { Identifier = "pt" },
            new LanguageSelection { Identifier = "ru" },
        ];

    private string SelectedModelDescription(string providerId, string modelId)
        => modelCatalog.ModelsForProvider(providerId)
            .FirstOrDefault(model => model.Id == modelId)?.Detail
            ?? "No model description available.";

    private ModelDescriptor? CurrentModelDescriptor()
    {
        var modelId = Settings.SelectedProvider == ProviderIds.Parakeet
            ? Settings.SelectedParakeetModelID
            : Settings.SelectedWhisperModelID;
        return modelCatalog.ModelsForProvider(Settings.SelectedProvider).FirstOrDefault(model => model.Id == modelId);
    }

    private static string ProviderTitle(string providerId) => providerId switch
    {
        ProviderIds.AppleSpeech => "Apple Speech",
        ProviderIds.Parakeet => "Parakeet",
        _ => "Whisper",
    };
}

internal sealed class WindowsShellSnapshot
{
    public string? StatusMessage { get; set; }
    public AppSettings Settings { get; set; } = new();
    public string SelectedProvider { get; set; } = ProviderIds.Whisper;
    public string EffectiveProvider { get; set; } = ProviderIds.Whisper;
    public IReadOnlyList<ProviderShellSnapshot> Providers { get; set; } = [];
    public IReadOnlyList<LanguageSelection> CurrentLanguageOptions { get; set; } = [];
    public IReadOnlyList<ModelDescriptor> WhisperModels { get; set; } = [];
    public IReadOnlyList<ModelDescriptor> ParakeetModels { get; set; } = [];
    public IReadOnlyList<ProviderDiagnosticReduction> Diagnostics { get; set; } = [];
    public IReadOnlyList<HistoryItem> HistoryItems { get; set; } = [];
    public IReadOnlyList<DictionaryEntry> DictionaryEntries { get; set; } = [];
    public VerbatimAppPaths Paths { get; set; } = VerbatimAppPaths.Current();
    public Dictionary<string, RuntimeHealthSnapshot> RuntimeSnapshots { get; set; } = [];
    public PermissionStatus Permission { get; set; } = new(false, "Unknown", null);
    public ActiveContextSnapshot FocusContext { get; set; } = new("Unknown app", null, null, null, null, null, null);
    public IReadOnlyList<string> Tips { get; set; } = [];
    public bool IsRecording { get; set; }
}

internal sealed class ProviderShellSnapshot
{
    public string ProviderId { get; set; } = ProviderIds.Whisper;
    public string Title { get; set; } = "Whisper";
    public bool IsSelected { get; set; }
    public bool IsEffective { get; set; }
    public CapabilityStatus Capability { get; set; } = new();
    public ProviderAvailability Availability { get; set; } = new();
    public ProviderReadiness Readiness { get; set; } = new();
    public RuntimeHealthSnapshot? Runtime { get; set; }
    public string SelectedLanguage { get; set; } = "auto";
    public IReadOnlyList<LanguageSelection> CurrentLanguageOptions { get; set; } = [];
    public IReadOnlyList<ModelDescriptor> Models { get; set; } = [];
}
