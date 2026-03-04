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
                case .logicSettings:
                    logicSettingsContent
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
                    .disabled(!hasTranscriptText)

                    Button {
                        viewModel.clearTranscript()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(!hasTranscriptText)
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
                settingsHeader(
                    title: "Transcription Settings",
                    subtitle: "Transcription model, mode, and speech options"
                )
                transcriptionModeCard
                    .liquidCard(cornerRadius: 20)
                transcriptionModelCard
                    .liquidCard(cornerRadius: 20)
                if viewModel.transcriptionMode == .remote {
                    apiKeyCard
                        .liquidCard(cornerRadius: 20)
                }
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

    private var logicSettingsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsHeader(
                    title: "Logic Settings",
                    subtitle: "Logic model, mode, and formatting preferences"
                )
                logicModeCard
                    .liquidCard(cornerRadius: 20)
                if viewModel.logicMode == .remote {
                    apiKeyCard
                        .liquidCard(cornerRadius: 20)
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func settingsHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptionModeCard: some View {
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

    private var transcriptionModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Model")
                .font(.headline)

            if viewModel.transcriptionMode == .remote {
                remoteModelSection
                remoteCapabilitySection
            } else {
                localModelSection
            }
        }
    }

    private var remoteModelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remote model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Refresh", systemImage: "arrow.clockwise") {
                    viewModel.refreshRemoteModels()
                }
                .buttonStyle(.glass)
                .disabled(isBusy || !viewModel.hasApiKeyConfigured)
            }

            if case .loading = viewModel.remoteModelsLoadState {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(viewModel.remoteTranscriptionStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.isRemoteModelsStatusError ? .orange : .secondary)

            if case .idle = viewModel.remoteModelsLoadState, viewModel.remoteTranscriptionModels.isEmpty {
                Text("Enable Advanced snapshot models only if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Show advanced models", isOn: $viewModel.showAdvancedTranscriptionModels)
                    .disabled(isBusy)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(viewModel.remoteTranscriptionModels) { model in
                    let isSelectable = model.isAvailable
                    Button {
                        viewModel.selectRemoteTranscriptionModel(model.entry.id)
                    } label: {
                        modelRow(
                            title: model.title,
                            subtitle: model.entry.notes ?? model.entry.id,
                            isSelected: viewModel.selectedRemoteModelID == model.entry.id,
                            badgeText: model.isAvailable ? "OpenAI" : "Unavailable",
                            isAvailable: isSelectable,
                            notes: ""
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || !model.isAvailable)
                }
            }
        }
    }

    private var localModelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local transcription model")
                .font(.subheadline)
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
                            isAvailable: model.isImplemented,
                            notes: model.isImplemented ? "" : "Coming soon"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
    }

    private var remoteCapabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = viewModel.selectedTranscriptionModel {
                Text("Transcription options")
                    .font(.subheadline.weight(.medium))

                let formats = responseFormats(for: selected)
                if !formats.isEmpty {
                    Picker("Response format", selection: $viewModel.transcribeResponseFormat) {
                        ForEach(formats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.canEnableStreaming {
                    Toggle("Enable streaming", isOn: $viewModel.transcribeUseStream)
                }

                if viewModel.canUseTimestamps {
                    Toggle("Include timestamps", isOn: $viewModel.transcribeUseTimestamps)
                }

                if viewModel.canUseDiarization {
                    Toggle("Speaker labels", isOn: $viewModel.transcribeUseDiarization)
                    if selected.id == "gpt-4o-transcribe-diarize" && viewModel.transcribeUseDiarization {
                        Text("Diarized transcripts require diarized_json format.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if viewModel.transcribeUseDiarization {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Known speaker names (optional)")
                                .font(.caption)
                            TextField(
                                "One speaker name per line",
                                text: $viewModel.transcribeKnownSpeakerNamesText,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                            .disabled(isBusy)

                            Text("Known speaker references (optional data URLs)")
                                .font(.caption)
                            TextField(
                                "One reference clip per line",
                                text: $viewModel.transcribeKnownSpeakerReferencesText,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                            .disabled(isBusy)
                            .font(.caption)

                            Text("Chunking strategy (optional)")
                                .font(.caption)
                            TextField("Leave empty for auto on >30s when supported", text: $viewModel.transcribeChunkingStrategy)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isBusy)
                        }
                    }
                }

                if viewModel.shouldShowLowConfidenceToggle {
                    Toggle("Capture token confidence", isOn: $viewModel.transcribeUseLogprobs)
                        .help("Produces low-confidence spans for logic stage")
                }

                if viewModel.canUsePromptForTranscription {
                    TextField("Prompt (optional)", text: $viewModel.transcribePrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
        }
    }

    private var logicModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logic Mode")
                .font(.headline)

            Picker("Logic mode", selection: $viewModel.logicMode) {
                ForEach(LogicMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.logicMode == .remote {
                Text("Remote logic uses /v1/responses with structured output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Remote model")
                    .font(.subheadline.weight(.medium))

                VStack(spacing: 8) {
                    ForEach(viewModel.remoteLogicModels) { model in
                        Button {
                            viewModel.selectRemoteLogicModel(model.entry.id)
                        } label: {
                            modelRow(
                                title: model.title,
                                subtitle: model.entry.notes ?? model.entry.id,
                                isSelected: viewModel.selectedRemoteLogicModelID == model.entry.id,
                                badgeText: model.isAvailable ? "OpenAI" : "Unavailable",
                                isAvailable: model.isAvailable,
                                notes: ""
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy || !model.isAvailable)
                    }
                }
            } else {
                Text("Local logic engine (Ollama)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(viewModel.localLogicModels) { model in
                        Button {
                            viewModel.selectLocalLogicModel(model.entry.id)
                        } label: {
                            modelRow(
                                title: model.title,
                                subtitle: model.entry.notes ?? model.entry.id,
                                isSelected: viewModel.selectedLocalLogicModelID == model.entry.id,
                                badgeText: model.entry.isEnabled ? "Available" : "Phase 2",
                                isAvailable: model.entry.isEnabled,
                                notes: model.entry.isEnabled ? "" : "Requires local runtime"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy || !model.entry.isEnabled)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Local runtime")
                        .font(.subheadline.weight(.medium))

                    Text("Uses downloaded local model via `ollama run` (no localhost API required).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Check runtime", systemImage: "bolt.badge.checkmark") {
                            viewModel.checkLocalLogicRuntime()
                        }
                        .buttonStyle(.glass)
                        .disabled(isBusy)
                        Spacer()
                    }

                    Text(viewModel.localLogicRuntimeStatusMessage)
                        .font(.caption)
                        .foregroundStyle(viewModel.isLocalLogicRuntimeStatusError ? .orange : .secondary)
                }
            }

            logicOptionsSection
        }
    }

    private var logicOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 4)

            Toggle("Auto format after transcription", isOn: $viewModel.autoFormatEnabled)

            Toggle("Remove filler words", isOn: $viewModel.logicSettings.removeFillerWords)

            HStack {
                Text("Self-corrections")
                    .font(.caption)
                Spacer()
                Picker("Self-corrections", selection: $viewModel.logicSettings.selfCorrectionMode) {
                    ForEach(SelfCorrectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Toggle("Detect list output", isOn: $viewModel.logicSettings.autoDetectLists)

            HStack {
                Text("Output override")
                    .font(.caption)
                Spacer()
                Picker("Output", selection: $viewModel.logicSettings.outputFormat) {
                    ForEach(LogicOutputFormat.allCases) { format in
                        Text(format == .auto ? "Auto" : (format == .paragraph ? "Paragraph" : "Bullets"))
                            .tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack {
                Text("Reasoning effort")
                    .font(.caption)
                Spacer()
                Picker("Reasoning effort", selection: $viewModel.logicSettings.reasoningEffort) {
                    ForEach(LogicReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!viewModel.canConfigureReasoningEffort)
            }
            if !viewModel.canConfigureReasoningEffort && viewModel.logicMode == .remote {
                Text("Reasoning effort applies to GPT-5 logic models.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let lowConfEnabled = (viewModel.transcript?.tokenLogprobs?.isEmpty == false)
            Toggle("Flag low-confidence spans", isOn: $viewModel.logicSettings.flagLowConfidenceWords)
                .disabled(!lowConfEnabled)
                .help(lowConfEnabled ? "" : "Run logic with a model that supports logprobs in transcription.")

            if viewModel.logicMode == .local {
                Text("Local mode uses Ollama and returns raw transcript if JSON repair fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .onSubmit { viewModel.saveApiKey() }
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

                if viewModel.shouldShowTranscriptTabs {
                    Picker("Transcript view", selection: $viewModel.selectedTranscriptViewMode) {
                        ForEach(TranscriptViewMode.allCases) { mode in
                            Text(mode == .raw ? "Raw" : "Formatted").tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .disabled(viewModel.transcript == nil || viewModel.formattedOutput == nil)
                }

                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let warning = viewModel.lastErrorSummary, !warning.isEmpty, viewModel.selectedTranscriptViewMode == .formatted {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 4)
            }

            ScrollView {
                Text(activeTranscriptText)
                    .font(.body)
                    .foregroundStyle(activeTranscriptText.contains("Your transcript will appear here") ? .tertiary : .primary)
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

    private func modelRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        badgeText: String,
        isAvailable: Bool,
        notes: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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

            if !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.22 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
        )
        .opacity(isAvailable ? 1.0 : 0.65)
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

    private var activeEngineSummary: String {
        let transMode = viewModel.transcriptionMode == .remote
            ? "Remote STT"
            : "Local STT"
        let logicMode = viewModel.logicMode == .remote
            ? "Remote logic"
            : "Local logic (Phase 2)"
        return "\(transMode) / \(logicMode)"
    }

    private var hasTranscriptText: Bool {
        !activeTranscriptText.isEmpty && activeTranscriptText != "Your transcript will appear here after recording."
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .recording, .transcribing, .formatting:
            return true
        case .idle, .done, .error:
            return false
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
        case .formatting:
            return "brain"
        case .done:
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
        case .formatting:
            return "Formatting"
        case .done:
            return "Complete"
        case .error:
            return "Error"
        }
    }

    private var wordCount: Int {
        activeTranscriptText
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var activeTranscriptText: String {
        guard let transcript = viewModel.transcript else {
            return "Your transcript will appear here after recording."
        }

        switch viewModel.selectedTranscriptViewMode {
        case .raw:
            return renderRawTranscript(transcript)
        case .formatted:
            if let output = viewModel.formattedOutput {
                return renderFormattedOutput(output, transcript: transcript)
            }
            return renderRawTranscript(transcript)
        }
    }

    private func renderRawTranscript(_ transcript: Transcript) -> String {
        if transcript.segments.isEmpty {
            return transcript.rawText
        }

        let hasSpeakerData = transcript.segments.contains { !($0.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) }
        if !hasSpeakerData {
            return transcript.rawText.isEmpty
                ? transcript.segments.map(\.text).joined(separator: " ")
                : transcript.rawText
        }

        return transcript.segments
            .map { segment in
                let prefix = segment.speaker.map { "[\($0)] " } ?? ""
                return "\(prefix)\(segment.text)"
            }
            .joined(separator: "\n")
    }

    private func renderFormattedOutput(_ output: FormattedOutput, transcript: Transcript) -> String {
        if transcriptHasSpeakerData(transcript) && !output.clean_text.contains("[") {
            if !transcript.rawText.isEmpty {
                return transcript.rawText
            }
        }

        if output.format == "bullets" && !output.bullets.isEmpty {
            let bullets = output.bullets.map { "• \($0)" }.joined(separator: "\n")
            return bullets.isEmpty ? transcript.rawText : bullets
        }
        if !output.clean_text.isEmpty {
            return output.clean_text
        }
        return transcript.rawText
    }

    private func transcriptHasSpeakerData(_ transcript: Transcript) -> Bool {
        transcript.segments.contains { segment in
            !(segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
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

    private func responseFormats(for model: ModelRegistryEntry) -> [String] {
        if model.id == "gpt-4o-transcribe-diarize" && viewModel.transcribeUseDiarization {
            return ["diarized_json"]
        }

        return model.allowedResponseFormats
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
