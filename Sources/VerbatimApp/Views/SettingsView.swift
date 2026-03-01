import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Transcription engine", selection: $controller.settings.selectedEngine) {
                    ForEach(TranscriptOrigin.allCases) { origin in
                        Text(origin.title).tag(origin)
                    }
                }

                TextField("OpenAI model", text: $controller.settings.openAIModel)
                SecureField("OpenAI API key", text: $controller.settings.openAIAPIKey)
                TextField("whisper.cpp binary path", text: $controller.settings.whisperBinaryPath)
                TextField("whisper.cpp model path", text: $controller.settings.whisperModelPath)
                TextField("Language code", text: $controller.settings.selectedLanguageCode)
                    .textInputAutocapitalization(.never)
            }

            Section("Behavior") {
                Toggle("Auto insert when editable", isOn: $controller.settings.autoInsertWhenEditable)
                Toggle("Copy fallback transcript to clipboard", isOn: $controller.settings.fallbackCopiesToClipboard)
                Toggle("Play start sound", isOn: $controller.settings.playStartSound)
                Toggle("Play stop sound", isOn: $controller.settings.playStopSound)
                HStack {
                    Text("Double-tap lock window")
                    Slider(value: $controller.settings.doubleTapLockWindowSeconds, in: 0.18...0.5, step: 0.01)
                    Text("\(controller.settings.doubleTapLockWindowSeconds.formatted(.number.precision(.fractionLength(2))))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Quick actions") {
                Button("Request permissions again") {
                    controller.start()
                }
                Button("Simulate mock capture") {
                    controller.simulateMockCapture()
                }
                if controller.lastCapture != nil {
                    Button("Paste last capture") {
                        controller.pasteLastCapture()
                    }
                }
            }

            if let errorMessage = controller.errorMessage {
                Section("Last error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
}
