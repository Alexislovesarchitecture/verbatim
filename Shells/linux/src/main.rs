mod models;
mod paths;
mod state;

use adw::prelude::*;
use gtk::prelude::*;
use models::{language_title, provider_title};
use state::LinuxShellState;
use std::cell::RefCell;
use std::rc::Rc;
use verbatim_core_contract as contract;

fn main() {
    adw::init().expect("libadwaita initialization failed");

    let app = adw::Application::builder()
        .application_id("dev.verbatim.linux")
        .build();

    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &adw::Application) {
    let state = Rc::new(RefCell::new(LinuxShellState::load()));

    let status_label = gtk::Label::new(None);
    status_label.set_wrap(true);
    status_label.set_xalign(0.0);

    let provider_combo = gtk::ComboBoxText::new();
    let language_combo = gtk::ComboBoxText::new();
    let whisper_combo = gtk::ComboBoxText::new();
    let parakeet_combo = gtk::ComboBoxText::new();
    let provider_list = gtk::ListBox::new();
    let runtime_list = gtk::ListBox::new();
    let diagnostics_list = gtk::ListBox::new();
    let history_list = gtk::ListBox::new();
    let dictionary_list = gtk::ListBox::new();
    let tips_list = gtk::ListBox::new();
    let permission_label = gtk::Label::new(None);
    permission_label.set_wrap(true);
    permission_label.set_xalign(0.0);
    let focus_label = gtk::Label::new(None);
    focus_label.set_wrap(true);
    focus_label.set_xalign(0.0);
    let paths_label = gtk::Label::new(None);
    paths_label.set_wrap(true);
    paths_label.set_xalign(0.0);

    let widgets = Rc::new(Widgets {
        status_label,
        provider_combo,
        language_combo,
        whisper_combo,
        parakeet_combo,
        provider_list,
        runtime_list,
        diagnostics_list,
        history_list,
        dictionary_list,
        tips_list,
        permission_label,
        focus_label,
        paths_label,
    });

    {
        let widgets = widgets.clone();
        let state = state.clone();
        widgets.provider_combo.connect_changed(move |combo| {
            if let Some(id) = combo.active_id() {
                let provider = match id.as_str() {
                    "apple_speech" => contract::ProviderID::AppleSpeech,
                    "parakeet" => contract::ProviderID::Parakeet,
                    _ => contract::ProviderID::Whisper,
                };
                state.borrow_mut().set_selected_provider(provider);
                render(&state.borrow(), &widgets, Some("Updated preferred provider."));
            }
        });
    }

    {
        let widgets = widgets.clone();
        let state = state.clone();
        widgets.language_combo.connect_changed(move |combo| {
            if let Some(id) = combo.active_id() {
                state.borrow_mut().set_language(id.to_string());
                render(&state.borrow(), &widgets, Some("Updated language preference."));
            }
        });
    }

    {
        let widgets = widgets.clone();
        let state = state.clone();
        widgets.whisper_combo.connect_changed(move |combo| {
            if let Some(id) = combo.active_id() {
                state
                    .borrow_mut()
                    .set_model(contract::ProviderID::Whisper, id.to_string());
                render(&state.borrow(), &widgets, Some("Updated Whisper model selection."));
            }
        });
    }

    {
        let widgets = widgets.clone();
        let state = state.clone();
        widgets.parakeet_combo.connect_changed(move |combo| {
            if let Some(id) = combo.active_id() {
                state
                    .borrow_mut()
                    .set_model(contract::ProviderID::Parakeet, id.to_string());
                render(&state.borrow(), &widgets, Some("Updated Parakeet model selection."));
            }
        });
    }

    let left_column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    left_column.append(&section_title("Provider and Language"));
    left_column.append(&widgets.provider_combo);
    left_column.append(&widgets.language_combo);
    left_column.append(&widgets.permission_label);
    left_column.append(&widgets.focus_label);

    let middle_column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    middle_column.append(&section_title("Models and Runtime"));
    middle_column.append(&widgets.whisper_combo);
    middle_column.append(&widgets.parakeet_combo);
    middle_column.append(&widgets.provider_list);
    middle_column.append(&widgets.runtime_list);

    let right_column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    right_column.append(&section_title("Diagnostics and Tips"));
    right_column.append(&widgets.diagnostics_list);
    right_column.append(&widgets.tips_list);

    let lower_left = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    lower_left.append(&section_title("History"));
    lower_left.append(&widgets.paths_label);
    lower_left.append(&widgets.history_list);

    let lower_middle = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    lower_middle.append(&section_title("Dictionary"));
    lower_middle.append(&widgets.dictionary_list);

    let lower_right = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .build();
    lower_right.append(&section_title("Product Notes"));
    lower_right.append(&gtk::Label::new(Some(
        "Linux is a first-class Verbatim shell. X11 remains the automation-capable target, while Wayland stays explicit about hotkey, focus, and auto-paste limits in this build.",
    )));
    lower_right.append(&gtk::Label::new(Some(
        "Provider rules remain unchanged: Apple Speech is visible but unsupported, Whisper stays cross-platform and transcription-only, and Parakeet remains visible but gated off on Linux.",
    )));

    let grid = gtk::Grid::builder()
        .column_spacing(18)
        .row_spacing(18)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(24)
        .margin_end(24)
        .build();
    grid.attach(&header(&widgets.status_label), 0, 0, 3, 1);
    grid.attach(&card(&left_column), 0, 1, 1, 1);
    grid.attach(&card(&middle_column), 1, 1, 1, 1);
    grid.attach(&card(&right_column), 2, 1, 1, 1);
    grid.attach(&card(&lower_left), 0, 2, 1, 1);
    grid.attach(&card(&lower_middle), 1, 2, 1, 1);
    grid.attach(&card(&lower_right), 2, 2, 1, 1);

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Verbatim")
        .default_width(1320)
        .default_height(920)
        .content(&gtk::ScrolledWindow::builder().child(&grid).build())
        .build();

    render(&state.borrow(), &widgets, None);
    window.present();
}

struct Widgets {
    status_label: gtk::Label,
    provider_combo: gtk::ComboBoxText,
    language_combo: gtk::ComboBoxText,
    whisper_combo: gtk::ComboBoxText,
    parakeet_combo: gtk::ComboBoxText,
    provider_list: gtk::ListBox,
    runtime_list: gtk::ListBox,
    diagnostics_list: gtk::ListBox,
    history_list: gtk::ListBox,
    dictionary_list: gtk::ListBox,
    tips_list: gtk::ListBox,
    permission_label: gtk::Label,
    focus_label: gtk::Label,
    paths_label: gtk::Label,
}

fn render(state: &LinuxShellState, widgets: &Widgets, status_override: Option<&str>) {
    let snapshot = state.build_snapshot(status_override);
    widgets.status_label.set_text(&snapshot.status_message);
    widgets.permission_label.set_text(&format!(
        "Selected provider: {} | Active on this system: {}\n{}",
        provider_title(&snapshot.selected_provider),
        provider_title(&snapshot.effective_provider),
        snapshot.permission.message
    ));
    widgets.focus_label.set_text(&format!(
        "{}\nWindow: {}\n{}",
        snapshot.focus_context.app_name,
        snapshot.focus_context.window_title.unwrap_or_else(|| "Unavailable".to_string()),
        snapshot.focus_context.note
    ));
    widgets.paths_label.set_text(&format!(
        "Settings: {}\nHistory: {}\nModels: {}\nRuntime: {}",
        state.paths.settings.display(),
        state.paths.history.display(),
        state.paths.models.display(),
        state.paths.runtime.display()
    ));

    refill_combo(
        &widgets.provider_combo,
        snapshot.providers.iter().map(|provider| {
            (
                provider_identifier(&provider.provider).to_string(),
                format!("{} ({})", provider.title, provider.readiness),
            )
        }),
        Some(provider_identifier(&snapshot.selected_provider).to_string()),
    );
    refill_combo(
        &widgets.language_combo,
        snapshot
            .current_language_options
            .iter()
            .map(|language| (language.identifier.clone(), language_title(&language.identifier))),
        Some(match snapshot.selected_provider {
            contract::ProviderID::AppleSpeech => snapshot.settings.preferred_languages.apple_speech_id.clone(),
            contract::ProviderID::Whisper => snapshot.settings.preferred_languages.whisper_id.clone(),
            contract::ProviderID::Parakeet => snapshot.settings.preferred_languages.parakeet_id.clone(),
        }),
    );
    refill_combo(
        &widgets.whisper_combo,
        state
            .whisper_models()
            .into_iter()
            .map(|model| (model.id.clone(), format!("{} - {} ({})", model.name, model.detail, model.size_label))),
        Some(snapshot.settings.selected_whisper_model_id.clone()),
    );
    refill_combo(
        &widgets.parakeet_combo,
        state.parakeet_models().into_iter().map(|model| {
            (
                model.id.clone(),
                format!("{} - {} ({})", model.name, model.detail, model.size_label),
            )
        }),
        Some(snapshot.settings.selected_parakeet_model_id.clone()),
    );

    refill_list(
        &widgets.provider_list,
        snapshot.providers.iter().map(|provider| {
            format!(
                "{}\nSelection: {} | Activation: {}\nCapability: {}\nReadiness: {}",
                provider.title,
                if provider.selected { "selected" } else { "visible" },
                if provider.effective { "active" } else { "fallback/blocked" },
                provider.capability,
                provider.readiness
            )
        }),
    );
    refill_list(
        &widgets.runtime_list,
        snapshot.runtime_snapshots.iter().map(|runtime| {
            format!(
                "{} runtime\nBinary: {}\nPresent: {}\nState: {}\nEndpoint: {}\nLast error: {}",
                provider_title(&runtime.provider),
                runtime.binary_name,
                runtime.binary_present,
                runtime.state,
                runtime.endpoint.clone().unwrap_or_else(|| "n/a".to_string()),
                runtime
                    .last_error
                    .clone()
                    .unwrap_or_else(|| "none".to_string())
            )
        }),
    );
    refill_list(
        &widgets.diagnostics_list,
        snapshot.diagnostics.iter().map(|diagnostic| {
            format!(
                "{}\n{}{}",
                provider_title(&diagnostic.provider),
                diagnostic.summary_line,
                diagnostic
                    .last_error
                    .as_ref()
                    .map(|error| format!("\nLast error: {}", error))
                    .unwrap_or_default()
            )
        }),
    );
    refill_list(&widgets.tips_list, snapshot.tips.iter().cloned());
    refill_list(
        &widgets.history_list,
        snapshot.history_items.iter().map(|item| {
            format!(
                "{} [{} / {}]\nOriginal: {}\nFinal: {}{}",
                chrono::DateTime::<chrono::Utc>::from_timestamp_millis(item.timestamp_ms)
                    .map(|value| value.format("%Y-%m-%d %H:%M").to_string())
                    .unwrap_or_else(|| item.timestamp_ms.to_string()),
                item.provider,
                item.language,
                item.original_text,
                item.final_pasted_text,
                item.error
                    .as_ref()
                    .map(|error| format!("\nError: {}", error))
                    .unwrap_or_default()
            )
        }),
    );
    refill_list(
        &widgets.dictionary_list,
        snapshot
            .dictionary_entries
            .iter()
            .map(|entry| format!("{}\n{}", entry.phrase, entry.hint)),
    );
}

fn header(status_label: &gtk::Label) -> gtk::Box {
    let title = gtk::Label::new(Some("Verbatim"));
    title.set_xalign(0.0);
    title.add_css_class("title-1");

    let container = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(6)
        .build();
    container.append(&title);
    container.append(status_label);
    container
}

fn card(child: &impl IsA<gtk::Widget>) -> gtk::Frame {
    gtk::Frame::builder().child(child).build()
}

fn section_title(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.0);
    label.add_css_class("title-4");
    label
}

fn refill_combo<I>(combo: &gtk::ComboBoxText, rows: I, active: Option<String>)
where
    I: IntoIterator<Item = (String, String)>,
{
    combo.remove_all();
    for (id, label) in rows {
        combo.append(Some(&id), &label);
    }
    if let Some(active) = active {
        combo.set_active_id(Some(&active));
    }
}

fn refill_list<I>(list: &gtk::ListBox, rows: I)
where
    I: IntoIterator<Item = String>,
{
    while let Some(child) = list.first_child() {
        list.remove(&child);
    }

    for row in rows {
        let label = gtk::Label::new(Some(&row));
        label.set_xalign(0.0);
        label.set_wrap(true);
        list.append(&label);
    }
}

fn provider_identifier(provider: &contract::ProviderID) -> &'static str {
    match provider {
        contract::ProviderID::AppleSpeech => "apple_speech",
        contract::ProviderID::Whisper => "whisper",
        contract::ProviderID::Parakeet => "parakeet",
    }
}
