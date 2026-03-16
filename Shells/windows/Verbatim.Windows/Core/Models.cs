using System.Text.Json.Serialization;

namespace Verbatim.Windows.Core;

internal static class ProviderIds
{
    internal const string AppleSpeech = "apple_speech";
    internal const string Whisper = "whisper";
    internal const string Parakeet = "parakeet";

    internal static readonly string[] All = [AppleSpeech, Whisper, Parakeet];
}

internal static class FeatureIds
{
    internal const string ProviderSelection = "provider_selection";
    internal const string AutoPaste = "auto_paste";
    internal const string HotkeyCapture = "hotkey_capture";
    internal const string ModelManagement = "model_management";
    internal const string AppleSpeechAssets = "apple_speech_assets";
}

internal static class CapabilityKinds
{
    internal const string Available = "available";
    internal const string Unsupported = "unsupported";
    internal const string SupportedButNotReady = "supported_but_not_ready";
}

internal static class ProviderReadinessKinds
{
    internal const string Ready = "ready";
    internal const string Installable = "installable";
    internal const string Unavailable = "unavailable";
}

internal sealed class LanguageSelection
{
    [JsonPropertyName("identifier")]
    public string Identifier { get; set; } = "auto";

    [JsonIgnore]
    public bool IsAuto => Identifier == "auto";

    internal static LanguageSelection Auto => new() { Identifier = "auto" };
}

internal sealed class ProviderLanguageSettings
{
    [JsonPropertyName("appleSpeechID")]
    public string AppleSpeechID { get; set; } = "en-US";

    [JsonPropertyName("whisperID")]
    public string WhisperID { get; set; } = "auto";

    [JsonPropertyName("parakeetID")]
    public string ParakeetID { get; set; } = "auto";

    internal string ForProvider(string providerId) => providerId switch
    {
        ProviderIds.AppleSpeech => AppleSpeechID,
        ProviderIds.Parakeet => ParakeetID,
        _ => WhisperID,
    };

    internal void SetForProvider(string providerId, string identifier)
    {
        switch (providerId)
        {
            case ProviderIds.AppleSpeech:
                AppleSpeechID = Normalize(providerId, identifier);
                break;
            case ProviderIds.Parakeet:
                ParakeetID = Normalize(providerId, identifier);
                break;
            default:
                WhisperID = Normalize(providerId, identifier);
                break;
        }
    }

    internal void Normalize()
    {
        AppleSpeechID = Normalize(ProviderIds.AppleSpeech, AppleSpeechID);
        WhisperID = Normalize(ProviderIds.Whisper, WhisperID);
        ParakeetID = Normalize(ProviderIds.Parakeet, ParakeetID);
    }

    private static string Normalize(string providerId, string identifier)
    {
        var trimmed = (identifier ?? string.Empty).Trim();
        return providerId switch
        {
            ProviderIds.AppleSpeech => string.IsNullOrWhiteSpace(trimmed) || trimmed == "auto" ? "en-US" : trimmed,
            ProviderIds.Parakeet => "auto",
            _ => string.IsNullOrWhiteSpace(trimmed) ? "auto" : trimmed,
        };
    }
}

internal sealed class StyleCategorySettings
{
    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; }

    [JsonPropertyName("preset")]
    public string Preset { get; set; } = "casual";
}

internal sealed class StyleSettings
{
    [JsonPropertyName("personalMessages")]
    public StyleCategorySettings PersonalMessages { get; set; } = new() { Preset = "casual" };

    [JsonPropertyName("workMessages")]
    public StyleCategorySettings WorkMessages { get; set; } = new() { Preset = "formal" };

    [JsonPropertyName("email")]
    public StyleCategorySettings Email { get; set; } = new() { Preset = "formal" };

    [JsonPropertyName("other")]
    public StyleCategorySettings Other { get; set; } = new() { Preset = "casual" };
}

internal sealed class HotkeySettings
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "hold";

    [JsonPropertyName("modifiers")]
    public uint Modifiers { get; set; } = 0x0002 | 0x0004;

    [JsonPropertyName("virtualKey")]
    public uint VirtualKey { get; set; } = 0x20;

    [JsonPropertyName("displayTitle")]
    public string DisplayTitle { get; set; } = "Ctrl+Shift+Space";
}

internal sealed class AppSettings
{
    [JsonPropertyName("selectedProvider")]
    public string SelectedProvider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("preferredLanguages")]
    public ProviderLanguageSettings PreferredLanguages { get; set; } = new();

    [JsonPropertyName("selectedWhisperModelID")]
    public string SelectedWhisperModelID { get; set; } = "base";

    [JsonPropertyName("selectedParakeetModelID")]
    public string SelectedParakeetModelID { get; set; } = "parakeet-tdt-0.6b-v3";

    [JsonPropertyName("styleSettings")]
    public StyleSettings StyleSettings { get; set; } = new();

    [JsonPropertyName("hotkey")]
    public HotkeySettings Hotkey { get; set; } = new();

    [JsonPropertyName("pasteMode")]
    public string PasteMode { get; set; } = "auto_paste";

    [JsonPropertyName("onboardingCompleted")]
    public bool OnboardingCompleted { get; set; }

    internal void Normalize()
    {
        if (!ProviderIds.All.Contains(SelectedProvider))
        {
            SelectedProvider = ProviderIds.Whisper;
        }

        PreferredLanguages.Normalize();
        Hotkey.Mode = Hotkey.Mode switch
        {
            "toggle" => "toggle",
            "double_tap_lock" => "double_tap_lock",
            _ => "hold",
        };
        PasteMode = PasteMode == "clipboard_only" ? "clipboard_only" : "auto_paste";
        SelectedWhisperModelID = string.IsNullOrWhiteSpace(SelectedWhisperModelID) ? "base" : SelectedWhisperModelID;
        SelectedParakeetModelID = string.IsNullOrWhiteSpace(SelectedParakeetModelID) ? "parakeet-tdt-0.6b-v3" : SelectedParakeetModelID;
    }
}

internal sealed class DictionaryEntry
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [JsonPropertyName("phrase")]
    public string Phrase { get; set; } = string.Empty;

    [JsonPropertyName("hint")]
    public string Hint { get; set; } = string.Empty;
}

internal sealed class HistoryItem
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("timestampMs")]
    public long TimestampMs { get; set; }

    [JsonPropertyName("provider")]
    public string Provider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("language")]
    public string Language { get; set; } = "auto";

    [JsonPropertyName("originalText")]
    public string OriginalText { get; set; } = string.Empty;

    [JsonPropertyName("finalPastedText")]
    public string FinalPastedText { get; set; } = string.Empty;

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}

internal sealed class HistorySectionReduction
{
    [JsonPropertyName("bucketTimestampMs")]
    public long BucketTimestampMs { get; set; }

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("items")]
    public List<HistoryItem> Items { get; set; } = [];
}

internal sealed class ProviderAvailability
{
    [JsonPropertyName("isAvailable")]
    public bool IsAvailable { get; set; }

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }
}

internal sealed class ProviderReadiness
{
    [JsonPropertyName("kind")]
    public string Kind { get; set; } = ProviderReadinessKinds.Unavailable;

    [JsonPropertyName("message")]
    public string Message { get; set; } = "Unavailable";

    [JsonPropertyName("actionTitle")]
    public string? ActionTitle { get; set; }
}

internal sealed class CapabilityStatus
{
    [JsonPropertyName("kind")]
    public string Kind { get; set; } = CapabilityKinds.Unsupported;

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }

    [JsonPropertyName("actionTitle")]
    public string? ActionTitle { get; set; }
}

internal sealed class CapabilityRequirement
{
    [JsonPropertyName("allowedOSFamilies")]
    public string[] AllowedOSFamilies { get; set; } = [];

    [JsonPropertyName("allowedArchitectures")]
    public string[] AllowedArchitectures { get; set; } = [];

    [JsonPropertyName("requiredAccelerators")]
    public string[] RequiredAccelerators { get; set; } = [];
}

internal sealed class ProviderCapabilityDescriptor
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("requirements")]
    public CapabilityRequirement Requirements { get; set; } = new();

    [JsonPropertyName("unsupportedReason")]
    public string UnsupportedReason { get; set; } = string.Empty;
}

internal sealed class FeatureCapabilityDescriptor
{
    [JsonPropertyName("feature")]
    public string Feature { get; set; } = FeatureIds.ProviderSelection;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("requirements")]
    public CapabilityRequirement Requirements { get; set; } = new();

    [JsonPropertyName("unsupportedReason")]
    public string UnsupportedReason { get; set; } = string.Empty;
}

internal sealed class CapabilityManifest
{
    [JsonPropertyName("providers")]
    public List<ProviderCapabilityDescriptor> Providers { get; set; } = [];

    [JsonPropertyName("features")]
    public List<FeatureCapabilityDescriptor> Features { get; set; } = [];
}

internal sealed class ModelDescriptor
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("provider")]
    public string Provider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("detail")]
    public string Detail { get; set; } = string.Empty;

    [JsonPropertyName("sizeLabel")]
    public string SizeLabel { get; set; } = string.Empty;

    [JsonPropertyName("downloadURL")]
    public string? DownloadUrl { get; set; }

    [JsonPropertyName("expectedSizeBytes")]
    public long? ExpectedSizeBytes { get; set; }

    [JsonPropertyName("fileName")]
    public string? FileName { get; set; }

    [JsonPropertyName("extractDirectory")]
    public string? ExtractDirectory { get; set; }

    [JsonPropertyName("supportedLanguageIDs")]
    public List<string> SupportedLanguageIds { get; set; } = [];

    [JsonPropertyName("recommended")]
    public bool Recommended { get; set; }
}

internal sealed class ModelManifestEnvelope
{
    [JsonPropertyName("models")]
    public List<ModelDescriptor> Models { get; set; } = [];
}

internal sealed class ProviderModelStatusInput
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("supportedLanguageIDs")]
    public List<string> SupportedLanguageIds { get; set; } = [];

    [JsonPropertyName("isInstalled")]
    public bool IsInstalled { get; set; }
}

internal sealed class ProviderModelSelectionResolution
{
    [JsonPropertyName("currentLanguageOptions")]
    public List<LanguageSelection> CurrentLanguageOptions { get; set; } = [];

    [JsonPropertyName("selectedWhisperDescription")]
    public string SelectedWhisperDescription { get; set; } = string.Empty;

    [JsonPropertyName("selectedWhisperInstalled")]
    public bool SelectedWhisperInstalled { get; set; }

    [JsonPropertyName("selectedParakeetDescription")]
    public string SelectedParakeetDescription { get; set; } = string.Empty;

    [JsonPropertyName("selectedParakeetInstalled")]
    public bool SelectedParakeetInstalled { get; set; }
}

internal sealed class SharedCoreCapabilityResolution
{
    [JsonPropertyName("providerCapabilities")]
    public Dictionary<string, CapabilityStatus> ProviderCapabilities { get; set; } = [];

    [JsonPropertyName("featureCapabilities")]
    public Dictionary<string, CapabilityStatus> FeatureCapabilities { get; set; } = [];

    [JsonPropertyName("effectiveProvider")]
    public string EffectiveProvider { get; set; } = ProviderIds.Whisper;
}

internal sealed class SharedCoreSelectionResolution
{
    [JsonPropertyName("effectiveProvider")]
    public string EffectiveProvider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("effectiveLanguages")]
    public ProviderLanguageSettings EffectiveLanguages { get; set; } = new();

    [JsonPropertyName("effectiveProviderMessage")]
    public string? EffectiveProviderMessage { get; set; }
}

internal sealed class ProviderDiagnosticInput
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("capability")]
    public CapabilityStatus Capability { get; set; } = new();

    [JsonPropertyName("availability")]
    public ProviderAvailability Availability { get; set; } = new();

    [JsonPropertyName("readiness")]
    public ProviderReadiness Readiness { get; set; } = new();

    [JsonPropertyName("runtimeStateLabel")]
    public string? RuntimeStateLabel { get; set; }

    [JsonPropertyName("runtimeError")]
    public string? RuntimeError { get; set; }
}

internal sealed class ProviderDiagnosticReduction
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("lastError")]
    public string? LastError { get; set; }

    [JsonPropertyName("summaryLine")]
    public string SummaryLine { get; set; } = string.Empty;
}

internal sealed class RuntimeHealthSnapshot
{
    public string BinaryName { get; set; } = string.Empty;
    public bool BinaryPresent { get; set; }
    public string State { get; set; } = "stopped";
    public string? Endpoint { get; set; }
    public DateTimeOffset? LastCheck { get; set; }
    public string? LastError { get; set; }
}

internal sealed class SystemProfilePayload
{
    [JsonPropertyName("osFamily")]
    public string OsFamily { get; set; } = "windows";

    [JsonPropertyName("osVersion")]
    public SystemVersionPayload OsVersion { get; set; } = new();

    [JsonPropertyName("architecture")]
    public string Architecture { get; set; } = "x86_64";

    [JsonPropertyName("accelerator")]
    public string Accelerator { get; set; } = "none";
}

internal sealed class SystemVersionPayload
{
    [JsonPropertyName("major")]
    public int Major { get; set; }

    [JsonPropertyName("minor")]
    public int Minor { get; set; }

    [JsonPropertyName("patch")]
    public int Patch { get; set; }
}

internal sealed class CapabilityResolutionRequest
{
    [JsonPropertyName("manifest")]
    public CapabilityManifest Manifest { get; set; } = new();

    [JsonPropertyName("profile")]
    public SystemProfilePayload Profile { get; set; } = new();

    [JsonPropertyName("storedProvider")]
    public string StoredProvider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("fallbackOrder")]
    public List<string> FallbackOrder { get; set; } = [ProviderIds.Whisper, ProviderIds.AppleSpeech, ProviderIds.Parakeet];

    [JsonPropertyName("availability")]
    public Dictionary<string, ProviderAvailability> Availability { get; set; } = [];

    [JsonPropertyName("readiness")]
    public Dictionary<string, ProviderReadiness> Readiness { get; set; } = [];
}

internal sealed class SelectionResolutionRequest
{
    [JsonPropertyName("storedProvider")]
    public string StoredProvider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("fallbackOrder")]
    public List<string> FallbackOrder { get; set; } = [ProviderIds.Whisper, ProviderIds.AppleSpeech, ProviderIds.Parakeet];

    [JsonPropertyName("capabilities")]
    public Dictionary<string, CapabilityStatus> Capabilities { get; set; } = [];

    [JsonPropertyName("preferredLanguages")]
    public ProviderLanguageSettings PreferredLanguages { get; set; } = new();

    [JsonPropertyName("appleInstalledLanguages")]
    public List<LanguageSelection> AppleInstalledLanguages { get; set; } = [];
}

internal sealed class ProviderModelSelectionRequest
{
    [JsonPropertyName("selectedProvider")]
    public string SelectedProvider { get; set; } = ProviderIds.Whisper;

    [JsonPropertyName("selectedWhisperModelID")]
    public string SelectedWhisperModelID { get; set; } = "base";

    [JsonPropertyName("selectedParakeetModelID")]
    public string SelectedParakeetModelID { get; set; } = "parakeet-tdt-0.6b-v3";

    [JsonPropertyName("whisperStatuses")]
    public List<ProviderModelStatusInput> WhisperStatuses { get; set; } = [];

    [JsonPropertyName("parakeetStatuses")]
    public List<ProviderModelStatusInput> ParakeetStatuses { get; set; } = [];

    [JsonPropertyName("appleInstalledLanguages")]
    public List<LanguageSelection> AppleInstalledLanguages { get; set; } = [];
}

internal sealed class ProviderDiagnosticsRequest
{
    [JsonPropertyName("inputs")]
    public List<ProviderDiagnosticInput> Inputs { get; set; } = [];
}

internal sealed class HistorySectionsRequest
{
    [JsonPropertyName("items")]
    public List<HistoryItem> Items { get; set; } = [];

    [JsonPropertyName("searchText")]
    public string SearchText { get; set; } = string.Empty;

    [JsonPropertyName("nowTimestampMs")]
    public long NowTimestampMs { get; set; }

    [JsonPropertyName("utcOffsetSeconds")]
    public int UtcOffsetSeconds { get; set; }
}
