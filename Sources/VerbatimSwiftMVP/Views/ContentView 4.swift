import SwiftUI

@available(macOS 26.0, *)
@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            ZStack {
                ambientBackground

                switch viewModel.selectedSection {
                case .workspace:
                    workspaceContent
                case .transcriptionSettings:
                    transcriptionSettingsContent
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            if viewModel.selectedSection == .workspace {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewModel.copyTranscript()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.transcript.isEmpty)

                    Button {
                        viewModel.clearTranscript()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.transcript.isEmpty)
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: selectedSectionBinding) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.body.weight(section == viewModel.selectedSection ? .semibold : .regular))
                    .tag(section)
                    .padding(.vertical, 6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(sidebarBackground)
    }

    private var workspaceContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                workspaceHeader

                recordingCard
                    .liquidCard(cornerRadius: 20)

                transcriptCard
                    .liquidCard(cornerRadius: 24)
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var transcriptionSettingsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsHeader

                modeCard
                    .liquidCard(cornerRadius: 20)

                modelSelectionCard
                    .liquidCard(cornerRadius: 20)

                apiKeyCard
                    .liquidCard(cornerRadius: 20)
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var workspaceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(activeEngineSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(stateLabel, systemImage: statusSymbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var settingsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Configure mode, model, and API key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Mode")
                .font(.headline)

            Picker("Transcription Mode", selection: $viewModel.transcriptionMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)

            Text(viewModel.transcriptionMode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Selection")
                    .font(.headline)

                Spacer()

                if viewModel.transcriptionMode == .remote {
                    Button {
                        viewModel.refreshRemoteModels()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(isBusy || !viewModel.hasApiKeyConfigured)
                }
            }

            if viewModel.transcriptionMode == .remote {
                if case .loading = viewModel.remoteModelsLoadState {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(viewModel.remoteModelsStatusMessage)
                    .font(.caption)
                    .foregroundStyle(viewModel.isRemoteModelsStatusError ? .orange : .secondary)

                VStack(spacing: 8) {
                    ForEach(viewModel.availableRemoteModels) { model in
                        Button {
                            viewModel.selectRemoteModel(model)
                        } label: {
                            modelRow(
                                title: model.displayName,
                                subtitle: model.id,
                                isSelected: viewModel.selectedRemoteModelID == model.id,
                                badgeText: "OpenAI",
                                isAvailable: true
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
            } else {
                Text("Local model selection")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(LocalTranscriptionModel.allCases) { model in
                        Button {
                            viewModel.selectLocalModel(model)
                        } label: {
                            modelRow(
                                title: model.title,
                                subtitle: model.detail,
                                isSelected: viewModel.selectedLocalModel == model,
                                badgeText: model.isImplemented ? "Ready" : "Soon",
                                isAvailable: model.isImplemented
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
            }
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI API Key")
                .font(.headline)

            SecureField(
                "Paste OpenAI API key",
                text: Binding(
                    get: { viewModel.apiKey },
                    set: { viewModel.apiKey = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onSubmit {
                viewModel.saveApiKey()
            }
            .disabled(isBusy)

            HStack(spacing: 8) {
                Button("Save Key") {
                    viewModel.saveApiKey()
                }
                .buttonStyle(.glassProminent)
                .disabled(!viewModel.canSaveApiKey || isBusy)

                Button("Clear Key") {
                    viewModel.clearStoredApiKey()
                }
                .buttonStyle(.glass)
                .disabled(!viewModel.canClearApiKey || isBusy)

                Spacer()
            }

            Text(viewModel.keyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.hasApiKeyConfigured ? Color.secondary : Color.orange)
        }
    }

    private var recordingCard: some View {
        VStack(spacing: 12) {
            Label(viewModel.statusMessage, systemImage: statusSymbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: handlePrimaryAction) {
                Label(viewModel.primaryButtonTitle, systemImage: primaryButtonSymbol)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(!viewModel.canToggleRecording)
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(viewModel.transcript.isEmpty ? "Your transcript will appear here after recording." : viewModel.transcript)
                    .font(.body)
                    .foregroundStyle(viewModel.transcript.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func modelRow(title: String, subtitle: String, isSelected: Bool, badgeText: String, isAvailable: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(badgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.14), in: Capsule())
                .foregroundStyle(isAvailable ? .primary : .secondary)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.22 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.18),
                    lineWidth: 1
                )
        )
        .opacity(isAvailable ? 1.0 : 0.82)
    }

    private var selectedSectionBinding: Binding<AppSection?> {
        Binding(
            get: { viewModel.selectedSection },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectedSection = newValue
            }
        )
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .recording, .transcribing:
            return true
        case .idle, .ready, .error:
            return false
        }
    }

    private var activeEngineSummary: String {
        switch viewModel.transcriptionMode {
        case .remote:
            let selectedName = viewModel.availableRemoteModels.first(where: { $0.id == viewModel.selectedRemoteModelID })?.displayName
                ?? viewModel.selectedRemoteModelID
            return selectedName.isEmpty ? "Remote transcription" : "Remote transcription • \(selectedName)"
        case .local:
            return "Local transcription • \(viewModel.selectedLocalModel.title)"
        }
    }

    private var statusSymbol: String {
        switch viewModel.state {
        case .idle:
            return "checkmark.circle"
        case .recording:
            return "waveform"
        case .transcribing:
            return "hourglass"
        case .ready:
            return "checkmark.seal"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var primaryButtonSymbol: String {
        if viewModel.state == .recording {
            return "stop.fill"
        }
        return "mic.fill"
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .ready:
            return "Complete"
        case .error:
            return "Error"
        }
    }

    private var wordCount: Int {
        viewModel.transcript
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.20, blue: 0.28),
                Color(red: 0.11, green: 0.14, blue: 0.21)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial.opacity(0.78))
        )
    }

    private var ambientBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.21, green: 0.26, blue: 0.35),
                    Color(red: 0.10, green: 0.13, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -260, y: -240)

            Circle()
                .fill(Color.cyan.opacity(0.17))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: 290, y: 260)
        }
        .ignoresSafeArea()
    }

    private func handlePrimaryAction() {
        switch viewModel.state {
        case .recording:
            viewModel.stop()
        default:
            viewModel.start()
        }
    }
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
private extension View {
    func liquidCard(cornerRadius: CGFloat) -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
            )
    }
}
