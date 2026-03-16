using System.Runtime.InteropServices;
using System.Text.Json;

namespace Verbatim.Windows.Core;

internal static class VerbatimCoreBridge
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    private static readonly Lazy<nint> Engine = new(verbatim_core_engine_new);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_engine_new();

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern void verbatim_core_engine_free(nint engine);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_resolve_capabilities(nint engine, string requestJson);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_resolve_selection(nint engine, string requestJson);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_resolve_provider_model_selection(nint engine, string requestJson);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_build_history_sections(nint engine, string requestJson);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_reduce_provider_diagnostics(nint engine, string requestJson);

    [DllImport("verbatim_core_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint verbatim_core_free_string(nint value);

    internal static SharedCoreCapabilityResolution ResolveCapabilities(CapabilityResolutionRequest request)
        => Call<CapabilityResolutionRequest, SharedCoreCapabilityResolution>(verbatim_core_resolve_capabilities, request);

    internal static SharedCoreSelectionResolution ResolveSelection(SelectionResolutionRequest request)
        => Call<SelectionResolutionRequest, SharedCoreSelectionResolution>(verbatim_core_resolve_selection, request);

    internal static ProviderModelSelectionResolution ResolveProviderModelSelection(ProviderModelSelectionRequest request)
        => Call<ProviderModelSelectionRequest, ProviderModelSelectionResolution>(verbatim_core_resolve_provider_model_selection, request);

    internal static IReadOnlyList<HistorySectionReduction> BuildHistorySections(HistorySectionsRequest request)
        => Call<HistorySectionsRequest, List<HistorySectionReduction>>(verbatim_core_build_history_sections, request);

    internal static IReadOnlyList<ProviderDiagnosticReduction> ReduceProviderDiagnostics(ProviderDiagnosticsRequest request)
        => Call<ProviderDiagnosticsRequest, List<ProviderDiagnosticReduction>>(verbatim_core_reduce_provider_diagnostics, request);

    private static TResponse Call<TRequest, TResponse>(Func<nint, string, nint> function, TRequest request)
    {
        var requestJson = JsonSerializer.Serialize(request, JsonOptions);
        var resultPtr = function(Engine.Value, requestJson);
        try
        {
            var resultJson = Marshal.PtrToStringUTF8(resultPtr) ?? string.Empty;
            using var document = JsonDocument.Parse(resultJson);
            var root = document.RootElement;
            if (!root.TryGetProperty("ok", out var okElement) || !okElement.GetBoolean())
            {
                var error = root.TryGetProperty("error", out var errorElement) ? errorElement.GetString() : "Unknown Rust bridge error.";
                throw new InvalidOperationException(error);
            }

            var value = root.GetProperty("value").GetRawText();
            return JsonSerializer.Deserialize<TResponse>(value, JsonOptions)
                   ?? throw new InvalidOperationException("Rust bridge returned an empty payload.");
        }
        finally
        {
            verbatim_core_free_string(resultPtr);
        }
    }
}
