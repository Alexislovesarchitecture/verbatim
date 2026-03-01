import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: VerbatimStore

    var body: some View {
        Form {
            Section("General") {
                TextField("Display name", text: $store.settings.displayName)
                Picker("Transcription provider", selection: $store.settings.provider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                TextField("Language code", text: $store.settings.languageCode)
            }

            Section("OpenAI") {
                SecureField("OpenAI API key", text: $store.settings.openAIAPIKey)
                TextField("Model", text: $store.settings.openAIModel)
            }

            Section("Local whisper.cpp") {
                TextField("whisper-cli path", text: $store.settings.whisperCLIPath)
                TextField("Model path", text: $store.settings.whisperModelPath)
            }

            Section("Behavior") {
                Toggle("Auto insert into active text field", isOn: $store.settings.autoInsert)
                Toggle("Auto paste fallback when direct insert fails", isOn: $store.settings.autoPasteFallback)
                Toggle("Play start sound", isOn: $store.settings.playStartSound)
                Toggle("Remove filler words", isOn: $store.settings.removeFillers)
                Toggle("Expand snippets", isOn: $store.settings.useSnippetExpansion)
                Toggle("Keep history", isOn: $store.settings.keepHistory)
                Toggle("Keep clipboard backup", isOn: $store.settings.keepClipboardBackup)
            }

            Section {
                Button("Save settings") {
                    store.persist()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
