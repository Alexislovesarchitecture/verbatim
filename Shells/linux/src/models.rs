use serde::{Deserialize, Serialize};
use verbatim_core_contract as contract;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub selected_provider: contract::ProviderID,
    pub preferred_languages: contract::ProviderLanguageSettings,
    pub selected_whisper_model_id: String,
    pub selected_parakeet_model_id: String,
    pub paste_mode: String,
    pub onboarding_completed: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            selected_provider: contract::ProviderID::Whisper,
            preferred_languages: contract::ProviderLanguageSettings {
                apple_speech_id: "en-US".to_string(),
                whisper_id: "auto".to_string(),
                parakeet_id: "auto".to_string(),
            },
            selected_whisper_model_id: "base".to_string(),
            selected_parakeet_model_id: "parakeet-tdt-0.6b-v3".to_string(),
            paste_mode: "auto_paste".to_string(),
            onboarding_completed: false,
        }
    }
}

impl AppSettings {
    pub fn normalize(&mut self) {
        if self.preferred_languages.apple_speech_id.trim().is_empty()
            || self.preferred_languages.apple_speech_id == "auto"
        {
            self.preferred_languages.apple_speech_id = "en-US".to_string();
        }

        if self.preferred_languages.whisper_id.trim().is_empty() {
            self.preferred_languages.whisper_id = "auto".to_string();
        }

        self.preferred_languages.parakeet_id = "auto".to_string();
        if self.selected_whisper_model_id.trim().is_empty() {
            self.selected_whisper_model_id = "base".to_string();
        }
        if self.selected_parakeet_model_id.trim().is_empty() {
            self.selected_parakeet_model_id = "parakeet-tdt-0.6b-v3".to_string();
        }
        if self.paste_mode != "clipboard_only" {
            self.paste_mode = "auto_paste".to_string();
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelDescriptor {
    pub id: String,
    pub provider: contract::ProviderID,
    pub name: String,
    pub detail: String,
    pub size_label: String,
    pub download_url: Option<String>,
    pub expected_size_bytes: Option<i64>,
    pub file_name: Option<String>,
    pub extract_directory: Option<String>,
    pub supported_language_ids: Vec<String>,
    pub recommended: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelManifestEnvelope {
    pub models: Vec<ModelDescriptor>,
}

#[derive(Debug, Clone)]
pub struct DictionaryEntry {
    pub id: String,
    pub phrase: String,
    pub hint: String,
}

#[derive(Debug, Clone)]
pub struct PermissionStatus {
    pub is_granted: bool,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct RuntimeSnapshot {
    pub provider: contract::ProviderID,
    pub binary_name: String,
    pub binary_present: bool,
    pub state: String,
    pub endpoint: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FocusContextSnapshot {
    pub app_name: String,
    pub window_title: Option<String>,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct ProviderRow {
    pub provider: contract::ProviderID,
    pub title: String,
    pub selected: bool,
    pub effective: bool,
    pub capability: String,
    pub readiness: String,
    pub language_options: Vec<contract::LanguageSelection>,
}

#[derive(Debug, Clone)]
pub struct ShellSnapshot {
    pub status_message: String,
    pub settings: AppSettings,
    pub selected_provider: contract::ProviderID,
    pub effective_provider: contract::ProviderID,
    pub providers: Vec<ProviderRow>,
    pub current_language_options: Vec<contract::LanguageSelection>,
    pub diagnostics: Vec<contract::ProviderDiagnosticReduction>,
    pub history_items: Vec<contract::HistoryItemReduction>,
    pub dictionary_entries: Vec<DictionaryEntry>,
    pub runtime_snapshots: Vec<RuntimeSnapshot>,
    pub permission: PermissionStatus,
    pub focus_context: FocusContextSnapshot,
    pub tips: Vec<String>,
}

pub fn language_title(identifier: &str) -> String {
    match identifier {
        "auto" => "Auto-detect".to_string(),
        "en" => "English".to_string(),
        "en-US" => "English (United States)".to_string(),
        "es" => "Spanish".to_string(),
        "es-ES" => "Spanish (Spain)".to_string(),
        "pt" => "Portuguese".to_string(),
        "pt-BR" => "Portuguese (Brazil)".to_string(),
        "ru" => "Russian".to_string(),
        "ru-RU" => "Russian (Russia)".to_string(),
        other => other.to_string(),
    }
}

pub fn provider_title(provider: &contract::ProviderID) -> &'static str {
    match provider {
        contract::ProviderID::AppleSpeech => "Apple Speech",
        contract::ProviderID::Whisper => "Whisper",
        contract::ProviderID::Parakeet => "Parakeet",
    }
}
