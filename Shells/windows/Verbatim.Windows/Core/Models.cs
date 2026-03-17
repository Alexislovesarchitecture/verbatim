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

internal sealed class EmptyResponse
{
}

internal static class TriggerModes
{
    internal const string Hold = "hold";
    internal const string Toggle = "toggle";
    internal const string DoubleTapLock = "double_tap_lock";
}

internal static class InputEvents
{
    internal const string TriggerDown = "trigger_down";
    internal const string TriggerUp = "trigger_up";
    internal const string TriggerToggle = "trigger_toggle";
}

internal static class DictationActions
{
    internal const string None = "none";
    internal const string StartRecording = "start_recording";
    internal const string StopRecording = "stop_recording";
    internal const string CancelRecording = "cancel_recording";
}

internal static class HotkeyBackends
{
    internal const string EventMonitor = "event_monitor";
    internal const string FunctionKeySpecialCase = "function_key_special_case";
    internal const string Fallback = "fallback";
    internal const string Unavailable = "unavailable";
}

internal static class StyleCategories
{
    internal const string PersonalMessages = "personal_messages";
    internal const string WorkMessages = "work_messages";
    internal const string Email = "email";
    internal const string Other = "other";
}

internal static class StylePresets
{
    internal const string Formal = "formal";
    internal const string Casual = "casual";
    internal const string Enthusiastic = "enthusiastic";
    internal const string VeryCasual = "very_casual";
}

internal static class StyleDecisionSources
{
    internal const string FocusedField = "focused_field";
    internal const string WindowTitle = "window_title";
    internal const string BundleId = "bundle_id";
    internal const string Fallback = "fallback";
}

internal sealed class PrepareTriggerRequest
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = TriggerModes.Hold;
}

internal sealed class HotkeyStartResultPayload
{
    [JsonPropertyName("backend")]
    public string Backend { get; set; } = HotkeyBackends.Unavailable;

    [JsonPropertyName("effectiveTriggerLabel")]
    public string EffectiveTriggerLabel { get; set; } = string.Empty;

    [JsonPropertyName("originalTriggerLabel")]
    public string OriginalTriggerLabel { get; set; } = string.Empty;

    [JsonPropertyName("fallbackWasUsed")]
    public bool FallbackWasUsed { get; set; }

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("recommendedFallbackLabel")]
    public string? RecommendedFallbackLabel { get; set; }

    [JsonPropertyName("permissionGranted")]
    public bool PermissionGranted { get; set; }

    [JsonPropertyName("isActive")]
    public bool IsActive { get; set; }
}

internal sealed class SummarizeTriggerStateRequest
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = TriggerModes.Hold;

    [JsonPropertyName("startResult")]
    public HotkeyStartResultPayload StartResult { get; set; } = new();
}

internal sealed class TriggerStateSummary
{
    [JsonPropertyName("statusMessage")]
    public string StatusMessage { get; set; } = string.Empty;

    [JsonPropertyName("effectiveTriggerLabel")]
    public string EffectiveTriggerLabel { get; set; } = string.Empty;

    [JsonPropertyName("backendLabel")]
    public string BackendLabel { get; set; } = string.Empty;

    [JsonPropertyName("fallbackReason")]
    public string? FallbackReason { get; set; }

    [JsonPropertyName("isAvailable")]
    public bool IsAvailable { get; set; }
}

internal sealed class HandleInputEventRequest
{
    [JsonPropertyName("event")]
    public string Event { get; set; } = InputEvents.TriggerDown;

    [JsonPropertyName("isRecording")]
    public bool IsRecording { get; set; }

    [JsonPropertyName("timestampMs")]
    public long TimestampMs { get; set; }
}

internal sealed class HandleInputEventResponse
{
    [JsonPropertyName("action")]
    public string Action { get; set; } = DictationActions.None;
}

internal sealed class ActiveAppContext
{
    [JsonPropertyName("appName")]
    public string AppName { get; set; } = string.Empty;

    [JsonPropertyName("bundleId")]
    public string BundleId { get; set; } = string.Empty;

    [JsonPropertyName("processIdentifier")]
    public int? ProcessIdentifier { get; set; }

    [JsonPropertyName("styleCategory")]
    public string StyleCategory { get; set; } = StyleCategories.Other;

    [JsonPropertyName("windowTitle")]
    public string? WindowTitle { get; set; }

    [JsonPropertyName("focusedElementRole")]
    public string? FocusedElementRole { get; set; }

    [JsonPropertyName("focusedElementSubrole")]
    public string? FocusedElementSubrole { get; set; }

    [JsonPropertyName("focusedElementTitle")]
    public string? FocusedElementTitle { get; set; }

    [JsonPropertyName("focusedElementPlaceholder")]
    public string? FocusedElementPlaceholder { get; set; }

    [JsonPropertyName("focusedElementDescription")]
    public string? FocusedElementDescription { get; set; }

    [JsonPropertyName("focusedValueSnippet")]
    public string? FocusedValueSnippet { get; set; }
}

internal sealed class ResolveStyleContextRequest
{
    [JsonPropertyName("context")]
    public ActiveAppContext Context { get; set; } = new();

    [JsonPropertyName("settings")]
    public StyleSettings Settings { get; set; } = new();
}

internal sealed class StyleDecisionReport
{
    [JsonPropertyName("category")]
    public string Category { get; set; } = StyleCategories.Other;

    [JsonPropertyName("preset")]
    public string Preset { get; set; } = StylePresets.Casual;

    [JsonPropertyName("source")]
    public string Source { get; set; } = StyleDecisionSources.Fallback;

    [JsonPropertyName("confidence")]
    public double Confidence { get; set; }

    [JsonPropertyName("formattingEnabled")]
    public bool FormattingEnabled { get; set; }

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }

    [JsonPropertyName("outputPreview")]
    public string? OutputPreview { get; set; }
}

internal sealed class DictionaryEntryInput
{
    [JsonPropertyName("phrase")]
    public string Phrase { get; set; } = string.Empty;

    [JsonPropertyName("hint")]
    public string Hint { get; set; } = string.Empty;
}

internal sealed class ProcessTranscriptRequest
{
    [JsonPropertyName("text")]
    public string Text { get; set; } = string.Empty;

    [JsonPropertyName("context")]
    public ActiveAppContext? Context { get; set; }

    [JsonPropertyName("settings")]
    public StyleSettings Settings { get; set; } = new();

    [JsonPropertyName("resolvedDecision")]
    public StyleDecisionReport? ResolvedDecision { get; set; }

    [JsonPropertyName("dictionaryEntries")]
    public List<DictionaryEntryInput> DictionaryEntries { get; set; } = [];
}

internal sealed class ProcessTranscriptResponse
{
    [JsonPropertyName("cleanedText")]
    public string CleanedText { get; set; } = string.Empty;

    [JsonPropertyName("finalText")]
    public string FinalText { get; set; } = string.Empty;

    [JsonPropertyName("changed")]
    public bool Changed { get; set; }

    [JsonPropertyName("decision")]
    public StyleDecisionReport Decision { get; set; } = new();
}
