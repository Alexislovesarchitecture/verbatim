use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub const DOUBLE_TAP_THRESHOLD_MS: i64 = 350;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TriggerEngine {
    trigger_state: TriggerState,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct TriggerState {
    mode: TriggerMode,
    is_pressed: bool,
    last_tap_at_ms: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct EmptyResponse {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum ProviderID {
    AppleSpeech,
    Whisper,
    Parakeet,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StyleCategory {
    PersonalMessages,
    WorkMessages,
    Email,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StylePreset {
    Formal,
    Casual,
    Enthusiastic,
    VeryCasual,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StyleDecisionSource {
    FocusedField,
    WindowTitle,
    BundleId,
    Fallback,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum TriggerMode {
    #[default]
    Hold,
    Toggle,
    DoubleTapLock,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum HotkeyBackend {
    EventMonitor,
    FunctionKeySpecialCase,
    Fallback,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OperatingSystemFamily {
    Macos,
    Windows,
    Linux,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CPUArchitecture {
    Arm64,
    X86_64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AcceleratorClass {
    None,
    AppleSilicon,
    NvidiaCuda,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SystemVersionInfo {
    pub major: i32,
    pub minor: i32,
    pub patch: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SystemProfile {
    pub os_family: OperatingSystemFamily,
    pub os_version: SystemVersionInfo,
    pub architecture: CPUArchitecture,
    pub accelerator: AcceleratorClass,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityRequirement {
    pub allowed_os_families: Vec<OperatingSystemFamily>,
    pub allowed_architectures: Vec<CPUArchitecture>,
    pub required_accelerators: Vec<AcceleratorClass>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityStatusKind {
    Available,
    Unsupported,
    SupportedButNotReady,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityStatus {
    pub kind: CapabilityStatusKind,
    pub reason: Option<String>,
    pub action_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderCapabilityDescriptor {
    pub provider: ProviderID,
    pub title: String,
    pub requirements: CapabilityRequirement,
    pub unsupported_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum FeatureID {
    ProviderSelection,
    AutoPaste,
    HotkeyCapture,
    ModelManagement,
    AppleSpeechAssets,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FeatureCapabilityDescriptor {
    pub feature: FeatureID,
    pub title: String,
    pub requirements: CapabilityRequirement,
    pub unsupported_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityManifest {
    pub providers: Vec<ProviderCapabilityDescriptor>,
    pub features: Vec<FeatureCapabilityDescriptor>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderAvailability {
    pub is_available: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderReadinessKind {
    Ready,
    Installable,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderReadiness {
    pub kind: ProviderReadinessKind,
    pub message: String,
    pub action_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityResolutionRequest {
    pub manifest: CapabilityManifest,
    pub profile: SystemProfile,
    pub stored_provider: ProviderID,
    pub fallback_order: Vec<ProviderID>,
    pub availability: HashMap<ProviderID, ProviderAvailability>,
    pub readiness: HashMap<ProviderID, ProviderReadiness>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityResolutionResponse {
    pub provider_capabilities: HashMap<ProviderID, CapabilityStatus>,
    pub feature_capabilities: HashMap<FeatureID, CapabilityStatus>,
    pub effective_provider: ProviderID,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LanguageSelection {
    pub identifier: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderLanguageSettings {
    pub apple_speech_id: String,
    pub whisper_id: String,
    pub parakeet_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SelectionResolutionRequest {
    pub stored_provider: ProviderID,
    pub fallback_order: Vec<ProviderID>,
    pub capabilities: HashMap<ProviderID, CapabilityStatus>,
    pub preferred_languages: ProviderLanguageSettings,
    pub apple_installed_languages: Vec<LanguageSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SelectionResolutionResponse {
    pub effective_provider: ProviderID,
    pub effective_languages: ProviderLanguageSettings,
    pub effective_provider_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderModelStatusInput {
    pub id: String,
    pub name: String,
    pub supported_language_ids: Vec<String>,
    pub is_installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderModelSelectionRequest {
    pub selected_provider: ProviderID,
    pub selected_whisper_model_id: String,
    pub selected_parakeet_model_id: String,
    pub whisper_statuses: Vec<ProviderModelStatusInput>,
    pub parakeet_statuses: Vec<ProviderModelStatusInput>,
    pub apple_installed_languages: Vec<LanguageSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderModelSelectionResponse {
    pub current_language_options: Vec<LanguageSelection>,
    pub selected_whisper_description: String,
    pub selected_whisper_installed: bool,
    pub selected_parakeet_description: String,
    pub selected_parakeet_installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryItemReduction {
    pub id: i64,
    pub timestamp_ms: i64,
    pub provider: String,
    pub language: String,
    pub original_text: String,
    pub final_pasted_text: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HistorySectionReduction {
    pub bucket_timestamp_ms: i64,
    pub title: String,
    pub items: Vec<HistoryItemReduction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HistorySectionsRequest {
    pub items: Vec<HistoryItemReduction>,
    pub search_text: String,
    pub now_timestamp_ms: i64,
    pub utc_offset_seconds: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDiagnosticInput {
    pub provider: ProviderID,
    pub capability: CapabilityStatus,
    pub availability: ProviderAvailability,
    pub readiness: ProviderReadiness,
    pub runtime_state_label: Option<String>,
    pub runtime_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDiagnosticReduction {
    pub provider: ProviderID,
    pub last_error: Option<String>,
    pub summary_line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDiagnosticsRequest {
    pub inputs: Vec<ProviderDiagnosticInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum InputEvent {
    TriggerDown,
    TriggerUp,
    TriggerToggle,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DictationAction {
    None,
    StartRecording,
    StopRecording,
    CancelRecording,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyStartResultPayload {
    pub backend: HotkeyBackend,
    pub effective_trigger_label: String,
    pub original_trigger_label: String,
    pub fallback_was_used: bool,
    pub message: Option<String>,
    pub recommended_fallback_label: Option<String>,
    pub permission_granted: bool,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PrepareTriggerRequest {
    pub mode: TriggerMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SummarizeTriggerStateRequest {
    pub mode: TriggerMode,
    pub start_result: HotkeyStartResultPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SummarizeTriggerStateResponse {
    pub status_message: String,
    pub effective_trigger_label: String,
    pub backend_label: String,
    pub fallback_reason: Option<String>,
    pub is_available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HandleInputEventRequest {
    pub event: InputEvent,
    pub is_recording: bool,
    pub timestamp_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HandleInputEventResponse {
    pub action: DictationAction,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StyleCategorySettings {
    pub enabled: bool,
    pub preset: StylePreset,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StyleSettings {
    pub personal_messages: StyleCategorySettings,
    pub work_messages: StyleCategorySettings,
    pub email: StyleCategorySettings,
    pub other: StyleCategorySettings,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ActiveAppContext {
    pub app_name: String,
    pub bundle_id: String,
    pub process_identifier: Option<i32>,
    pub style_category: StyleCategory,
    pub window_title: Option<String>,
    pub focused_element_role: Option<String>,
    pub focused_element_subrole: Option<String>,
    pub focused_element_title: Option<String>,
    pub focused_element_placeholder: Option<String>,
    pub focused_element_description: Option<String>,
    pub focused_value_snippet: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ResolveStyleContextRequest {
    pub context: ActiveAppContext,
    pub settings: StyleSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StyleDecisionReport {
    pub category: StyleCategory,
    pub preset: StylePreset,
    pub source: StyleDecisionSource,
    pub confidence: f64,
    pub formatting_enabled: bool,
    pub reason: Option<String>,
    pub output_preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DictionaryEntryInput {
    pub phrase: String,
    pub hint: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessTranscriptRequest {
    pub text: String,
    pub context: Option<ActiveAppContext>,
    pub settings: StyleSettings,
    pub resolved_decision: Option<StyleDecisionReport>,
    pub dictionary_entries: Vec<DictionaryEntryInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessTranscriptResponse {
    pub cleaned_text: String,
    pub final_text: String,
    pub changed: bool,
    pub decision: StyleDecisionReport,
}

impl TriggerEngine {
    pub fn prepare_trigger(&mut self, mode: TriggerMode) {
        self.trigger_state.mode = mode;
        self.trigger_state.is_pressed = false;
        self.trigger_state.last_tap_at_ms = None;
    }

    pub fn summarize_trigger_state(
        &mut self,
        request: SummarizeTriggerStateRequest,
    ) -> SummarizeTriggerStateResponse {
        self.prepare_trigger(request.mode);
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
            result.message
        } else {
            None
        };
        SummarizeTriggerStateResponse {
            effective_trigger_label: result.effective_trigger_label,
            status_message,
            backend_label: backend_title(&result.backend),
            fallback_reason,
            is_available: result.is_active,
        }
    }

    pub fn handle_input_event(
        &mut self,
        request: HandleInputEventRequest,
    ) -> HandleInputEventResponse {
        let action = match self.trigger_state.mode {
            TriggerMode::Hold => match request.event {
                InputEvent::TriggerDown => {
                    if self.trigger_state.is_pressed {
                        DictationAction::None
                    } else {
                        self.trigger_state.is_pressed = true;
                        if request.is_recording {
                            DictationAction::None
                        } else {
                            DictationAction::StartRecording
                        }
                    }
                }
                InputEvent::TriggerUp => {
                    if self.trigger_state.is_pressed {
                        self.trigger_state.is_pressed = false;
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
                        self.trigger_state.last_tap_at_ms = None;
                        DictationAction::StopRecording
                    } else if let Some(last_tap) = self.trigger_state.last_tap_at_ms {
                        if request.timestamp_ms - last_tap <= DOUBLE_TAP_THRESHOLD_MS {
                            self.trigger_state.last_tap_at_ms = None;
                            DictationAction::StartRecording
                        } else {
                            self.trigger_state.last_tap_at_ms = Some(request.timestamp_ms);
                            DictationAction::None
                        }
                    } else {
                        self.trigger_state.last_tap_at_ms = Some(request.timestamp_ms);
                        DictationAction::None
                    }
                }
            },
        };
        HandleInputEventResponse { action }
    }
}

pub fn resolve_capabilities(request: CapabilityResolutionRequest) -> CapabilityResolutionResponse {
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

    CapabilityResolutionResponse {
        effective_provider: effective_provider(
            &request.stored_provider,
            &provider_capabilities,
            &request.fallback_order,
        ),
        provider_capabilities,
        feature_capabilities,
    }
}

pub fn normalize_provider_languages(settings: &ProviderLanguageSettings) -> ProviderLanguageSettings {
    ProviderLanguageSettings {
        apple_speech_id: normalize_language_identifier(&ProviderID::AppleSpeech, &settings.apple_speech_id),
        whisper_id: normalize_language_identifier(&ProviderID::Whisper, &settings.whisper_id),
        parakeet_id: normalize_language_identifier(&ProviderID::Parakeet, &settings.parakeet_id),
    }
}

pub fn resolve_selection_response(request: SelectionResolutionRequest) -> SelectionResolutionResponse {
    let effective_provider = effective_provider(
        &request.stored_provider,
        &request.capabilities,
        &request.fallback_order,
    );

    let effective_languages = normalize_provider_languages(&request.preferred_languages);

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

pub fn resolve_provider_model_selection(
    request: ProviderModelSelectionRequest,
) -> ProviderModelSelectionResponse {
    let current_language_options = match request.selected_provider {
        ProviderID::Whisper => vec![
            LanguageSelection { identifier: "auto".to_string() },
            LanguageSelection { identifier: "en-US".to_string() },
            LanguageSelection { identifier: "es-ES".to_string() },
            LanguageSelection { identifier: "pt-BR".to_string() },
            LanguageSelection { identifier: "ru-RU".to_string() },
            LanguageSelection { identifier: "fr-FR".to_string() },
            LanguageSelection { identifier: "de-DE".to_string() },
            LanguageSelection { identifier: "ja-JP".to_string() },
        ],
        ProviderID::Parakeet => vec![LanguageSelection { identifier: "auto".to_string() }],
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

pub fn build_history_sections(request: HistorySectionsRequest) -> Vec<HistorySectionReduction> {
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

pub fn reduce_provider_diagnostics(
    request: ProviderDiagnosticsRequest,
) -> Vec<ProviderDiagnosticReduction> {
    request
        .inputs
        .into_iter()
        .map(|input| {
            let last_error = input
                .runtime_error
                .clone()
                .or_else(|| {
                    if input.readiness.kind == ProviderReadinessKind::Ready {
                        None
                    } else {
                        Some(input.readiness.message.clone())
                    }
                })
                .or_else(|| {
                    if input.availability.is_available {
                        None
                    } else {
                        input.availability.reason.clone()
                    }
                });
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

pub fn backend_title(backend: &HotkeyBackend) -> String {
    match backend {
        HotkeyBackend::EventMonitor => "Event monitor".to_string(),
        HotkeyBackend::FunctionKeySpecialCase => "Fn / Globe".to_string(),
        HotkeyBackend::Fallback => "Fallback shortcut".to_string(),
        HotkeyBackend::Unavailable => "Unavailable".to_string(),
    }
}

pub fn resolve_style_context(
    context: &ActiveAppContext,
    settings: &StyleSettings,
) -> StyleDecisionReport {
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
        (
            bundle_category(&bundle_lower, &app_lower, &context.style_category),
            StyleDecisionSource::BundleId,
            0.65,
        )
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

pub fn default_decision(settings: &StyleSettings) -> StyleDecisionReport {
    let config = settings.configuration_for(&StyleCategory::Other);
    StyleDecisionReport {
        category: StyleCategory::Other,
        preset: config.preset.clone(),
        source: StyleDecisionSource::Fallback,
        confidence: 0.4,
        formatting_enabled: config.enabled,
        reason: if config.enabled {
            None
        } else {
            Some("Formatting is disabled for this category.".to_string())
        },
        output_preview: None,
    }
}

pub fn process_transcript(request: ProcessTranscriptRequest) -> ProcessTranscriptResponse {
    let decision = request
        .resolved_decision
        .unwrap_or_else(|| match request.context.as_ref() {
            Some(context) => resolve_style_context(context, &request.settings),
            None => default_decision(&request.settings),
        });

    let cleaned = cleanup_text(&request.text);
    let corrected = apply_dictionary_entries(&cleaned, &request.dictionary_entries);
    let final_text = apply_style(&corrected, &decision);
    ProcessTranscriptResponse {
        changed: cleaned != corrected || corrected != final_text,
        cleaned_text: corrected,
        final_text: final_text.clone(),
        decision: StyleDecisionReport {
            output_preview: Some(preview(&final_text)),
            ..decision
        },
    }
}

impl StyleSettings {
    pub fn configuration_for(&self, category: &StyleCategory) -> &StyleCategorySettings {
        match category {
            StyleCategory::PersonalMessages => &self.personal_messages,
            StyleCategory::WorkMessages => &self.work_messages,
            StyleCategory::Email => &self.email,
            StyleCategory::Other => &self.other,
        }
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
    let os_supported =
        requirement.allowed_os_families.is_empty() || requirement.allowed_os_families.contains(&profile.os_family);
    let architecture_supported = requirement.allowed_architectures.is_empty()
        || requirement.allowed_architectures.contains(&profile.architecture);
    let accelerator_supported = requirement.required_accelerators.is_empty()
        || requirement.required_accelerators.contains(&profile.accelerator);
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

fn normalize_language_identifier(provider: &ProviderID, identifier: &str) -> String {
    let trimmed = identifier.trim();
    match provider {
        ProviderID::AppleSpeech => {
            if trimmed.is_empty() || trimmed == "auto" {
                "en-US".to_string()
            } else {
                trimmed.to_string()
            }
        }
        ProviderID::Whisper => {
            if trimmed.is_empty() {
                "auto".to_string()
            } else {
                trimmed.to_string()
            }
        }
        ProviderID::Parakeet => "auto".to_string(),
    }
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

fn is_host_app(bundle_lower: &str, app_lower: &str) -> bool {
    contains_any(
        &format!("{} {}", bundle_lower, app_lower),
        &["safari", "chrome", "arc", "firefox", "edge", "atlas", "chatgpt atlas"],
    )
}

fn focused_field_looks_like_email(text: &str) -> bool {
    contains_any(text, &["to", "cc", "bcc", "subject", "compose", "draft", "send"])
}

fn focused_field_looks_like_work_chat(text: &str) -> bool {
    contains_any(text, &["reply", "thread", "channel", "workspace", "team", "comment", "mention"])
}

fn focused_field_looks_like_personal_chat(text: &str, bundle_lower: &str, app_lower: &str) -> bool {
    contains_any(text, &["direct message", "dm", "message", "chat", "reply"])
        && contains_any(
            &format!("{} {}", bundle_lower, app_lower),
            &["messages", "whatsapp", "telegram", "discord"],
        )
}

fn window_looks_like_email(window_lower: &str, app_lower: &str) -> bool {
    contains_any(
        &format!("{} {}", window_lower, app_lower),
        &["gmail", "outlook", "mail", "inbox", "compose", "draft"],
    )
}

fn window_looks_like_work_chat(window_lower: &str, app_lower: &str) -> bool {
    contains_any(
        &format!("{} {}", window_lower, app_lower),
        &[
            "slack",
            "teams",
            "notion",
            "jira",
            "linear",
            "google chat",
            "channel",
            "thread",
            "workspace",
        ],
    )
}

fn window_looks_like_personal_chat(window_lower: &str, app_lower: &str) -> bool {
    contains_any(
        &format!("{} {}", window_lower, app_lower),
        &["messages", "whatsapp", "telegram", "discord", "dm", "direct message", "chat"],
    )
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

#[derive(Clone)]
struct DictionaryMatcher {
    canonical_phrase: String,
    canonical_normalized: String,
    hint_normalized: String,
    canonical_letters: String,
    hint_letters: String,
    canonical_token_count: usize,
    hint_token_count: usize,
}

#[derive(Clone)]
struct DictionaryReplacementCandidate {
    start: usize,
    end: usize,
    score: f64,
    replacement: String,
}

fn apply_dictionary_entries(text: &str, entries: &[DictionaryEntryInput]) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() || entries.is_empty() {
        return trimmed.to_string();
    }

    let tokens: Vec<&str> = trimmed.split_whitespace().collect();
    if tokens.is_empty() {
        return String::new();
    }

    let matchers = entries
        .iter()
        .filter_map(dictionary_matcher)
        .collect::<Vec<_>>();
    if matchers.is_empty() {
        return trimmed.to_string();
    }

    let max_span = matchers
        .iter()
        .map(|matcher| {
            matcher
                .canonical_token_count
                .max(matcher.hint_token_count)
                .max(matcher.canonical_letters.chars().count())
                .max(matcher.hint_letters.chars().count())
        })
        .max()
        .unwrap_or(1);

    let mut candidates = Vec::new();
    for start in 0..tokens.len() {
        let mut end = start;
        while end < tokens.len() && end < start + max_span {
            let span_tokens = &tokens[start..=end];
            if let Some(candidate) = best_dictionary_candidate(span_tokens, start, end, &matchers) {
                candidates.push(candidate);
            }
            end += 1;
        }
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.start.cmp(&right.start))
            .then_with(|| left.end.cmp(&right.end))
    });

    let mut accepted = Vec::new();
    for candidate in candidates {
        if accepted
            .iter()
            .any(|existing: &DictionaryReplacementCandidate| spans_overlap(existing, &candidate))
        {
            continue;
        }
        accepted.push(candidate);
    }
    accepted.sort_by_key(|candidate| candidate.start);

    let mut output = Vec::new();
    let mut token_index = 0;
    let mut replacement_index = 0;
    while token_index < tokens.len() {
        if replacement_index < accepted.len() && accepted[replacement_index].start == token_index {
            output.push(accepted[replacement_index].replacement.clone());
            token_index = accepted[replacement_index].end + 1;
            replacement_index += 1;
        } else {
            output.push(tokens[token_index].to_string());
            token_index += 1;
        }
    }

    collapse_spacing(&output.join(" "))
}

fn dictionary_matcher(entry: &DictionaryEntryInput) -> Option<DictionaryMatcher> {
    let canonical_phrase = collapse_spacing(entry.phrase.trim());
    if canonical_phrase.is_empty() {
        return None;
    }
    let spoken_hint = if entry.hint.trim().is_empty() {
        canonical_phrase.clone()
    } else {
        collapse_spacing(entry.hint.trim())
    };
    let canonical_normalized = normalize_phrase(&canonical_phrase);
    let hint_normalized = normalize_phrase(&spoken_hint);
    if canonical_normalized.is_empty() {
        return None;
    }
    Some(DictionaryMatcher {
        canonical_token_count: normalized_token_count(&canonical_normalized),
        hint_token_count: normalized_token_count(&hint_normalized),
        canonical_letters: letters_only(&canonical_phrase),
        hint_letters: letters_only(&spoken_hint),
        canonical_phrase,
        canonical_normalized,
        hint_normalized,
    })
}

fn best_dictionary_candidate(
    span_tokens: &[&str],
    start: usize,
    end: usize,
    matchers: &[DictionaryMatcher],
) -> Option<DictionaryReplacementCandidate> {
    let span_text = span_tokens.join(" ");
    let span_normalized = normalize_phrase(&span_text);
    if span_normalized.is_empty() {
        return None;
    }

    let span_token_count = normalized_token_count(&span_normalized);
    let spelled_letters = collapse_spelled_sequence(&span_text);
    let mut scored = Vec::new();

    for matcher in matchers {
        if span_token_count == matcher.canonical_token_count {
            if span_normalized == matcher.canonical_normalized {
                scored.push((matcher.canonical_phrase.clone(), 1.0));
            } else if let Some(score) = fuzzy_similarity(&span_normalized, &matcher.canonical_normalized) {
                let threshold = if span_token_count <= 1 { 0.8 } else { 0.88 };
                if score >= threshold {
                    scored.push((matcher.canonical_phrase.clone(), score));
                }
            }
        }

        if span_token_count == matcher.hint_token_count {
            if span_normalized == matcher.hint_normalized {
                scored.push((matcher.canonical_phrase.clone(), 1.0));
            } else if matcher.hint_normalized != matcher.canonical_normalized {
                if let Some(score) = fuzzy_similarity(&span_normalized, &matcher.hint_normalized) {
                    let threshold = if span_token_count <= 1 { 0.8 } else { 0.88 };
                    if score >= threshold {
                        scored.push((matcher.canonical_phrase.clone(), score));
                    }
                }
            }
        }

        if let Some(ref spelled_letters) = spelled_letters {
            if !matcher.canonical_letters.is_empty() && *spelled_letters == matcher.canonical_letters {
                scored.push((matcher.canonical_phrase.clone(), 0.99));
            } else if !matcher.hint_letters.is_empty() && *spelled_letters == matcher.hint_letters {
                scored.push((matcher.canonical_phrase.clone(), 0.99));
            }
        }
    }

    if scored.is_empty() {
        return None;
    }

    let mut deduped = Vec::<(String, f64)>::new();
    for (replacement, score) in scored {
        if let Some(existing) = deduped.iter_mut().find(|(value, _)| *value == replacement) {
            if score > existing.1 {
                existing.1 = score;
            }
        } else {
            deduped.push((replacement, score));
        }
    }
    deduped.sort_by(|left, right| {
        right
            .1
            .partial_cmp(&left.1)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let (replacement, best_score) = deduped[0].clone();
    if deduped
        .get(1)
        .map(|(_, score)| (best_score - score).abs() <= 0.03)
        .unwrap_or(false)
    {
        return None;
    }

    Some(DictionaryReplacementCandidate {
        start,
        end,
        score: best_score,
        replacement: replacement_with_punctuation(span_tokens, &replacement),
    })
}

fn spans_overlap(left: &DictionaryReplacementCandidate, right: &DictionaryReplacementCandidate) -> bool {
    left.start <= right.end && right.start <= left.end
}

fn replacement_with_punctuation(span_tokens: &[&str], replacement: &str) -> String {
    let prefix = span_tokens
        .first()
        .map(|token| leading_punctuation(token))
        .unwrap_or_default();
    let suffix = span_tokens
        .last()
        .map(|token| trailing_punctuation(token))
        .unwrap_or_default();
    format!("{}{}{}", prefix, replacement, suffix)
}

fn leading_punctuation(token: &str) -> String {
    token
        .chars()
        .take_while(|character| !character.is_alphanumeric())
        .collect()
}

fn trailing_punctuation(token: &str) -> String {
    token
        .chars()
        .rev()
        .take_while(|character| !character.is_alphanumeric())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect()
}

fn normalize_phrase(text: &str) -> String {
    let mut normalized = String::new();
    let mut last_was_space = true;
    for character in text.chars() {
        if character.is_alphanumeric() {
            normalized.push(character.to_ascii_lowercase());
            last_was_space = false;
        } else if character.is_whitespace() && !last_was_space {
            normalized.push(' ');
            last_was_space = true;
        }
    }
    normalized.trim().to_string()
}

fn normalized_token_count(text: &str) -> usize {
    text.split_whitespace().count()
}

fn letters_only(text: &str) -> String {
    text.chars()
        .filter(|character| character.is_alphanumeric())
        .map(|character| character.to_ascii_lowercase())
        .collect()
}

fn collapse_spelled_sequence(text: &str) -> Option<String> {
    let tokens = text.split_whitespace().collect::<Vec<_>>();
    if tokens.is_empty() {
        return None;
    }

    let mut letters = String::new();
    let mut sequence_like = tokens.len() > 1;
    for token in tokens {
        let trimmed = token.trim_matches(|character: char| !character.is_alphanumeric() && character != '-' && character != '.');
        if trimmed.is_empty() {
            return None;
        }

        if trimmed.contains('-') || trimmed.contains('.') {
            let parts = trimmed
                .split(|character| character == '-' || character == '.')
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>();
            if parts.len() < 2 {
                return None;
            }
            sequence_like = true;
            for part in parts {
                let mut chars = part.chars();
                let character = chars.next()?;
                if chars.next().is_some() || !character.is_alphabetic() {
                    return None;
                }
                letters.push(character.to_ascii_lowercase());
            }
        } else {
            let mut chars = trimmed.chars();
            let character = chars.next()?;
            if chars.next().is_some() || !character.is_alphabetic() {
                return None;
            }
            letters.push(character.to_ascii_lowercase());
        }
    }

    if sequence_like && letters.len() >= 2 {
        Some(letters)
    } else {
        None
    }
}

fn fuzzy_similarity(left: &str, right: &str) -> Option<f64> {
    if left.is_empty() || right.is_empty() {
        return None;
    }
    let distance = levenshtein_distance(left, right) as f64;
    let max_len = left.chars().count().max(right.chars().count()) as f64;
    Some((1.0 - (distance / max_len)).max(0.0))
}

fn levenshtein_distance(left: &str, right: &str) -> usize {
    let left_chars = left.chars().collect::<Vec<_>>();
    let right_chars = right.chars().collect::<Vec<_>>();
    let mut previous = (0..=right_chars.len()).collect::<Vec<_>>();
    let mut current = vec![0; right_chars.len() + 1];

    for (left_index, left_char) in left_chars.iter().enumerate() {
        current[0] = left_index + 1;
        for (right_index, right_char) in right_chars.iter().enumerate() {
            let substitution_cost = if left_char == right_char { 0 } else { 1 };
            current[right_index + 1] = (current[right_index] + 1)
                .min(previous[right_index + 1] + 1)
                .min(previous[right_index] + substitution_cost);
        }
        previous.clone_from(&current);
    }

    previous[right_chars.len()]
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

    fn assert_round_trip<T>(value: &T)
    where
        T: Serialize + for<'de> Deserialize<'de> + PartialEq + std::fmt::Debug,
    {
        let encoded = serde_json::to_string(value).unwrap();
        let decoded: T = serde_json::from_str(&encoded).unwrap();
        assert_eq!(decoded, *value);
    }

    #[test]
    fn contract_payloads_round_trip_through_json() {
        let manifest = CapabilityManifest {
            providers: vec![ProviderCapabilityDescriptor {
                provider: ProviderID::Whisper,
                title: "Whisper".to_string(),
                requirements: CapabilityRequirement {
                    allowed_os_families: vec![OperatingSystemFamily::Macos, OperatingSystemFamily::Windows, OperatingSystemFamily::Linux],
                    allowed_architectures: vec![],
                    required_accelerators: vec![],
                },
                unsupported_reason: "Unsupported".to_string(),
            }],
            features: vec![FeatureCapabilityDescriptor {
                feature: FeatureID::ModelManagement,
                title: "Model Management".to_string(),
                requirements: CapabilityRequirement {
                    allowed_os_families: vec![OperatingSystemFamily::Macos, OperatingSystemFamily::Windows, OperatingSystemFamily::Linux],
                    allowed_architectures: vec![],
                    required_accelerators: vec![],
                },
                unsupported_reason: "Unsupported".to_string(),
            }],
        };
        let profile = SystemProfile {
            os_family: OperatingSystemFamily::Linux,
            os_version: SystemVersionInfo { major: 1, minor: 2, patch: 3 },
            architecture: CPUArchitecture::X86_64,
            accelerator: AcceleratorClass::None,
        };
        let capability_request = CapabilityResolutionRequest {
            manifest: manifest.clone(),
            profile: profile.clone(),
            stored_provider: ProviderID::Whisper,
            fallback_order: vec![ProviderID::Whisper],
            availability: HashMap::from([(
                ProviderID::Whisper,
                ProviderAvailability { is_available: true, reason: None },
            )]),
            readiness: HashMap::from([(
                ProviderID::Whisper,
                ProviderReadiness {
                    kind: ProviderReadinessKind::Ready,
                    message: "Ready".to_string(),
                    action_title: None,
                },
            )]),
        };
        assert_round_trip(&capability_request);
        assert_round_trip(&resolve_capabilities(capability_request));

        let selection_request = SelectionResolutionRequest {
            stored_provider: ProviderID::AppleSpeech,
            fallback_order: vec![ProviderID::Whisper, ProviderID::Parakeet],
            capabilities: HashMap::from([
                (
                    ProviderID::AppleSpeech,
                    CapabilityStatus {
                        kind: CapabilityStatusKind::Unsupported,
                        reason: Some("Apple Speech unavailable.".to_string()),
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
            ]),
            preferred_languages: ProviderLanguageSettings {
                apple_speech_id: "auto".to_string(),
                whisper_id: "auto".to_string(),
                parakeet_id: "es-ES".to_string(),
            },
            apple_installed_languages: vec![LanguageSelection { identifier: "en-US".to_string() }],
        };
        assert_round_trip(&selection_request);
        assert_round_trip(&resolve_selection_response(selection_request));

        let model_request = ProviderModelSelectionRequest {
            selected_provider: ProviderID::Whisper,
            selected_whisper_model_id: "base".to_string(),
            selected_parakeet_model_id: "parakeet".to_string(),
            whisper_statuses: vec![ProviderModelStatusInput {
                id: "base".to_string(),
                name: "Whisper Base".to_string(),
                supported_language_ids: vec!["en-US".to_string()],
                is_installed: true,
            }],
            parakeet_statuses: vec![],
            apple_installed_languages: vec![],
        };
        assert_round_trip(&model_request);
        assert_round_trip(&resolve_provider_model_selection(model_request));

        let history_request = HistorySectionsRequest {
            items: vec![HistoryItemReduction {
                id: 1,
                timestamp_ms: 1_710_086_400_000,
                provider: "whisper".to_string(),
                language: "en-US".to_string(),
                original_text: "Second note".to_string(),
                final_pasted_text: "Second note".to_string(),
                error: None,
            }],
            search_text: String::new(),
            now_timestamp_ms: 1_710_086_400_000,
            utc_offset_seconds: 0,
        };
        assert_round_trip(&history_request);
        assert_round_trip(&build_history_sections(history_request).first().unwrap().clone());

        let diagnostics_request = ProviderDiagnosticsRequest {
            inputs: vec![ProviderDiagnosticInput {
                provider: ProviderID::Whisper,
                capability: CapabilityStatus {
                    kind: CapabilityStatusKind::SupportedButNotReady,
                    reason: Some("Needs setup".to_string()),
                    action_title: Some("Install".to_string()),
                },
                availability: ProviderAvailability { is_available: true, reason: None },
                readiness: ProviderReadiness {
                    kind: ProviderReadinessKind::Installable,
                    message: "Installable".to_string(),
                    action_title: Some("Install".to_string()),
                },
                runtime_state_label: Some("Idle".to_string()),
                runtime_error: None,
            }],
        };
        assert_round_trip(&diagnostics_request);
        assert_round_trip(&reduce_provider_diagnostics(diagnostics_request).first().unwrap().clone());

        let summarize_request = SummarizeTriggerStateRequest {
            mode: TriggerMode::Hold,
            start_result: HotkeyStartResultPayload {
                backend: HotkeyBackend::EventMonitor,
                effective_trigger_label: "Fn".to_string(),
                original_trigger_label: "Fn".to_string(),
                fallback_was_used: false,
                message: None,
                recommended_fallback_label: None,
                permission_granted: true,
                is_active: true,
            },
        };
        assert_round_trip(&summarize_request);
        let mut engine = TriggerEngine::default();
        assert_round_trip(&engine.summarize_trigger_state(summarize_request));

        let input_request = HandleInputEventRequest {
            event: InputEvent::TriggerDown,
            is_recording: false,
            timestamp_ms: 1000,
        };
        assert_round_trip(&input_request);
        assert_round_trip(&engine.handle_input_event(input_request));

        let style_request = ResolveStyleContextRequest {
            context: make_context(),
            settings: make_settings(),
        };
        assert_round_trip(&style_request);
        assert_round_trip(&resolve_style_context(&style_request.context, &style_request.settings));

        let transcript_request = ProcessTranscriptRequest {
            text: "um hello there".to_string(),
            context: Some(make_context()),
            settings: make_settings(),
            resolved_decision: None,
            dictionary_entries: vec![],
        };
        assert_round_trip(&transcript_request);
        assert_round_trip(&process_transcript(transcript_request));

        assert_round_trip(&PrepareTriggerRequest { mode: TriggerMode::Toggle });
        assert_round_trip(&EmptyResponse::default());
    }

    #[test]
    fn double_tap_lock_starts_on_second_tap() {
        let mut engine = TriggerEngine::default();
        engine.prepare_trigger(TriggerMode::DoubleTapLock);

        let first = engine.handle_input_event(HandleInputEventRequest {
            event: InputEvent::TriggerDown,
            is_recording: false,
            timestamp_ms: 1000,
        });
        let second = engine.handle_input_event(HandleInputEventRequest {
            event: InputEvent::TriggerDown,
            is_recording: false,
            timestamp_ms: 1200,
        });

        assert_eq!(first.action, DictationAction::None);
        assert_eq!(second.action, DictationAction::StartRecording);
    }

    #[test]
    fn resolves_email_from_focused_field() {
        let decision = resolve_style_context(&make_context(), &make_settings());
        assert_eq!(decision.category, StyleCategory::Email);
        assert_eq!(decision.source, StyleDecisionSource::FocusedField);
    }

    #[test]
    fn applies_conservative_formal_formatting() {
        let response = process_transcript(ProcessTranscriptRequest {
            text: "um hello there".to_string(),
            context: Some(ActiveAppContext {
                app_name: "Slack".to_string(),
                bundle_id: "com.tinyspeck.slackmacgap".to_string(),
                process_identifier: Some(7),
                style_category: StyleCategory::WorkMessages,
                window_title: Some("Team thread".to_string()),
                focused_element_role: Some("AXTextField".to_string()),
                focused_element_subrole: None,
                focused_element_title: Some("Reply".to_string()),
                focused_element_placeholder: None,
                focused_element_description: None,
                focused_value_snippet: None,
            }),
            settings: make_settings(),
            resolved_decision: Some(StyleDecisionReport {
                category: StyleCategory::WorkMessages,
                preset: StylePreset::Formal,
                source: StyleDecisionSource::BundleId,
                confidence: 0.65,
                formatting_enabled: true,
                reason: None,
                output_preview: None,
            }),
            dictionary_entries: vec![],
        });
        assert_eq!(response.cleaned_text, "hello there");
        assert_eq!(response.final_text, "Hello there.");
    }

    #[test]
    fn dictionary_rewrites_spoken_forms_before_styling() {
        let response = process_transcript(ProcessTranscriptRequest {
            text: "betty is here with me".to_string(),
            context: None,
            settings: make_settings(),
            resolved_decision: Some(StyleDecisionReport {
                category: StyleCategory::Other,
                preset: StylePreset::Casual,
                source: StyleDecisionSource::Fallback,
                confidence: 0.4,
                formatting_enabled: true,
                reason: None,
                output_preview: None,
            }),
            dictionary_entries: vec![DictionaryEntryInput {
                phrase: "Batty".to_string(),
                hint: "betty".to_string(),
            }],
        });

        assert_eq!(response.cleaned_text, "Batty is here with me");
        assert_eq!(response.final_text, "Batty is here with me");
    }

    #[test]
    fn dictionary_rewrites_spelled_sequences_to_canonical_phrase() {
        let response = process_transcript(ProcessTranscriptRequest {
            text: "B-A-T-T-Y is listening".to_string(),
            context: None,
            settings: make_settings(),
            resolved_decision: Some(StyleDecisionReport {
                category: StyleCategory::Other,
                preset: StylePreset::Casual,
                source: StyleDecisionSource::Fallback,
                confidence: 0.4,
                formatting_enabled: true,
                reason: None,
                output_preview: None,
            }),
            dictionary_entries: vec![DictionaryEntryInput {
                phrase: "Batty".to_string(),
                hint: String::new(),
            }],
        });

        assert_eq!(response.cleaned_text, "Batty is listening");
        assert_eq!(response.final_text, "Batty is listening");
    }

    #[test]
    fn dictionary_leaves_ambiguous_candidates_unchanged() {
        let response = process_transcript(ProcessTranscriptRequest {
            text: "katy is here".to_string(),
            context: None,
            settings: make_settings(),
            resolved_decision: Some(StyleDecisionReport {
                category: StyleCategory::Other,
                preset: StylePreset::Casual,
                source: StyleDecisionSource::Fallback,
                confidence: 0.4,
                formatting_enabled: true,
                reason: None,
                output_preview: None,
            }),
            dictionary_entries: vec![
                DictionaryEntryInput {
                    phrase: "Katy".to_string(),
                    hint: "katy".to_string(),
                },
                DictionaryEntryInput {
                    phrase: "Katie".to_string(),
                    hint: "katy".to_string(),
                },
            ],
        });

        assert_eq!(response.cleaned_text, "katy is here");
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
                parakeet_id: "ru-RU".to_string(),
            },
            apple_installed_languages: vec![LanguageSelection { identifier: "fr-FR".to_string() }],
        };

        let response = resolve_selection_response(request);

        assert_eq!(response.effective_provider, ProviderID::Whisper);
        assert_eq!(response.effective_languages.apple_speech_id, "en-US");
        assert_eq!(response.effective_languages.parakeet_id, "auto");
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
        assert_eq!(response.current_language_options, vec![LanguageSelection { identifier: "auto".to_string() }]);
    }

    #[test]
    fn provider_model_selection_apple_languages_exclude_auto() {
        let response = resolve_provider_model_selection(ProviderModelSelectionRequest {
            selected_provider: ProviderID::AppleSpeech,
            selected_whisper_model_id: "base".to_string(),
            selected_parakeet_model_id: "parakeet".to_string(),
            whisper_statuses: vec![],
            parakeet_statuses: vec![],
            apple_installed_languages: vec![LanguageSelection { identifier: "en-US".to_string() }],
        });

        assert_eq!(response.current_language_options, vec![LanguageSelection { identifier: "en-US".to_string() }]);
    }

    #[test]
    fn provider_model_selection_whisper_languages_include_auto_and_multilingual_options() {
        let response = resolve_provider_model_selection(ProviderModelSelectionRequest {
            selected_provider: ProviderID::Whisper,
            selected_whisper_model_id: "base".to_string(),
            selected_parakeet_model_id: "parakeet".to_string(),
            whisper_statuses: vec![],
            parakeet_statuses: vec![],
            apple_installed_languages: vec![],
        });

        assert!(response.current_language_options.contains(&LanguageSelection { identifier: "auto".to_string() }));
        assert!(response.current_language_options.contains(&LanguageSelection { identifier: "pt-BR".to_string() }));
        assert!(response.current_language_options.contains(&LanguageSelection { identifier: "ru-RU".to_string() }));
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
        let reductions = reduce_provider_diagnostics(ProviderDiagnosticsRequest {
            inputs: vec![ProviderDiagnosticInput {
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
            }],
        });

        assert_eq!(reductions[0].last_error.as_deref(), Some("Socket bind failed"));
        assert!(reductions[0].summary_line.contains("Whisper"));
        assert!(reductions[0].summary_line.contains("Failed"));
    }
}
