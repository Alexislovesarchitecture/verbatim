use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

const DOUBLE_TAP_THRESHOLD_MS: i64 = 350;

#[derive(Default)]
struct Engine {
    trigger_state: TriggerState,
}

#[derive(Default)]
struct TriggerState {
    mode: TriggerMode,
    is_pressed: bool,
    last_tap_at_ms: Option<i64>,
}

#[derive(Serialize)]
struct ResponseEnvelope<T: Serialize> {
    ok: bool,
    value: Option<T>,
    error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct EmptyResponse {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
enum ProviderID {
    AppleSpeech,
    Whisper,
    Parakeet,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum StyleCategory {
    PersonalMessages,
    WorkMessages,
    Email,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum StylePreset {
    Formal,
    Casual,
    Enthusiastic,
    VeryCasual,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum StyleDecisionSource {
    FocusedField,
    WindowTitle,
    BundleId,
    Fallback,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
enum TriggerMode {
    #[default]
    Hold,
    Toggle,
    DoubleTapLock,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum HotkeyBackend {
    EventMonitor,
    FunctionKeySpecialCase,
    Fallback,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum OperatingSystemFamily {
    Macos,
    Windows,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum CPUArchitecture {
    Arm64,
    X86_64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum AcceleratorClass {
    None,
    AppleSilicon,
    NvidiaCuda,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SystemVersionInfo {
    major: i32,
    minor: i32,
    patch: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SystemProfile {
    os_family: OperatingSystemFamily,
    os_version: SystemVersionInfo,
    architecture: CPUArchitecture,
    accelerator: AcceleratorClass,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityRequirement {
    allowed_os_families: Vec<OperatingSystemFamily>,
    allowed_architectures: Vec<CPUArchitecture>,
    required_accelerators: Vec<AcceleratorClass>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum CapabilityStatusKind {
    Available,
    Unsupported,
    SupportedButNotReady,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityStatus {
    kind: CapabilityStatusKind,
    reason: Option<String>,
    action_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderCapabilityDescriptor {
    provider: ProviderID,
    title: String,
    requirements: CapabilityRequirement,
    unsupported_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
enum FeatureID {
    ProviderSelection,
    AutoPaste,
    HotkeyCapture,
    ModelManagement,
    AppleSpeechAssets,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FeatureCapabilityDescriptor {
    feature: FeatureID,
    title: String,
    requirements: CapabilityRequirement,
    unsupported_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityManifest {
    providers: Vec<ProviderCapabilityDescriptor>,
    features: Vec<FeatureCapabilityDescriptor>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderAvailability {
    is_available: bool,
    reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum ProviderReadinessKind {
    Ready,
    Installable,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderReadiness {
    kind: ProviderReadinessKind,
    message: String,
    action_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityResolutionRequest {
    manifest: CapabilityManifest,
    profile: SystemProfile,
    stored_provider: ProviderID,
    fallback_order: Vec<ProviderID>,
    availability: HashMap<ProviderID, ProviderAvailability>,
    readiness: HashMap<ProviderID, ProviderReadiness>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityResolutionResponse {
    provider_capabilities: HashMap<ProviderID, CapabilityStatus>,
    feature_capabilities: HashMap<FeatureID, CapabilityStatus>,
    effective_provider: ProviderID,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct LanguageSelection {
    identifier: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderLanguageSettings {
    apple_speech_id: String,
    whisper_id: String,
    parakeet_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SelectionResolutionRequest {
    stored_provider: ProviderID,
    fallback_order: Vec<ProviderID>,
    capabilities: HashMap<ProviderID, CapabilityStatus>,
    preferred_languages: ProviderLanguageSettings,
    apple_installed_languages: Vec<LanguageSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SelectionResolutionResponse {
    effective_provider: ProviderID,
    effective_languages: ProviderLanguageSettings,
    effective_provider_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderModelStatusInput {
    id: String,
    name: String,
    supported_language_ids: Vec<String>,
    is_installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderModelSelectionRequest {
    selected_provider: ProviderID,
    selected_whisper_model_id: String,
    selected_parakeet_model_id: String,
    whisper_statuses: Vec<ProviderModelStatusInput>,
    parakeet_statuses: Vec<ProviderModelStatusInput>,
    apple_installed_languages: Vec<LanguageSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderModelSelectionResponse {
    current_language_options: Vec<LanguageSelection>,
    selected_whisper_description: String,
    selected_whisper_installed: bool,
    selected_parakeet_description: String,
    selected_parakeet_installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryItemReduction {
    id: i64,
    timestamp_ms: i64,
    provider: String,
    language: String,
    original_text: String,
    final_pasted_text: String,
    error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistorySectionReduction {
    bucket_timestamp_ms: i64,
    title: String,
    items: Vec<HistoryItemReduction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistorySectionsRequest {
    items: Vec<HistoryItemReduction>,
    search_text: String,
    now_timestamp_ms: i64,
    utc_offset_seconds: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderDiagnosticInput {
    provider: ProviderID,
    capability: CapabilityStatus,
    availability: ProviderAvailability,
    readiness: ProviderReadiness,
    runtime_state_label: Option<String>,
    runtime_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderDiagnosticReduction {
    provider: ProviderID,
    last_error: Option<String>,
    summary_line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderDiagnosticsRequest {
    inputs: Vec<ProviderDiagnosticInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum InputEvent {
    TriggerDown,
    TriggerUp,
    TriggerToggle,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum DictationAction {
    None,
    StartRecording,
    StopRecording,
    CancelRecording,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HotkeyStartResultPayload {
    backend: HotkeyBackend,
    effective_trigger_label: String,
    original_trigger_label: String,
    fallback_was_used: bool,
    message: Option<String>,
    recommended_fallback_label: Option<String>,
    permission_granted: bool,
    is_active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PrepareTriggerRequest {
    mode: TriggerMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SummarizeTriggerStateRequest {
    mode: TriggerMode,
    start_result: HotkeyStartResultPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SummarizeTriggerStateResponse {
    status_message: String,
    effective_trigger_label: String,
    backend_label: String,
    fallback_reason: Option<String>,
    is_available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HandleInputEventRequest {
    event: InputEvent,
    is_recording: bool,
    timestamp_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HandleInputEventResponse {
    action: DictationAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StyleCategorySettings {
    enabled: bool,
    preset: StylePreset,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StyleSettings {
    personal_messages: StyleCategorySettings,
    work_messages: StyleCategorySettings,
    email: StyleCategorySettings,
    other: StyleCategorySettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ActiveAppContext {
    app_name: String,
    bundle_id: String,
    process_identifier: Option<i32>,
    style_category: StyleCategory,
    window_title: Option<String>,
    focused_element_role: Option<String>,
    focused_element_subrole: Option<String>,
    focused_element_title: Option<String>,
    focused_element_placeholder: Option<String>,
    focused_element_description: Option<String>,
    focused_value_snippet: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResolveStyleContextRequest {
    context: ActiveAppContext,
    settings: StyleSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StyleDecisionReport {
    category: StyleCategory,
    preset: StylePreset,
    source: StyleDecisionSource,
    confidence: f64,
    formatting_enabled: bool,
    reason: Option<String>,
    output_preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProcessTranscriptRequest {
    text: String,
    context: Option<ActiveAppContext>,
    settings: StyleSettings,
    resolved_decision: Option<StyleDecisionReport>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProcessTranscriptResponse {
    cleaned_text: String,
    final_text: String,
    changed: bool,
    decision: StyleDecisionReport,
}

#[no_mangle]
pub extern "C" fn verbatim_core_engine_new() -> *mut c_void {
    Box::into_raw(Box::new(Engine::default())) as *mut c_void
}

#[no_mangle]
pub extern "C" fn verbatim_core_engine_free(engine: *mut c_void) {
    if engine.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(engine as *mut Engine));
    }
}

#[no_mangle]
pub extern "C" fn verbatim_core_version() -> *const c_char {
    static VERSION: &str = "0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn verbatim_core_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub extern "C" fn verbatim_core_prepare_trigger(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |engine, request: PrepareTriggerRequest| {
        engine.trigger_state.mode = request.mode;
        engine.trigger_state.is_pressed = false;
        engine.trigger_state.last_tap_at_ms = None;
        Ok(EmptyResponse {})
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_capabilities(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: CapabilityResolutionRequest| {
        let mut provider_capabilities = HashMap::new();
        for provider in [ProviderID::AppleSpeech, ProviderID::Whisper, ProviderID::Parakeet] {
            let availability = request
                .availability
                .get(&provider)
                .cloned()
                .unwrap_or(ProviderAvailability {
                    is_available: false,
                    reason: Some("Checking…".to_string()),
                });
            let readiness = request
                .readiness
                .get(&provider)
                .cloned()
                .unwrap_or(ProviderReadiness {
                    kind: ProviderReadinessKind::Unavailable,
                    message: "Checking…".to_string(),
                    action_title: None,
                });
            provider_capabilities.insert(
                provider.clone(),
                provider_capability(&request.manifest, &provider, &request.profile, &availability, &readiness),
            );
        }

        let mut feature_capabilities = HashMap::new();
        for feature in [
            FeatureID::ProviderSelection,
            FeatureID::AutoPaste,
            FeatureID::HotkeyCapture,
            FeatureID::ModelManagement,
            FeatureID::AppleSpeechAssets,
        ] {
            feature_capabilities.insert(
                feature.clone(),
                feature_capability(&request.manifest, &feature, &request.profile),
            );
        }

        Ok(CapabilityResolutionResponse {
            effective_provider: effective_provider(
                &request.stored_provider,
                &provider_capabilities,
                &request.fallback_order,
            ),
            provider_capabilities,
            feature_capabilities,
        })
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_selection(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: SelectionResolutionRequest| {
        Ok(resolve_selection_response(request))
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_provider_model_selection(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: ProviderModelSelectionRequest| {
        Ok(resolve_provider_model_selection(request))
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_build_history_sections(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: HistorySectionsRequest| {
        Ok(build_history_sections(request))
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_reduce_provider_diagnostics(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: ProviderDiagnosticsRequest| {
        Ok(reduce_provider_diagnostics(request.inputs))
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_summarize_trigger_state(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |engine, request: SummarizeTriggerStateRequest| {
        engine.trigger_state.mode = request.mode;
        engine.trigger_state.is_pressed = false;
        engine.trigger_state.last_tap_at_ms = None;
        let result = request.start_result;
        let status_message = if let Some(message) = result.message.clone() {
            message
        } else if !result.is_active {
            "No global hotkey could be activated.".to_string()
        } else if result.fallback_was_used {
            format!("Using {} as the active fallback.", result.effective_trigger_label)
        } else {
            format!("Hotkey active: {}", result.effective_trigger_label)
        };
        let fallback_reason = if result.fallback_was_used {
            result.message.clone()
        } else {
            None
        };
        Ok(SummarizeTriggerStateResponse {
            effective_trigger_label: result.effective_trigger_label,
            status_message,
            backend_label: backend_title(&result.backend),
            fallback_reason,
            is_available: result.is_active,
        })
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_handle_input_event(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |engine, request: HandleInputEventRequest| {
        let action = match engine.trigger_state.mode {
            TriggerMode::Hold => match request.event {
                InputEvent::TriggerDown => {
                    if engine.trigger_state.is_pressed {
                        DictationAction::None
                    } else {
                        engine.trigger_state.is_pressed = true;
                        if request.is_recording {
                            DictationAction::None
                        } else {
                            DictationAction::StartRecording
                        }
                    }
                }
                InputEvent::TriggerUp => {
                    if engine.trigger_state.is_pressed {
                        engine.trigger_state.is_pressed = false;
                        if request.is_recording {
                            DictationAction::StopRecording
                        } else {
                            DictationAction::None
                        }
                    } else {
                        DictationAction::None
                    }
                }
                InputEvent::TriggerToggle => DictationAction::None,
            },
            TriggerMode::Toggle => match request.event {
                InputEvent::TriggerDown | InputEvent::TriggerToggle => {
                    if request.is_recording {
                        DictationAction::StopRecording
                    } else {
                        DictationAction::StartRecording
                    }
                }
                InputEvent::TriggerUp => DictationAction::None,
            },
            TriggerMode::DoubleTapLock => match request.event {
                InputEvent::TriggerUp => DictationAction::None,
                InputEvent::TriggerDown | InputEvent::TriggerToggle => {
                    if request.is_recording {
                        engine.trigger_state.last_tap_at_ms = None;
                        DictationAction::StopRecording
                    } else if let Some(last_tap) = engine.trigger_state.last_tap_at_ms {
                        if request.timestamp_ms - last_tap <= DOUBLE_TAP_THRESHOLD_MS {
                            engine.trigger_state.last_tap_at_ms = None;
                            DictationAction::StartRecording
                        } else {
                            engine.trigger_state.last_tap_at_ms = Some(request.timestamp_ms);
                            DictationAction::None
                        }
                    } else {
                        engine.trigger_state.last_tap_at_ms = Some(request.timestamp_ms);
                        DictationAction::None
                    }
                }
            },
        };
        Ok(HandleInputEventResponse { action })
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_resolve_style_context(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: ResolveStyleContextRequest| {
        Ok(resolve_style_context(&request.context, &request.settings))
    })
}

#[no_mangle]
pub extern "C" fn verbatim_core_process_transcript(engine: *mut c_void, request_json: *const c_char) -> *mut c_char {
    respond(engine, request_json, |_engine, request: ProcessTranscriptRequest| {
        let decision = request
            .resolved_decision
            .unwrap_or_else(|| match request.context.as_ref() {
                Some(context) => resolve_style_context(context, &request.settings),
                None => default_decision(&request.settings),
            });

        let cleaned = cleanup_text(&request.text);
        let final_text = apply_style(&cleaned, &decision);
        Ok(ProcessTranscriptResponse {
            changed: cleaned != final_text,
            cleaned_text: cleaned,
            final_text: final_text.clone(),
            decision: StyleDecisionReport {
                output_preview: Some(preview(&final_text)),
                ..decision
            },
        })
    })
}

fn respond<Request, Response, F>(engine: *mut c_void, request_json: *const c_char, handler: F) -> *mut c_char
where
    Request: for<'de> Deserialize<'de>,
    Response: Serialize,
    F: FnOnce(&mut Engine, Request) -> Result<Response, String>,
{
    let envelope = (|| {
        if engine.is_null() {
            return ResponseEnvelope::<Response> {
                ok: false,
                value: None,
                error: Some("Engine was null.".to_string()),
            };
        }
        let request_str = unsafe { c_str_to_string(request_json) };
        let request = match serde_json::from_str::<Request>(&request_str) {
            Ok(request) => request,
            Err(error) => {
                return ResponseEnvelope::<Response> {
                    ok: false,
                    value: None,
                    error: Some(format!("Invalid request JSON: {error}")),
                }
            }
        };
        let engine = unsafe { &mut *(engine as *mut Engine) };
        match handler(engine, request) {
            Ok(value) => ResponseEnvelope {
                ok: true,
                value: Some(value),
                error: None,
            },
            Err(error) => ResponseEnvelope {
                ok: false,
                value: None,
                error: Some(error),
            },
        }
    })();

    json_to_ptr(&envelope)
}

unsafe fn c_str_to_string(value: *const c_char) -> String {
    if value.is_null() {
        return String::new();
    }
    CStr::from_ptr(value).to_string_lossy().into_owned()
}

fn json_to_ptr<T: Serialize>(value: &T) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|error| {
        format!("{{\"ok\":false,\"value\":null,\"error\":\"Serialization error: {}\"}}", escape_json(&error.to_string()))
    });
    CString::new(json).unwrap().into_raw()
}

fn escape_json(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn backend_title(backend: &HotkeyBackend) -> String {
    match backend {
        HotkeyBackend::EventMonitor => "Event monitor".to_string(),
        HotkeyBackend::FunctionKeySpecialCase => "Fn / Globe".to_string(),
        HotkeyBackend::Fallback => "Fallback shortcut".to_string(),
        HotkeyBackend::Unavailable => "Unavailable".to_string(),
    }
}

fn provider_capability(
    manifest: &CapabilityManifest,
    provider: &ProviderID,
    profile: &SystemProfile,
    availability: &ProviderAvailability,
    readiness: &ProviderReadiness,
) -> CapabilityStatus {
    if let Some(descriptor) = manifest.providers.iter().find(|descriptor| descriptor.provider == *provider) {
        if !supports_profile(&descriptor.requirements, profile) {
            return CapabilityStatus {
                kind: CapabilityStatusKind::Unsupported,
                reason: Some(descriptor.unsupported_reason.clone()),
                action_title: None,
            };
        }
    } else if availability.is_available && readiness.kind == ProviderReadinessKind::Ready {
        return CapabilityStatus {
            kind: CapabilityStatusKind::Available,
            reason: None,
            action_title: None,
        };
    }

    if !availability.is_available {
        return CapabilityStatus {
            kind: CapabilityStatusKind::SupportedButNotReady,
            reason: Some(
                availability
                    .reason
                    .clone()
                    .unwrap_or_else(|| format!("{} is not ready on this system.", provider_title(provider))),
            ),
            action_title: None,
        };
    }

    if readiness.kind != ProviderReadinessKind::Ready {
        return CapabilityStatus {
            kind: CapabilityStatusKind::SupportedButNotReady,
            reason: Some(readiness.message.clone()),
            action_title: readiness.action_title.clone(),
        };
    }

    CapabilityStatus {
        kind: CapabilityStatusKind::Available,
        reason: None,
        action_title: None,
    }
}

fn feature_capability(
    manifest: &CapabilityManifest,
    feature: &FeatureID,
    profile: &SystemProfile,
) -> CapabilityStatus {
    if let Some(descriptor) = manifest.features.iter().find(|descriptor| descriptor.feature == *feature) {
        if !supports_profile(&descriptor.requirements, profile) {
            return CapabilityStatus {
                kind: CapabilityStatusKind::Unsupported,
                reason: Some(descriptor.unsupported_reason.clone()),
                action_title: None,
            };
        }
    }

    CapabilityStatus {
        kind: CapabilityStatusKind::Available,
        reason: None,
        action_title: None,
    }
}

fn effective_provider(
    stored_provider: &ProviderID,
    capabilities: &HashMap<ProviderID, CapabilityStatus>,
    fallback_order: &[ProviderID],
) -> ProviderID {
    if capabilities
        .get(stored_provider)
        .map(|capability| capability.kind != CapabilityStatusKind::Unsupported)
        .unwrap_or(false)
    {
        return stored_provider.clone();
    }

    if let Some(provider) = fallback_order.iter().find(|provider| {
        capabilities
            .get(*provider)
            .map(|capability| capability.kind == CapabilityStatusKind::Available)
            .unwrap_or(false)
    }) {
        return provider.clone();
    }

    if let Some(provider) = fallback_order.iter().find(|provider| {
        capabilities
            .get(*provider)
            .map(|capability| capability.kind != CapabilityStatusKind::Unsupported)
            .unwrap_or(false)
    }) {
        return provider.clone();
    }

    stored_provider.clone()
}

fn supports_profile(requirement: &CapabilityRequirement, profile: &SystemProfile) -> bool {
    let os_supported = requirement.allowed_os_families.is_empty() || requirement.allowed_os_families.contains(&profile.os_family);
    let architecture_supported =
        requirement.allowed_architectures.is_empty() || requirement.allowed_architectures.contains(&profile.architecture);
    let accelerator_supported =
        requirement.required_accelerators.is_empty() || requirement.required_accelerators.contains(&profile.accelerator);
    os_supported && architecture_supported && accelerator_supported
}

fn provider_title(provider: &ProviderID) -> &'static str {
    match provider {
        ProviderID::AppleSpeech => "Apple Speech",
        ProviderID::Whisper => "Whisper",
        ProviderID::Parakeet => "Parakeet",
    }
}

fn capability_title(kind: &CapabilityStatusKind) -> &'static str {
    match kind {
        CapabilityStatusKind::Available => "Available",
        CapabilityStatusKind::Unsupported => "Unsupported",
        CapabilityStatusKind::SupportedButNotReady => "Needs Setup",
    }
}

fn resolve_selection_response(request: SelectionResolutionRequest) -> SelectionResolutionResponse {
    let effective_provider = effective_provider(
        &request.stored_provider,
        &request.capabilities,
        &request.fallback_order,
    );

    let mut effective_languages = request.preferred_languages.clone();
    if effective_languages.apple_speech_id == "auto" {
        effective_languages.apple_speech_id = request
            .apple_installed_languages
            .first()
            .map(|language| language.identifier.clone())
            .unwrap_or_else(|| "en-US".to_string());
    }

    let effective_provider_message = if effective_provider == request.stored_provider {
        None
    } else {
        let detail = request
            .capabilities
            .get(&request.stored_provider)
            .and_then(|capability| capability.reason.clone())
            .unwrap_or_else(|| format!("{} is unavailable on this system.", provider_title(&request.stored_provider)));
        Some(format!(
            "{} Verbatim will use {} while this preference is unavailable.",
            detail,
            provider_title(&effective_provider)
        ))
    };

    SelectionResolutionResponse {
        effective_provider,
        effective_languages,
        effective_provider_message,
    }
}

fn resolve_provider_model_selection(request: ProviderModelSelectionRequest) -> ProviderModelSelectionResponse {
    let current_language_options = match request.selected_provider {
        ProviderID::Whisper => vec![
            LanguageSelection { identifier: "auto".to_string() },
            LanguageSelection { identifier: "en-US".to_string() },
            LanguageSelection { identifier: "es-ES".to_string() },
            LanguageSelection { identifier: "fr-FR".to_string() },
            LanguageSelection { identifier: "de-DE".to_string() },
            LanguageSelection { identifier: "ja-JP".to_string() },
        ],
        ProviderID::Parakeet => {
            let mut ids = request
                .parakeet_statuses
                .iter()
                .find(|status| status.id == request.selected_parakeet_model_id)
                .map(|status| status.supported_language_ids.clone())
                .unwrap_or_default();
            ids.sort();
            ids.dedup();
            let mut languages = vec![LanguageSelection { identifier: "auto".to_string() }];
            languages.extend(ids.into_iter().map(|identifier| LanguageSelection { identifier }));
            languages
        }
        ProviderID::AppleSpeech => {
            if request.apple_installed_languages.is_empty() {
                vec![
                    LanguageSelection { identifier: "en-US".to_string() },
                    LanguageSelection { identifier: "es-ES".to_string() },
                    LanguageSelection { identifier: "fr-FR".to_string() },
                ]
            } else {
                request.apple_installed_languages.clone()
            }
        }
    };

    let selected_whisper = request
        .whisper_statuses
        .iter()
        .find(|status| status.id == request.selected_whisper_model_id);
    let selected_parakeet = request
        .parakeet_statuses
        .iter()
        .find(|status| status.id == request.selected_parakeet_model_id);

    ProviderModelSelectionResponse {
        current_language_options,
        selected_whisper_description: selected_whisper
            .map(|status| status.name.clone())
            .unwrap_or(request.selected_whisper_model_id),
        selected_whisper_installed: selected_whisper.map(|status| status.is_installed).unwrap_or(false),
        selected_parakeet_description: selected_parakeet
            .map(|status| status.name.clone())
            .unwrap_or(request.selected_parakeet_model_id),
        selected_parakeet_installed: selected_parakeet.map(|status| status.is_installed).unwrap_or(false),
    }
}

fn build_history_sections(request: HistorySectionsRequest) -> Vec<HistorySectionReduction> {
    let trimmed_search = request.search_text.trim().to_lowercase();
    let filtered_items: Vec<HistoryItemReduction> = if trimmed_search.is_empty() {
        request.items
    } else {
        request
            .items
            .into_iter()
            .filter(|item| {
                item.original_text.to_lowercase().contains(&trimmed_search)
                    || item.final_pasted_text.to_lowercase().contains(&trimmed_search)
            })
            .collect()
    };

    let day_ms: i64 = 86_400_000;
    let offset_ms = i64::from(request.utc_offset_seconds) * 1000;
    let today_bucket = bucket_start_ms(request.now_timestamp_ms, day_ms, offset_ms);
    let yesterday_bucket = today_bucket - day_ms;
    let mut grouped: HashMap<i64, Vec<HistoryItemReduction>> = HashMap::new();
    for item in filtered_items {
        grouped
            .entry(bucket_start_ms(item.timestamp_ms, day_ms, offset_ms))
            .or_default()
            .push(item);
    }

    let mut sections = grouped
        .into_iter()
        .map(|(bucket_timestamp_ms, mut items)| {
            items.sort_by(|left, right| right.timestamp_ms.cmp(&left.timestamp_ms));
            let title = if bucket_timestamp_ms == today_bucket {
                "Today".to_string()
            } else if bucket_timestamp_ms == yesterday_bucket {
                "Yesterday".to_string()
            } else {
                format_bucket_title(bucket_timestamp_ms, offset_ms)
            };
            HistorySectionReduction {
                bucket_timestamp_ms,
                title,
                items,
            }
        })
        .collect::<Vec<_>>();
    sections.sort_by(|left, right| right.bucket_timestamp_ms.cmp(&left.bucket_timestamp_ms));
    sections
}

fn reduce_provider_diagnostics(inputs: Vec<ProviderDiagnosticInput>) -> Vec<ProviderDiagnosticReduction> {
    inputs
        .into_iter()
        .map(|input| {
            let last_error = input
                .runtime_error
                .clone()
                .or_else(|| if input.readiness.kind == ProviderReadinessKind::Ready { None } else { Some(input.readiness.message.clone()) })
                .or_else(|| if input.availability.is_available { None } else { input.availability.reason.clone() });
            let runtime_state = input.runtime_state_label.unwrap_or_else(|| "System Managed".to_string());
            let readiness = if input.readiness.kind == ProviderReadinessKind::Ready {
                "Ready".to_string()
            } else {
                input.readiness.message.clone()
            };
            ProviderDiagnosticReduction {
                provider: input.provider.clone(),
                last_error,
                summary_line: format!(
                    "{}: {} • {} • {}",
                    provider_title(&input.provider),
                    capability_title(&input.capability.kind),
                    runtime_state,
                    readiness
                ),
            }
        })
        .collect::<Vec<_>>()
}

fn bucket_start_ms(timestamp_ms: i64, day_ms: i64, offset_ms: i64) -> i64 {
    let shifted = timestamp_ms + offset_ms;
    shifted - shifted.rem_euclid(day_ms) - offset_ms
}

fn format_bucket_title(bucket_timestamp_ms: i64, offset_ms: i64) -> String {
    let (year, month, day) = local_date_parts(bucket_timestamp_ms, offset_ms);
    format!("{} {}, {}", month_abbrev(month), day, year)
}

fn local_date_parts(timestamp_ms: i64, offset_ms: i64) -> (i32, u32, u32) {
    let days = (timestamp_ms + offset_ms).div_euclid(86_400_000);
    civil_from_days(days)
}

fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    let year = y + if m <= 2 { 1 } else { 0 };
    (year as i32, m as u32, d as u32)
}

fn month_abbrev(month: u32) -> &'static str {
    match month {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        _ => "Date",
    }
}

fn resolve_style_context(context: &ActiveAppContext, settings: &StyleSettings) -> StyleDecisionReport {
    let bundle_lower = context.bundle_id.to_lowercase();
    let app_lower = context.app_name.to_lowercase();
    let window_lower = lower_join([context.window_title.as_deref()]);
    let focused_text = lower_join([
        context.focused_element_role.as_deref(),
        context.focused_element_subrole.as_deref(),
        context.focused_element_title.as_deref(),
        context.focused_element_placeholder.as_deref(),
        context.focused_element_description.as_deref(),
        context.focused_value_snippet.as_deref(),
    ]);
    let host_app = is_host_app(&bundle_lower, &app_lower);

    let (category, source, confidence) = if focused_field_looks_like_email(&focused_text) {
        (StyleCategory::Email, StyleDecisionSource::FocusedField, 0.95)
    } else if focused_field_looks_like_work_chat(&focused_text) {
        (StyleCategory::WorkMessages, StyleDecisionSource::FocusedField, 0.92)
    } else if focused_field_looks_like_personal_chat(&focused_text, &bundle_lower, &app_lower) {
        (StyleCategory::PersonalMessages, StyleDecisionSource::FocusedField, 0.9)
    } else if window_looks_like_email(&window_lower, &app_lower) {
        (StyleCategory::Email, StyleDecisionSource::WindowTitle, 0.82)
    } else if window_looks_like_work_chat(&window_lower, &app_lower) {
        (StyleCategory::WorkMessages, StyleDecisionSource::WindowTitle, 0.8)
    } else if window_looks_like_personal_chat(&window_lower, &app_lower) {
        (StyleCategory::PersonalMessages, StyleDecisionSource::WindowTitle, 0.78)
    } else if !host_app {
        (bundle_category(&bundle_lower, &app_lower, &context.style_category), StyleDecisionSource::BundleId, 0.65)
    } else {
        (context.style_category.clone(), StyleDecisionSource::Fallback, 0.4)
    };

    let config = settings.configuration_for(&category);
    StyleDecisionReport {
        preset: config.preset.clone(),
        formatting_enabled: config.enabled,
        category,
        source,
        confidence,
        reason: if config.enabled {
            None
        } else {
            Some("Formatting is disabled for this category.".to_string())
        },
        output_preview: None,
    }
}

fn default_decision(settings: &StyleSettings) -> StyleDecisionReport {
    let config = settings.configuration_for(&StyleCategory::Other);
    StyleDecisionReport {
        category: StyleCategory::Other,
        preset: config.preset.clone(),
        source: StyleDecisionSource::Fallback,
        confidence: 0.4,
        formatting_enabled: config.enabled,
        reason: if config.enabled { None } else { Some("Formatting is disabled for this category.".to_string()) },
        output_preview: None,
    }
}

fn bundle_category(bundle_lower: &str, app_lower: &str, fallback: &StyleCategory) -> StyleCategory {
    let combined = format!("{} {}", bundle_lower, app_lower);
    if contains_any(&combined, &["mail", "outlook", "spark", "hey", "gmail"]) {
        StyleCategory::Email
    } else if contains_any(&combined, &["slack", "teams", "notion", "jira", "linear", "google chat"]) {
        StyleCategory::WorkMessages
    } else if contains_any(&combined, &["messages", "whatsapp", "telegram", "discord"]) {
        StyleCategory::PersonalMessages
    } else {
        fallback.clone()
    }
}

impl StyleSettings {
    fn configuration_for(&self, category: &StyleCategory) -> &StyleCategorySettings {
        match category {
            StyleCategory::PersonalMessages => &self.personal_messages,
            StyleCategory::WorkMessages => &self.work_messages,
            StyleCategory::Email => &self.email,
            StyleCategory::Other => &self.other,
        }
    }
}

fn is_host_app(bundle_lower: &str, app_lower: &str) -> bool {
    contains_any(
        &format!("{} {}", bundle_lower, app_lower),
        &[
            "safari",
            "chrome",
            "arc",
            "firefox",
            "edge",
            "atlas",
            "chatgpt atlas",
        ],
    )
}

fn focused_field_looks_like_email(text: &str) -> bool {
    contains_any(text, &["to", "cc", "bcc", "subject", "compose", "draft", "send"])
}

fn focused_field_looks_like_work_chat(text: &str) -> bool {
    contains_any(text, &["reply", "thread", "channel", "workspace", "team", "comment", "mention"])
}

fn focused_field_looks_like_personal_chat(text: &str, bundle_lower: &str, app_lower: &str) -> bool {
    contains_any(text, &["direct message", "dm", "message", "chat", "reply"]) && contains_any(&format!("{} {}", bundle_lower, app_lower), &["messages", "whatsapp", "telegram", "discord"])
}

fn window_looks_like_email(window_lower: &str, app_lower: &str) -> bool {
    contains_any(&format!("{} {}", window_lower, app_lower), &["gmail", "outlook", "mail", "inbox", "compose", "draft"]) 
}

fn window_looks_like_work_chat(window_lower: &str, app_lower: &str) -> bool {
    contains_any(&format!("{} {}", window_lower, app_lower), &["slack", "teams", "notion", "jira", "linear", "google chat", "channel", "thread", "workspace"]) 
}

fn window_looks_like_personal_chat(window_lower: &str, app_lower: &str) -> bool {
    contains_any(&format!("{} {}", window_lower, app_lower), &["messages", "whatsapp", "telegram", "discord", "dm", "direct message", "chat"]) 
}

fn lower_join<'a, I>(parts: I) -> String
where
    I: IntoIterator<Item = Option<&'a str>>,
{
    parts
        .into_iter()
        .flatten()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn cleanup_text(text: &str) -> String {
    let mut filtered: Vec<String> = Vec::new();
    let tokens: Vec<&str> = text.split_whitespace().collect();
    let mut index = 0;
    while index < tokens.len() {
        let token = tokens[index];
        let normalized = strip_token(token);
        if normalized.eq_ignore_ascii_case("um") || normalized.eq_ignore_ascii_case("uh") {
            index += 1;
            continue;
        }
        if normalized.eq_ignore_ascii_case("you") && index + 1 < tokens.len() {
            let next = strip_token(tokens[index + 1]);
            if next.eq_ignore_ascii_case("know") {
                index += 2;
                continue;
            }
        }
        filtered.push(token.to_string());
        index += 1;
    }
    collapse_spacing(&filtered.join(" "))
}

fn strip_token(token: &str) -> String {
    token
        .trim_matches(|character: char| !character.is_alphanumeric())
        .to_string()
}

fn collapse_spacing(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ").trim().to_string()
}

fn apply_style(text: &str, decision: &StyleDecisionReport) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if !decision.formatting_enabled {
        return trimmed.to_string();
    }
    match decision.preset {
        StylePreset::Formal => formalize(trimmed),
        StylePreset::Casual => casualize(trimmed, decision.category == StyleCategory::Email),
        StylePreset::Enthusiastic => energize(trimmed),
        StylePreset::VeryCasual => make_very_casual(trimmed),
    }
}

fn formalize(text: &str) -> String {
    let capitalized = capitalize_leading_character(text);
    match capitalized.chars().last() {
        Some('.') | Some('!') | Some('?') => capitalized,
        _ => format!("{}.", capitalized),
    }
}

fn casualize(text: &str, preserve_terminal_punctuation: bool) -> String {
    let mut result = capitalize_leading_character(text);
    if preserve_terminal_punctuation {
        return result;
    }
    if result.ends_with('.') {
        result.pop();
    }
    result
}

fn energize(text: &str) -> String {
    let capitalized = capitalize_leading_character(text);
    match capitalized.chars().last() {
        Some('!') => capitalized,
        Some('.') | Some('?') => {
            let mut output = capitalized;
            output.pop();
            format!("{}!", output)
        }
        _ => format!("{}!", capitalized),
    }
}

fn make_very_casual(text: &str) -> String {
    let mut output = text.trim_end_matches(['.', '!']).to_string();
    if let Some(first) = output.chars().next() {
        if first.is_ascii_uppercase() {
            output.replace_range(0..first.len_utf8(), &first.to_ascii_lowercase().to_string());
        }
    }
    output
}

fn capitalize_leading_character(text: &str) -> String {
    let mut chars = text.chars().collect::<Vec<_>>();
    if let Some(index) = chars.iter().position(|character| character.is_alphabetic()) {
        chars[index] = chars[index].to_ascii_uppercase();
    }
    chars.into_iter().collect()
}

fn preview(text: &str) -> String {
    const LIMIT: usize = 140;
    if text.chars().count() <= LIMIT {
        text.to_string()
    } else {
        text.chars().take(LIMIT).collect::<String>() + "…"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_settings() -> StyleSettings {
        StyleSettings {
            personal_messages: StyleCategorySettings { enabled: true, preset: StylePreset::Casual },
            work_messages: StyleCategorySettings { enabled: true, preset: StylePreset::Formal },
            email: StyleCategorySettings { enabled: true, preset: StylePreset::Formal },
            other: StyleCategorySettings { enabled: true, preset: StylePreset::Casual },
        }
    }

    fn make_context() -> ActiveAppContext {
        ActiveAppContext {
            app_name: "Atlas".to_string(),
            bundle_id: "com.openai.atlas".to_string(),
            process_identifier: Some(1),
            style_category: StyleCategory::Other,
            window_title: Some("Compose - Outlook".to_string()),
            focused_element_role: Some("AXTextField".to_string()),
            focused_element_subrole: None,
            focused_element_title: Some("Subject".to_string()),
            focused_element_placeholder: None,
            focused_element_description: None,
            focused_value_snippet: None,
        }
    }

    #[test]
    fn double_tap_lock_starts_on_second_tap() {
        let mut engine = Engine::default();
        engine.trigger_state.mode = TriggerMode::DoubleTapLock;
        let first = HandleInputEventRequest { event: InputEvent::TriggerDown, is_recording: false, timestamp_ms: 1000 };
        let second = HandleInputEventRequest { event: InputEvent::TriggerDown, is_recording: false, timestamp_ms: 1200 };
        let first_response = match engine.trigger_state.mode {
            TriggerMode::DoubleTapLock => {
                engine.trigger_state.last_tap_at_ms = Some(first.timestamp_ms);
                HandleInputEventResponse { action: DictationAction::None }
            }
            _ => unreachable!(),
        };
        assert_eq!(first_response.action, DictationAction::None);
        let second_response = HandleInputEventResponse {
            action: if second.timestamp_ms - engine.trigger_state.last_tap_at_ms.unwrap() <= DOUBLE_TAP_THRESHOLD_MS {
                DictationAction::StartRecording
            } else {
                DictationAction::None
            },
        };
        assert_eq!(second_response.action, DictationAction::StartRecording);
    }

    #[test]
    fn resolves_email_from_focused_field() {
        let decision = resolve_style_context(&make_context(), &make_settings());
        assert_eq!(decision.category, StyleCategory::Email);
        assert_eq!(decision.source, StyleDecisionSource::FocusedField);
    }

    #[test]
    fn applies_conservative_formal_formatting() {
        let response = apply_style(
            &cleanup_text("um hello there"),
            &StyleDecisionReport {
                category: StyleCategory::WorkMessages,
                preset: StylePreset::Formal,
                source: StyleDecisionSource::BundleId,
                confidence: 0.65,
                formatting_enabled: true,
                reason: None,
                output_preview: None,
            },
        );
        assert_eq!(response, "Hello there.");
    }

    #[test]
    fn selection_resolution_falls_back_to_available_provider() {
        let capabilities = HashMap::from([
            (
                ProviderID::AppleSpeech,
                CapabilityStatus {
                    kind: CapabilityStatusKind::Unsupported,
                    reason: Some("Apple Speech is unavailable on this system.".to_string()),
                    action_title: None,
                },
            ),
            (
                ProviderID::Whisper,
                CapabilityStatus {
                    kind: CapabilityStatusKind::Available,
                    reason: None,
                    action_title: None,
                },
            ),
        ]);
        let request = SelectionResolutionRequest {
            stored_provider: ProviderID::AppleSpeech,
            fallback_order: vec![ProviderID::Whisper, ProviderID::Parakeet],
            capabilities,
            preferred_languages: ProviderLanguageSettings {
                apple_speech_id: "auto".to_string(),
                whisper_id: "en-US".to_string(),
                parakeet_id: "auto".to_string(),
            },
            apple_installed_languages: vec![LanguageSelection { identifier: "fr-FR".to_string() }],
        };

        let response = resolve_selection_response(request);

        assert_eq!(response.effective_provider, ProviderID::Whisper);
        assert_eq!(response.effective_languages.apple_speech_id, "fr-FR");
        assert_eq!(
            response.effective_provider_message.as_deref(),
            Some("Apple Speech is unavailable on this system. Verbatim will use Whisper while this preference is unavailable.")
        );
    }

    #[test]
    fn provider_model_selection_uses_model_metadata() {
        let response = resolve_provider_model_selection(ProviderModelSelectionRequest {
            selected_provider: ProviderID::Parakeet,
            selected_whisper_model_id: "base.en".to_string(),
            selected_parakeet_model_id: "parakeet-en".to_string(),
            whisper_statuses: vec![ProviderModelStatusInput {
                id: "base.en".to_string(),
                name: "Whisper Base English".to_string(),
                supported_language_ids: vec!["en-US".to_string()],
                is_installed: true,
            }],
            parakeet_statuses: vec![ProviderModelStatusInput {
                id: "parakeet-en".to_string(),
                name: "Parakeet English".to_string(),
                supported_language_ids: vec!["en-US".to_string(), "es-ES".to_string()],
                is_installed: false,
            }],
            apple_installed_languages: vec![],
        });

        assert_eq!(response.selected_whisper_description, "Whisper Base English");
        assert!(response.selected_whisper_installed);
        assert_eq!(response.selected_parakeet_description, "Parakeet English");
        assert!(!response.selected_parakeet_installed);
        assert_eq!(
            response.current_language_options,
            vec![
                LanguageSelection { identifier: "auto".to_string() },
                LanguageSelection { identifier: "en-US".to_string() },
                LanguageSelection { identifier: "es-ES".to_string() },
            ]
        );
    }

    #[test]
    fn history_sections_group_and_filter_in_local_time() {
        let sections = build_history_sections(HistorySectionsRequest {
            items: vec![
                HistoryItemReduction {
                    id: 1,
                    timestamp_ms: 1_710_000_000_000,
                    provider: "whisper".to_string(),
                    language: "en-US".to_string(),
                    original_text: "First note".to_string(),
                    final_pasted_text: "First note".to_string(),
                    error: None,
                },
                HistoryItemReduction {
                    id: 2,
                    timestamp_ms: 1_710_086_400_000,
                    provider: "whisper".to_string(),
                    language: "en-US".to_string(),
                    original_text: "Second note".to_string(),
                    final_pasted_text: "Second note".to_string(),
                    error: None,
                },
            ],
            search_text: "second".to_string(),
            now_timestamp_ms: 1_710_086_400_000,
            utc_offset_seconds: 0,
        });

        assert_eq!(sections.len(), 1);
        assert_eq!(sections[0].title, "Today");
        assert_eq!(sections[0].items.len(), 1);
        assert_eq!(sections[0].items[0].id, 2);
    }

    #[test]
    fn provider_diagnostic_reducer_prefers_runtime_error() {
        let reductions = reduce_provider_diagnostics(vec![ProviderDiagnosticInput {
            provider: ProviderID::Whisper,
            capability: CapabilityStatus {
                kind: CapabilityStatusKind::SupportedButNotReady,
                reason: Some("Needs a local model.".to_string()),
                action_title: Some("Download model".to_string()),
            },
            availability: ProviderAvailability {
                is_available: true,
                reason: None,
            },
            readiness: ProviderReadiness {
                kind: ProviderReadinessKind::Installable,
                message: "Model can be installed.".to_string(),
                action_title: Some("Install".to_string()),
            },
            runtime_state_label: Some("Failed".to_string()),
            runtime_error: Some("Socket bind failed".to_string()),
        }]);

        assert_eq!(reductions[0].last_error.as_deref(), Some("Socket bind failed"));
        assert!(reductions[0].summary_line.contains("Whisper"));
        assert!(reductions[0].summary_line.contains("Failed"));
    }
}
