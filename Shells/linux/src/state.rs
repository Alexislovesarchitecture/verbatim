use crate::models::{
    AppSettings, DictionaryEntry, FocusContextSnapshot, ModelDescriptor, ModelManifestEnvelope, PermissionStatus,
    ProviderRow, RuntimeSnapshot, ShellSnapshot,
};
use crate::paths::AppPaths;
use cpal::traits::{DeviceTrait, HostTrait};
use rusqlite::Connection;
use std::fs;
use verbatim_core_contract as contract;

pub struct LinuxShellState {
    pub paths: AppPaths,
    pub settings: AppSettings,
    capability_manifest: contract::CapabilityManifest,
    model_manifest: ModelManifestEnvelope,
}

impl LinuxShellState {
    pub fn load() -> Self {
        let paths = AppPaths::current();
        let _ = paths.ensure_directories_exist();
        let settings = load_settings(&paths);
        let capability_manifest: contract::CapabilityManifest = serde_json::from_str(include_str!(
            "../../macOS/Verbatim/Resources/CapabilityManifest.json"
        ))
        .expect("capability manifest must decode");
        let model_manifest: ModelManifestEnvelope = serde_json::from_str(include_str!(
            "../../macOS/Verbatim/Resources/ModelManifest.json"
        ))
        .expect("model manifest must decode");
        ensure_history_schema(&paths);

        Self {
            paths,
            settings,
            capability_manifest,
            model_manifest,
        }
    }

    pub fn set_selected_provider(&mut self, provider: contract::ProviderID) {
        self.settings.selected_provider = provider;
        save_settings(&self.paths, &self.settings);
    }

    pub fn set_language(&mut self, identifier: String) {
        match self.settings.selected_provider {
            contract::ProviderID::AppleSpeech => self.settings.preferred_languages.apple_speech_id = identifier,
            contract::ProviderID::Whisper => self.settings.preferred_languages.whisper_id = identifier,
            contract::ProviderID::Parakeet => self.settings.preferred_languages.parakeet_id = "auto".to_string(),
        }
        self.settings.normalize();
        save_settings(&self.paths, &self.settings);
    }

    pub fn set_model(&mut self, provider: contract::ProviderID, model_id: String) {
        match provider {
            contract::ProviderID::Whisper => self.settings.selected_whisper_model_id = model_id,
            contract::ProviderID::Parakeet => self.settings.selected_parakeet_model_id = model_id,
            contract::ProviderID::AppleSpeech => {}
        }
        self.settings.normalize();
        save_settings(&self.paths, &self.settings);
    }

    pub fn build_snapshot(&self, status_message: Option<&str>) -> ShellSnapshot {
        let permission = microphone_permission();
        let runtime_snapshots = runtime_snapshots(&self.paths);
        let capability_request = contract::CapabilityResolutionRequest {
            manifest: self.capability_manifest.clone(),
            profile: system_profile(),
            stored_provider: self.settings.selected_provider.clone(),
            fallback_order: vec![
                contract::ProviderID::Whisper,
                contract::ProviderID::AppleSpeech,
                contract::ProviderID::Parakeet,
            ],
            availability: availability_map(&permission, &runtime_snapshots),
            readiness: readiness_map(&self.paths, &self.settings, &self.model_manifest, &runtime_snapshots),
        };
        let capability_resolution = contract::resolve_capabilities(capability_request.clone());
        let selection_resolution = contract::resolve_selection_response(contract::SelectionResolutionRequest {
            stored_provider: self.settings.selected_provider.clone(),
            fallback_order: vec![
                contract::ProviderID::Whisper,
                contract::ProviderID::AppleSpeech,
                contract::ProviderID::Parakeet,
            ],
            capabilities: capability_resolution.provider_capabilities.clone(),
            preferred_languages: self.settings.preferred_languages.clone(),
            apple_installed_languages: apple_languages(),
        });
        let model_selection = contract::resolve_provider_model_selection(contract::ProviderModelSelectionRequest {
            selected_provider: self.settings.selected_provider.clone(),
            selected_whisper_model_id: self.settings.selected_whisper_model_id.clone(),
            selected_parakeet_model_id: self.settings.selected_parakeet_model_id.clone(),
            whisper_statuses: model_statuses(&self.paths, &self.model_manifest, contract::ProviderID::Whisper),
            parakeet_statuses: model_statuses(&self.paths, &self.model_manifest, contract::ProviderID::Parakeet),
            apple_installed_languages: apple_languages(),
        });
        let diagnostics = contract::reduce_provider_diagnostics(contract::ProviderDiagnosticsRequest {
            inputs: vec![
                provider_diagnostic_input(
                    contract::ProviderID::AppleSpeech,
                    &capability_resolution,
                    &capability_request,
                    &runtime_snapshots,
                ),
                provider_diagnostic_input(
                    contract::ProviderID::Whisper,
                    &capability_resolution,
                    &capability_request,
                    &runtime_snapshots,
                ),
                provider_diagnostic_input(
                    contract::ProviderID::Parakeet,
                    &capability_resolution,
                    &capability_request,
                    &runtime_snapshots,
                ),
            ],
        });
        let providers = self
            .capability_manifest
            .providers
            .iter()
            .map(|provider| ProviderRow {
                provider: provider.provider.clone(),
                title: provider.title.clone(),
                selected: self.settings.selected_provider == provider.provider,
                effective: selection_resolution.effective_provider == provider.provider,
                capability: capability_resolution
                    .provider_capabilities
                    .get(&provider.provider)
                    .map(|status| status.kind.clone())
                    .map(|kind| match kind {
                        contract::CapabilityStatusKind::Available => "available".to_string(),
                        contract::CapabilityStatusKind::Unsupported => "unsupported".to_string(),
                        contract::CapabilityStatusKind::SupportedButNotReady => "supported but not ready".to_string(),
                    })
                    .unwrap_or_else(|| "unknown".to_string()),
                readiness: capability_request
                    .readiness
                    .get(&provider.provider)
                    .map(|status| status.message.clone())
                    .unwrap_or_else(|| "Unavailable".to_string()),
                language_options: if provider.provider == self.settings.selected_provider {
                    if model_selection.current_language_options.is_empty() {
                        language_options(&provider.provider)
                    } else {
                        model_selection.current_language_options.clone()
                    }
                } else {
                    language_options(&provider.provider)
                },
            })
            .collect::<Vec<_>>();

        let focus = focus_context();
        let tips = vec![
            "Apple Speech remains visible for parity, but it is unsupported on Linux.".to_string(),
            "Whisper auto-detect preserves the spoken language and does not translate.".to_string(),
            if session_kind() == "wayland" {
                "Wayland does not support global hotkeys in this build; clipboard-only workflows remain available.".to_string()
            } else {
                "X11 mode keeps hotkeys, focus capture, and auto-paste available as shell-local features.".to_string()
            },
            "Parakeet remains visible but unsupported on Linux.".to_string(),
        ];

        ShellSnapshot {
            status_message: status_message
                .map(ToOwned::to_owned)
                .or(selection_resolution.effective_provider_message)
                .unwrap_or_else(|| "Linux shell ready.".to_string()),
            settings: self.settings.clone(),
            selected_provider: self.settings.selected_provider.clone(),
            effective_provider: selection_resolution.effective_provider,
            providers,
            current_language_options: if model_selection.current_language_options.is_empty() {
                language_options(&self.settings.selected_provider)
            } else {
                model_selection.current_language_options
            },
            diagnostics,
            history_items: load_history(&self.paths),
            dictionary_entries: load_dictionary(&self.paths),
            runtime_snapshots,
            permission,
            focus_context: focus,
            tips,
        }
    }

    pub fn whisper_models(&self) -> Vec<&ModelDescriptor> {
        self.model_manifest
            .models
            .iter()
            .filter(|model| model.provider == contract::ProviderID::Whisper)
            .collect()
    }

    pub fn parakeet_models(&self) -> Vec<&ModelDescriptor> {
        self.model_manifest
            .models
            .iter()
            .filter(|model| model.provider == contract::ProviderID::Parakeet)
            .collect()
    }
}

fn load_settings(paths: &AppPaths) -> AppSettings {
    let settings = fs::read_to_string(&paths.settings)
        .ok()
        .and_then(|content| serde_json::from_str::<AppSettings>(&content).ok())
        .unwrap_or_default();
    let mut settings = settings;
    settings.normalize();
    save_settings(paths, &settings);
    settings
}

fn save_settings(paths: &AppPaths, settings: &AppSettings) {
    let mut normalized = settings.clone();
    normalized.normalize();
    let _ = fs::write(
        &paths.settings,
        serde_json::to_string_pretty(&normalized).expect("settings should encode"),
    );
}

fn ensure_history_schema(paths: &AppPaths) {
    let connection = Connection::open(&paths.history).expect("history db should open");
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp_ms INTEGER NOT NULL,
                provider TEXT NOT NULL,
                language TEXT NOT NULL,
                original_text TEXT NOT NULL,
                final_pasted_text TEXT NOT NULL,
                error TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS dictionary_entries (
                id TEXT PRIMARY KEY,
                phrase TEXT NOT NULL,
                hint TEXT NOT NULL
            );
            "#,
        )
        .expect("history schema should initialize");
}

fn load_history(paths: &AppPaths) -> Vec<contract::HistoryItemReduction> {
    let connection = Connection::open(&paths.history).expect("history db should open");
    let mut statement = connection
        .prepare(
            "SELECT id, timestamp_ms, provider, language, original_text, final_pasted_text, error
             FROM history
             ORDER BY timestamp_ms DESC
             LIMIT 50",
        )
        .expect("history query should prepare");
    statement
        .query_map([], |row| {
            Ok(contract::HistoryItemReduction {
                id: row.get(0)?,
                timestamp_ms: row.get(1)?,
                provider: row.get(2)?,
                language: row.get(3)?,
                original_text: row.get(4)?,
                final_pasted_text: row.get(5)?,
                error: row.get(6)?,
            })
        })
        .expect("history rows should map")
        .filter_map(Result::ok)
        .collect()
}

fn load_dictionary(paths: &AppPaths) -> Vec<DictionaryEntry> {
    let connection = Connection::open(&paths.history).expect("history db should open");
    let mut statement = connection
        .prepare("SELECT id, phrase, hint FROM dictionary_entries ORDER BY phrase COLLATE NOCASE ASC")
        .expect("dictionary query should prepare");
    statement
        .query_map([], |row| {
            Ok(DictionaryEntry {
                id: row.get(0)?,
                phrase: row.get(1)?,
                hint: row.get(2)?,
            })
        })
        .expect("dictionary rows should map")
        .filter_map(Result::ok)
        .collect()
}

fn microphone_permission() -> PermissionStatus {
    let host = cpal::default_host();
    match host.default_input_device() {
        Some(device) => PermissionStatus {
            is_granted: true,
            message: format!("Microphone capture is available through {}.", device.name().unwrap_or_else(|_| "the default input device".to_string())),
        },
        None => PermissionStatus {
            is_granted: false,
            message: "No input device is currently available.".to_string(),
        },
    }
}

fn session_kind() -> String {
    std::env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "x11".to_string()).to_lowercase()
}

fn focus_context() -> FocusContextSnapshot {
    let note = if session_kind() == "wayland" {
        "Focus capture unavailable without X11/AT-SPI support; copied output remains available.".to_string()
    } else {
        "X11 session detected. Focus and auto-paste adapters can activate in this shell build.".to_string()
    };
    FocusContextSnapshot {
        app_name: std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_else(|_| "Linux desktop".to_string()),
        window_title: std::env::var("WINDOW_TITLE").ok(),
        note,
    }
}

fn runtime_snapshots(paths: &AppPaths) -> Vec<RuntimeSnapshot> {
    vec![
        RuntimeSnapshot {
            provider: contract::ProviderID::Whisper,
            binary_name: "whisper-server-linux-x64".to_string(),
            binary_present: paths.runtime.join("whisper-server-linux-x64").exists(),
            state: if paths.runtime.join("whisper-server-linux-x64").exists() {
                "stopped".to_string()
            } else {
                "missing".to_string()
            },
            endpoint: Some("http://127.0.0.1:8178".to_string()),
            last_error: if paths.runtime.join("whisper-server-linux-x64").exists() {
                None
            } else {
                Some("whisper-server-linux-x64 is not staged in Verbatim Runtime.".to_string())
            },
        },
        RuntimeSnapshot {
            provider: contract::ProviderID::Parakeet,
            binary_name: "sherpa-onnx-ws-linux-x64".to_string(),
            binary_present: paths.runtime.join("sherpa-onnx-ws-linux-x64").exists(),
            state: "unsupported".to_string(),
            endpoint: Some("ws://127.0.0.1:6006".to_string()),
            last_error: Some("Parakeet remains unsupported on Linux in this build.".to_string()),
        },
    ]
}

fn system_profile() -> contract::SystemProfile {
    contract::SystemProfile {
        os_family: contract::OperatingSystemFamily::Linux,
        os_version: contract::SystemVersionInfo {
            major: 0,
            minor: 0,
            patch: 0,
        },
        architecture: if std::env::consts::ARCH == "aarch64" {
            contract::CPUArchitecture::Arm64
        } else {
            contract::CPUArchitecture::X86_64
        },
        accelerator: contract::AcceleratorClass::None,
    }
}

fn availability_map(
    permission: &PermissionStatus,
    runtime_snapshots: &[RuntimeSnapshot],
) -> std::collections::HashMap<contract::ProviderID, contract::ProviderAvailability> {
    let whisper_binary = runtime_snapshots
        .iter()
        .find(|snapshot| snapshot.provider == contract::ProviderID::Whisper)
        .map(|snapshot| snapshot.binary_present)
        .unwrap_or(false);
    std::collections::HashMap::from([
        (
            contract::ProviderID::AppleSpeech,
            contract::ProviderAvailability {
                is_available: false,
                reason: Some("Apple Speech is not available on Linux.".to_string()),
            },
        ),
        (
            contract::ProviderID::Whisper,
            contract::ProviderAvailability {
                is_available: permission.is_granted && whisper_binary,
                reason: if permission.is_granted {
                    if whisper_binary {
                        None
                    } else {
                        Some("whisper-server-linux-x64 is not staged in Verbatim Runtime.".to_string())
                    }
                } else {
                    Some(permission.message.clone())
                },
            },
        ),
        (
            contract::ProviderID::Parakeet,
            contract::ProviderAvailability {
                is_available: false,
                reason: Some("Parakeet currently requires Windows with an NVIDIA CUDA-compatible system.".to_string()),
            },
        ),
    ])
}

fn readiness_map(
    paths: &AppPaths,
    settings: &AppSettings,
    manifest: &ModelManifestEnvelope,
    runtime_snapshots: &[RuntimeSnapshot],
) -> std::collections::HashMap<contract::ProviderID, contract::ProviderReadiness> {
    let whisper_binary = runtime_snapshots
        .iter()
        .find(|snapshot| snapshot.provider == contract::ProviderID::Whisper)
        .map(|snapshot| snapshot.binary_present)
        .unwrap_or(false);
    let whisper_model_ready = manifest.models.iter().any(|model| {
        model.provider == contract::ProviderID::Whisper
            && model.id == settings.selected_whisper_model_id
            && model_installed(paths, model)
    });
    std::collections::HashMap::from([
        (
            contract::ProviderID::AppleSpeech,
            contract::ProviderReadiness {
                kind: contract::ProviderReadinessKind::Unavailable,
                message: "Apple Speech is only available on Apple Silicon Macs.".to_string(),
                action_title: None,
            },
        ),
        (
            contract::ProviderID::Whisper,
            if !whisper_binary {
                contract::ProviderReadiness {
                    kind: contract::ProviderReadinessKind::Unavailable,
                    message: "whisper-server-linux-x64 is missing from the runtime bundle.".to_string(),
                    action_title: None,
                }
            } else if !whisper_model_ready {
                contract::ProviderReadiness {
                    kind: contract::ProviderReadinessKind::Installable,
                    message: "Download the selected Whisper model first.".to_string(),
                    action_title: Some("Download".to_string()),
                }
            } else {
                contract::ProviderReadiness {
                    kind: contract::ProviderReadinessKind::Ready,
                    message: "Whisper is ready. Runtime will launch when you start transcription.".to_string(),
                    action_title: None,
                }
            },
        ),
        (
            contract::ProviderID::Parakeet,
            contract::ProviderReadiness {
                kind: contract::ProviderReadinessKind::Unavailable,
                message: "Parakeet remains unsupported on Linux in this build.".to_string(),
                action_title: None,
            },
        ),
    ])
}

fn model_statuses(
    paths: &AppPaths,
    manifest: &ModelManifestEnvelope,
    provider: contract::ProviderID,
) -> Vec<contract::ProviderModelStatusInput> {
    manifest
        .models
        .iter()
        .filter(|model| model.provider == provider)
        .map(|model| contract::ProviderModelStatusInput {
            id: model.id.clone(),
            name: model.name.clone(),
            supported_language_ids: model.supported_language_ids.clone(),
            is_installed: model_installed(paths, model),
        })
        .collect()
}

fn model_installed(paths: &AppPaths, model: &ModelDescriptor) -> bool {
    match model.provider {
        contract::ProviderID::Parakeet => paths
            .parakeet_models
            .join(model.extract_directory.as_deref().unwrap_or(&model.id))
            .exists(),
        _ => paths
            .whisper_models
            .join(model.file_name.as_deref().unwrap_or(&model.id))
            .exists(),
    }
}

fn apple_languages() -> Vec<contract::LanguageSelection> {
    vec![
        contract::LanguageSelection {
            identifier: "en-US".to_string(),
        },
        contract::LanguageSelection {
            identifier: "es-ES".to_string(),
        },
        contract::LanguageSelection {
            identifier: "pt-BR".to_string(),
        },
        contract::LanguageSelection {
            identifier: "ru-RU".to_string(),
        },
    ]
}

fn language_options(provider: &contract::ProviderID) -> Vec<contract::LanguageSelection> {
    match provider {
        contract::ProviderID::AppleSpeech => apple_languages(),
        contract::ProviderID::Parakeet => vec![auto_language()],
        contract::ProviderID::Whisper => vec![
            auto_language(),
            contract::LanguageSelection {
                identifier: "en".to_string(),
            },
            contract::LanguageSelection {
                identifier: "es".to_string(),
            },
            contract::LanguageSelection {
                identifier: "pt".to_string(),
            },
            contract::LanguageSelection {
                identifier: "ru".to_string(),
            },
        ],
    }
}

fn auto_language() -> contract::LanguageSelection {
    contract::LanguageSelection {
        identifier: "auto".to_string(),
    }
}

fn provider_diagnostic_input(
    provider: contract::ProviderID,
    capability_resolution: &contract::CapabilityResolutionResponse,
    capability_request: &contract::CapabilityResolutionRequest,
    runtime_snapshots: &[RuntimeSnapshot],
) -> contract::ProviderDiagnosticInput {
    let runtime = runtime_snapshots.iter().find(|snapshot| snapshot.provider == provider);
    contract::ProviderDiagnosticInput {
        provider: provider.clone(),
        capability: capability_resolution
            .provider_capabilities
            .get(&provider)
            .cloned()
            .unwrap_or(contract::CapabilityStatus {
                kind: contract::CapabilityStatusKind::Unsupported,
                reason: Some("Unavailable".to_string()),
                action_title: None,
            }),
        availability: capability_request
            .availability
            .get(&provider)
            .cloned()
            .unwrap_or(contract::ProviderAvailability {
                is_available: false,
                reason: Some("Unavailable".to_string()),
            }),
        readiness: capability_request
            .readiness
            .get(&provider)
            .cloned()
            .unwrap_or(contract::ProviderReadiness {
                kind: contract::ProviderReadinessKind::Unavailable,
                message: "Unavailable".to_string(),
                action_title: None,
            }),
        runtime_state_label: runtime.map(|snapshot| snapshot.state.clone()),
        runtime_error: runtime.and_then(|snapshot| snapshot.last_error.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linux_defaults_keep_provider_specific_language_rules() {
        let mut settings = AppSettings::default();
        settings.preferred_languages.apple_speech_id = "auto".to_string();
        settings.preferred_languages.parakeet_id = "ru".to_string();
        settings.normalize();

        assert_eq!(settings.preferred_languages.apple_speech_id, "en-US");
        assert_eq!(settings.preferred_languages.whisper_id, "auto");
        assert_eq!(settings.preferred_languages.parakeet_id, "auto");
    }

    #[test]
    fn linux_shell_keeps_parakeet_unavailable() {
        let state = LinuxShellState::load();
        let snapshot = state.build_snapshot(None);
        let parakeet = snapshot
            .providers
            .iter()
            .find(|provider| provider.provider == contract::ProviderID::Parakeet)
            .expect("parakeet provider row should exist");

        assert!(parakeet.readiness.contains("unsupported") || parakeet.readiness.contains("requires Windows"));
    }
}
