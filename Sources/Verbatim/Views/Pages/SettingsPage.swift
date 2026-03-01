import SwiftUI

struct SettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showClearHistory = false

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Start sound", isOn: $viewModel.startSoundEnabled)
                Toggle("Stop sound", isOn: $viewModel.stopSoundEnabled)
                Toggle("Double-tap Fn lock", isOn: $viewModel.doubleTapFnLockEnabled)
                Toggle("Show overlay meter", isOn: $viewModel.overlayMeterEnabled)
                HStack {
                    Text("Silence threshold")
                    Slider(value: Binding(
                        get: { Double(viewModel.silenceThreshold) },
                        set: { viewModel.silenceThreshold = Float($0) }
                    ), in: 0...0.5)
                    Text(String(format: "%.2f", viewModel.silenceThreshold))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transcription") {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                Picker("OpenAI model", selection: $viewModel.openAIModel) {
                    ForEach(OpenAITranscriptionModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }

                SecureField("OpenAI API key", text: $viewModel.openAIKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()

                HStack {
                    if viewModel.hasStoredOpenAIKey() {
                        Button("Clear OpenAI key") {
                            viewModel.clearOpenAIKey(repository: appState.settingsRepository)
                        }
                    } else {
                        Text("No OpenAI key saved")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Local backend", selection: $viewModel.whisperBackend) {
                    ForEach(WhisperLocalBackend.allCases) { backend in
                        Text(backend.title).tag(backend)
                    }
                }

                Picker("Whisper model", selection: $viewModel.whisperModelId) {
                    ForEach(viewModel.availableWhisperModels) { model in
                        Text(viewModel.modelDisplayName(model)).tag(model.id)
                    }
                }

                TextField("whisper.cpp path", text: $viewModel.whisperCppPath)
                Text("Server binary: \(viewModel.serverBinaryStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Download server binary") {
                        viewModel.downloadServerBinary()
                    }
                    .disabled(viewModel.isDownloadingServerBinary)
                    if viewModel.isDownloadingServerBinary {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                }
                if !viewModel.serverBinaryMessage.isEmpty {
                    Text(viewModel.serverBinaryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Selected model: \(viewModel.selectedModelStatus.path.lastPathComponent)")
                Text(viewModel.selectedModelStatus.isDownloaded ? "Model is available" : "Model is not downloaded")
                    .foregroundStyle(viewModel.selectedModelStatus.isDownloaded ? .green : .secondary)
                    .font(.caption)
                if let size = viewModel.selectedModelStatus.fileSizeBytes {
                    Text("Model size: \(viewModel.formatBytes(size))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Button("Download model") {
                        viewModel.downloadSelectedWhisperModel()
                    }
                    .disabled(viewModel.isDownloadingModel)
                    if viewModel.isDownloadingModel {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                }
                if !viewModel.modelDownloadMessage.isEmpty {
                    Text(viewModel.modelDownloadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Models directory", text: $viewModel.whisperModelsDir)
                Toggle("Auto-start local server", isOn: $viewModel.whisperServerAutoStart)
                Stepper("Server threads", value: $viewModel.whisperLocalThreads, in: 1...64)

                TextField("Legacy whisper model path", text: $viewModel.whisperModelPath)
                TextField("Language", text: $viewModel.language)
            }

            Section("Insertion") {
                Toggle("Auto insert", isOn: $viewModel.autoInsertEnabled)
                Toggle("Clipboard fallback", isOn: $viewModel.clipboardFallbackEnabled)
                Toggle("Show captured toast", isOn: $viewModel.showCapturedToastEnabled)

                Picker("Fallback strategy", selection: $viewModel.insertionModePreferred) {
                    ForEach(InsertionModePreferred.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Data") {
                Stepper("History retention days", value: $viewModel.historyRetentionDays, in: 1...365)
                Toggle("Auto-save long captures to notes", isOn: $viewModel.autoSaveLongCapturesToNotes)
                Stepper("Long capture threshold words", value: $viewModel.longCaptureThresholdWords, in: 20...500)

                Button("Save settings") {
                    viewModel.save(appState.settingsRepository)
                }
                .buttonStyle(.borderedProminent)

                Button("Clear History", role: .destructive) {
                    showClearHistory = true
                }
                .confirmationDialog("Delete all captures?", isPresented: $showClearHistory, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) {
                        viewModel.clearHistory(appState.captureRepository)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(20)
        .onDisappear {
            viewModel.save(appState.settingsRepository)
        }
    }
}
