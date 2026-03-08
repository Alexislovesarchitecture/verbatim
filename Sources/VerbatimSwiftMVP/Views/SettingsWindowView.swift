import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case testing
    case transcription
    case logic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .testing:
            return "Testing"
        case .transcription:
            return "Transcription"
        case .logic:
            return "Logic"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Hotkeys, listening feedback, and insertion behavior."
        case .testing:
            return "Record, review, and manually reformat transcripts away from the home screen."
        case .transcription:
            return "Speech engine, API key, and transcription controls."
        case .logic:
            return "Cleanup model selection, reasoning, and refinement behavior."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .testing:
            return "waveform.and.mic"
        case .transcription:
            return "waveform"
        case .logic:
            return "brain"
        }
    }

    var accent: AppSectionAccent {
        switch self {
        case .general:
            return .mint
        case .testing:
            return .cobalt
        case .transcription:
            return .amber
        case .logic:
            return .violet
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            VerbatimGlassGroup(spacing: 18) {
                NavigationSplitView {
                    settingsSidebar
                } detail: {
                    settingsDetail
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .overlay(alignment: .topLeading) {
            WindowConfigurator(centerOnFirstAppear: true)
                .frame(width: 0, height: 0)
        }
    }

    private var settingsSidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                sidebarHeader
                    .padding(.bottom, 6)

                VStack(spacing: 10) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 14, weight: .semibold))

                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                                Spacer()
                            }
                            .foregroundStyle(
                                selectedSection == section
                                    ? section.accent.tint
                                    : VerbatimPalette.ink.opacity(0.84)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(
                            VerbatimRailButtonStyle(
                                isActive: selectedSection == section,
                                accent: section.accent
                            )
                        )
                        .accessibilityLabel(section.title)
                        .help(section.subtitle)
                    }
                }
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 238, max: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Label("Back to App", systemImage: "arrow.left")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .applyGlassButtonStyle()
            .keyboardShortcut(.cancelAction)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                VerbatimBrandMark(size: 28)
                    .applyLiquidCardStyle(cornerRadius: 14, tone: .rail, padding: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Verbatim")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Settings")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()
            }
            .applyLiquidCardStyle(cornerRadius: 24, tone: .rail, padding: 14)
        }
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.20, green: 0.24, blue: 0.32).opacity(0.28)
                ]
                : [
                    Color.white.opacity(0.34),
                    Color(red: 0.86, green: 0.89, blue: 0.95).opacity(0.22)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.thinMaterial)
    }

    private var settingsDetail: some View {
        ZStack {
            detailBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    detailHeader(for: selectedSection)

                    switch selectedSection {
                    case .general:
                        LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                            hotkeyCapturePanel
                            interactionPreferencesPanel
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)

                        if !viewModel.hotkeyPermissionGranted {
                            permissionPanel
                                .applyLiquidCardStyle(cornerRadius: 28, tone: .cream, padding: 22)
                        }
                    case .testing:
                        LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                            testingCapturePanel
                            testingReviewPanel
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
                    case .transcription:
                        LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                            transcriptionModeCard

                            if viewModel.transcriptionMode == .remote {
                                apiKeyCard
                            } else {
                                localTranscriptionOverviewCard
                            }
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)

                        VStack(spacing: 18) {
                            transcriptionModelCard

                            if viewModel.transcriptionMode == .remote, viewModel.selectedTranscriptionModel != nil {
                                transcriptionOptionsCard
                            }
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
                    case .logic:
                        LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                            logicModeCard

                            if viewModel.logicMode == .remote {
                                apiKeyCard
                            }
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)

                        VStack(spacing: 18) {
                            logicModelSelectionCard
                            logicPreferencesCard
                        }
                        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
                    }
                }
                .padding(22)
                .frame(maxWidth: 980, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.36),
                    Color(red: 0.12, green: 0.15, blue: 0.21).opacity(0.30)
                ]
                : [
                    Color.white.opacity(0.40),
                    Color(red: 0.89, green: 0.92, blue: 0.97).opacity(0.28),
                    Color(red: 0.82, green: 0.86, blue: 0.93).opacity(0.18)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.regularMaterial)
        .ignoresSafeArea()
    }

    private func detailHeader(for section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(section.accent.tint)

            Text(section.title)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(VerbatimPalette.ink)

            Text(section.subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private var hotkeyCapturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Hotkey Dictation",
                subtitle: "Capture, reset, and tune the trigger without leaving the app."
            )

            Toggle("Enable global hotkey", isOn: $viewModel.interactionSettings.hotkeyEnabled)

            HStack {
                Text("Current binding")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Spacer()

                Text(viewModel.hotkeyBindingTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)
                    .applyStatusBadgeEffect()
            }

            HStack(spacing: 10) {
                Button(viewModel.isCapturingHotkey ? "Capturing..." : "Set hotkey") {
                    viewModel.beginHotkeyCapture()
                }
                .applyGlassButtonStyle()
                .disabled(viewModel.isCapturingHotkey)

                Button("Use Fn default") {
                    viewModel.resetHotkeyToDefault()
                }
                .applyGlassButtonStyle()
                .disabled(viewModel.isCapturingHotkey)

                if viewModel.isCapturingHotkey {
                    Button("Cancel") {
                        viewModel.cancelHotkeyCapture()
                    }
                    .applyGlassButtonStyle()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Picker("Trigger mode", selection: $viewModel.interactionSettings.hotkeyTriggerMode) {
                    ForEach(HotkeyTriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.isCapturingHotkey {
                Text("Press any key combination, or use Fn / Globe directly.")
                    .font(.caption)
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
    }

    private var interactionPreferencesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Feedback + Insertion",
                subtitle: "Tune how Verbatim signals listening and handles insertions."
            )

            Toggle("Show listening indicator", isOn: $viewModel.interactionSettings.showListeningIndicator)
            Toggle("Play start/stop sound cues", isOn: $viewModel.interactionSettings.playSoundCues)
            Toggle("Auto-paste after insert", isOn: $viewModel.interactionSettings.autoPasteAfterInsert)

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Picker("Appearance", selection: $viewModel.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(viewModel.hotkeyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.hotkeyPermissionGranted ? VerbatimPalette.mutedInk : Color.orange)
        }
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeading(
                title: "Accessibility Permission",
                subtitle: "Fn / Globe hotkeys and insertion need Accessibility access."
            )

            Text("Prompt macOS for access, then enable Verbatim in System Settings > Privacy & Security > Accessibility.")
                .font(.body)
                .foregroundStyle(VerbatimPalette.ink)

            Button("Prompt Accessibility Access") {
                viewModel.requestAccessibilityPermissionPrompt()
            }
            .applyGlassButtonStyle(prominent: true)
        }
    }

    private var testingCapturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Live Dictation",
                subtitle: "Use this area as the testing ground for recording, inserting, and validating transcript behavior."
            )

            Text("Testing moved out of Home so your main screen can stay focused on transcript history.")
                .font(.body)
                .foregroundStyle(VerbatimPalette.ink)

            HStack(spacing: 12) {
                Button(action: handleTestingPrimaryAction) {
                    Label(testingPrimaryButtonTitle, systemImage: testingPrimaryButtonSymbol)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(!viewModel.canToggleRecording)

                VStack(alignment: .leading, spacing: 8) {
                    Label(testingStateLabel, systemImage: testingStatusSymbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)
                        .applyStatusBadgeEffect()

                    Text(testingEngineSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
                .frame(maxWidth: 220, alignment: .leading)
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private var testingReviewPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(AppSectionAccent.cobalt.tint)

                    Text("Current Transcript")
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(viewModel.promptProfiles) { profile in
                            Button(profile.name) {
                                viewModel.runManualReformat(profileID: profile.id)
                            }
                            .disabled(viewModel.transcript == nil || !profile.enabled || isBusy)
                        }
                    } label: {
                        Label("Reformat", systemImage: "wand.and.stars")
                    }
                    .applyGlassButtonStyle()
                    .disabled(viewModel.transcript == nil || viewModel.promptProfiles.isEmpty)

                    Button {
                        viewModel.copyTranscript()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .applyGlassButtonStyle()
                    .disabled(!testingHasTranscriptText)

                    Button {
                        viewModel.clearTranscript()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .applyGlassButtonStyle()
                    .disabled(!testingHasTranscriptText)
                }
            }

            if viewModel.shouldShowTranscriptTabs {
                Picker("Transcript view", selection: $viewModel.selectedTranscriptViewMode) {
                    ForEach(TranscriptViewMode.allCases) { mode in
                        Text(mode == .raw ? "Raw" : "Formatted").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .disabled(viewModel.transcript == nil || viewModel.formattedOutput == nil)
            }

            if let warning = viewModel.lastErrorSummary,
               !warning.isEmpty,
               viewModel.selectedTranscriptViewMode == .formatted {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView(showsIndicators: false) {
                Text(testingActiveTranscriptText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(testingHasTranscriptText ? VerbatimPalette.ink : VerbatimPalette.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
            .applyInsetWellStyle(cornerRadius: 24, padding: 18)
        }
    }

    private var transcriptionModeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Speech Engine",
                subtitle: "Choose whether transcription runs locally or through OpenAI."
            )

            Picker("Transcription Mode", selection: $viewModel.transcriptionMode) {
                ForEach(TranscriptionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)

            Text(viewModel.transcriptionMode.subtitle)
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private var localTranscriptionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading(
                title: "Local Mode",
                subtitle: "Local transcription avoids network round-trips and keeps setup simple."
            )

            Text("Switch to Remote when you want OpenAI transcription models and their richer feature set.")
                .font(.body)
                .foregroundStyle(VerbatimPalette.ink)
        }
    }

    private var transcriptionModelCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeading(
                title: "Model Selection",
                subtitle: "Pick the speech model first, then tune the controls below."
            )

            if viewModel.transcriptionMode == .remote {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Remote models")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VerbatimPalette.mutedInk)

                        Spacer()

                        Button("Refresh models", systemImage: "arrow.clockwise") {
                            viewModel.refreshRemoteModels()
                        }
                        .applyGlassButtonStyle()
                        .disabled(isBusy || !viewModel.hasApiKeyConfigured)
                    }

                    Toggle("Show advanced", isOn: $viewModel.showAdvancedTranscriptionModels)
                        .disabled(isBusy)

                    if case .loading = viewModel.remoteModelsLoadState {
                        ProgressView()
                    }

                    Text(viewModel.remoteTranscriptionStatusMessage)
                        .font(.caption)
                        .foregroundStyle(viewModel.isRemoteModelsStatusError ? Color.orange : VerbatimPalette.mutedInk)

                    VStack(spacing: 10) {
                        ForEach(viewModel.remoteTranscriptionModels) { model in
                            Button {
                                viewModel.selectRemoteTranscriptionModel(model.entry.id)
                            } label: {
                                modelRow(
                                    title: model.title,
                                    subtitle: model.entry.notes ?? model.entry.id,
                                    isSelected: viewModel.selectedRemoteModelID == model.entry.id,
                                    badgeText: model.isAvailable ? "OpenAI" : "Unavailable",
                                    isAvailable: model.isAvailable,
                                    notes: "",
                                    accent: .amber
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy || !model.isAvailable)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local models")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    VStack(spacing: 10) {
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
                                    notes: model.isImplemented ? "" : "Coming soon",
                                    accent: .amber
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
    }

    private var transcriptionOptionsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeading(
                title: "Advanced Transcription Options",
                subtitle: "Response format, timestamps, streaming, and diarization."
            )

            if let selected = viewModel.selectedTranscriptionModel {
                let formats = responseFormats(for: selected)

                VStack(alignment: .leading, spacing: 14) {
                    if !formats.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Response format")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VerbatimPalette.mutedInk)

                            Picker("Response format", selection: $viewModel.transcribeResponseFormat) {
                                ForEach(formats, id: \.self) { format in
                                    Text(format).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.canEnableStreaming {
                            Toggle("Enable streaming", isOn: $viewModel.transcribeUseStream)
                        }

                        if viewModel.canUseTimestamps {
                            Toggle("Include timestamps", isOn: $viewModel.transcribeUseTimestamps)
                        }

                        if viewModel.canUseDiarization {
                            Toggle("Speaker labels", isOn: $viewModel.transcribeUseDiarization)

                            if selected.id == "gpt-4o-transcribe-diarize" && viewModel.transcribeUseDiarization {
                                Text("Diarized transcripts require `diarized_json` format.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        if viewModel.shouldShowLowConfidenceToggle {
                            Toggle("Capture token confidence", isOn: $viewModel.transcribeUseLogprobs)
                                .help("Produces low-confidence spans for the logic stage.")
                        }
                    }
                    .applyInsetWellStyle(cornerRadius: 20, padding: 16)

                    if viewModel.transcribeUseDiarization {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Speaker hints")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VerbatimPalette.mutedInk)

                            TextField("One speaker name per line", text: $viewModel.transcribeKnownSpeakerNamesText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...5)
                                .disabled(isBusy)

                            TextField("One reference clip per line", text: $viewModel.transcribeKnownSpeakerReferencesText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...5)
                                .disabled(isBusy)
                                .font(.caption)

                            TextField("Leave chunking empty for auto on longer sessions", text: $viewModel.transcribeChunkingStrategy)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isBusy)
                        }
                        .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                    }

                    if viewModel.canUsePromptForTranscription {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VerbatimPalette.mutedInk)

                            TextField("Optional prompt", text: $viewModel.transcribePrompt, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                        .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                    }
                }
            }
        }
    }

    private var logicModeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Logic Engine",
                subtitle: "Use OpenAI responses remotely or keep refinement local through Ollama."
            )

            Picker("Logic mode", selection: $viewModel.logicMode) {
                ForEach(LogicMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.logicMode == .remote {
                Text("Remote logic uses `/v1/responses` with structured output.")
                    .font(.caption)
                    .foregroundStyle(VerbatimPalette.mutedInk)
            } else {
                Text("Local logic uses Ollama with hidden thinking by default, then returns only the cleaned transcript.")
                    .font(.caption)
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }
        }
    }

    private var logicModelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeading(
                title: "Model Selection",
                subtitle: "Pick the refinement model and confirm runtime availability when local mode is active."
            )

            if viewModel.logicMode == .remote {
                VStack(spacing: 10) {
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
                                notes: "",
                                accent: .violet
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy || !model.isAvailable)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 10) {
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
                                    notes: model.entry.isEnabled ? "" : "Requires local runtime",
                                    accent: .violet
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy || !model.entry.isEnabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Local runtime")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VerbatimPalette.mutedInk)

                        Text("Uses downloaded local models via `ollama run`, with no localhost API dependency.")
                            .font(.caption)
                            .foregroundStyle(VerbatimPalette.mutedInk)

                        HStack(spacing: 10) {
                            Button("Check runtime", systemImage: "bolt.badge.checkmark") {
                                viewModel.checkLocalLogicRuntime()
                            }
                            .applyGlassButtonStyle()
                            .disabled(isBusy)

                            Text(viewModel.localLogicRuntimeStatusMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.isLocalLogicRuntimeStatusError ? Color.orange : VerbatimPalette.mutedInk)
                        }
                    }
                    .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                }
            }
        }
    }

    private var logicPreferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Logic Preferences",
                subtitle: "Guide cleanup, structure, and reasoning for the refinement stage."
            )

            Toggle("Auto format after transcription", isOn: $viewModel.autoFormatEnabled)
            Toggle("Remove filler words", isOn: $viewModel.logicSettings.removeFillerWords)
            Toggle("Detect list output", isOn: $viewModel.logicSettings.autoDetectLists)

            preferenceMenuRow(title: "Self-corrections") {
                Picker("Self-corrections", selection: $viewModel.logicSettings.selfCorrectionMode) {
                    ForEach(SelfCorrectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            preferenceMenuRow(title: "Output override") {
                Picker("Output", selection: $viewModel.logicSettings.outputFormat) {
                    ForEach(LogicOutputFormat.allCases) { format in
                        Text(format == .auto ? "Auto" : (format == .paragraph ? "Paragraph" : "Bullets"))
                            .tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            preferenceMenuRow(title: "Reasoning effort") {
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
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            if viewModel.logicMode == .local, viewModel.canConfigureReasoningEffort {
                Text("For local GPT OSS, this maps to Ollama's thinking level. Visible thinking stays hidden so only the final cleaned text lands in the transcript.")
                    .font(.caption2)
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            let lowConfEnabled = (viewModel.transcript?.tokenLogprobs?.isEmpty == false)
            Toggle("Flag low-confidence spans", isOn: $viewModel.logicSettings.flagLowConfidenceWords)
                .disabled(!lowConfEnabled)
                .help(lowConfEnabled ? "" : "Run transcription with logprobs enabled.")
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "OpenAI API Key",
                subtitle: "Remote speech and logic require a stored key in this app."
            )

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

            HStack(spacing: 10) {
                Button("Save Key") {
                    viewModel.saveApiKey()
                }
                .applyGlassButtonStyle(prominent: true)
                .disabled(!viewModel.canSaveApiKey || isBusy)

                Button("Clear Key") {
                    viewModel.clearStoredApiKey()
                }
                .applyGlassButtonStyle()
                .disabled(!viewModel.canClearApiKey || isBusy)
            }

            Text(viewModel.keyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.hasApiKeyConfigured ? VerbatimPalette.mutedInk : Color.orange)
        }
    }

    private func panelHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(VerbatimPalette.ink)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preferenceMenuRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Spacer()

            content()
        }
    }

    private func modelRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        badgeText: String,
        isAvailable: Bool,
        notes: String,
        accent: AppSectionAccent
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isAvailable ? VerbatimPalette.ink : VerbatimPalette.mutedInk)
                    .applyStatusBadgeEffect()
            }

            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accent.tint : VerbatimPalette.mutedInk)

                Text(isSelected ? "Selected" : "Tap to choose")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isAvailable ? VerbatimPalette.ink : VerbatimPalette.mutedInk)

                Spacer()
            }

            if !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? accent.glow : Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? accent.tint.opacity(0.70) : Color.white.opacity(0.24),
                            lineWidth: 1
                        )
                )
        )
        .opacity(isAvailable ? 1 : 0.68)
    }

    private var settingsColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 18, alignment: .top)]
    }

    private var testingHasTranscriptText: Bool {
        !testingActiveTranscriptText.isEmpty && testingActiveTranscriptText != "Your transcript will appear here after recording."
    }

    private var testingEngineSummary: String {
        let transMode = viewModel.transcriptionMode == .remote ? "Remote STT" : "Local STT"
        let logicMode = viewModel.logicMode == .remote ? "Remote logic" : "Local logic"
        return "\(transMode) / \(logicMode)"
    }

    private var testingPrimaryButtonTitle: String {
        switch viewModel.state {
        case .recording:
            return "Stop"
        case .transcribing, .formatting:
            return "Processing..."
        case .idle, .done, .error:
            return "Start recording"
        }
    }

    private var testingPrimaryButtonSymbol: String {
        viewModel.state == .recording ? "stop.fill" : "mic.fill"
    }

    private var testingStateLabel: String {
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

    private var testingStatusSymbol: String {
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

    private var testingActiveTranscriptText: String {
        guard let transcript = viewModel.transcript else {
            return "Your transcript will appear here after recording."
        }

        switch viewModel.selectedTranscriptViewMode {
        case .raw:
            return testingRenderRawTranscript(transcript)
        case .formatted:
            if let output = viewModel.formattedOutput {
                return testingRenderFormattedOutput(output, transcript: transcript)
            }
            if let deterministic = viewModel.deterministicResult?.text, !deterministic.isEmpty {
                return deterministic
            }
            return testingRenderRawTranscript(transcript)
        }
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .recording, .transcribing, .formatting:
            return true
        case .idle, .done, .error:
            return false
        }
    }

    private func responseFormats(for model: ModelRegistryEntry) -> [String] {
        if model.id == "gpt-4o-transcribe-diarize" && viewModel.transcribeUseDiarization {
            return ["diarized_json"]
        }

        return model.allowedResponseFormats
    }

    private func handleTestingPrimaryAction() {
        switch viewModel.state {
        case .recording:
            viewModel.stop()
        default:
            viewModel.start()
        }
    }

    private func testingRenderRawTranscript(_ transcript: Transcript) -> String {
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

    private func testingRenderFormattedOutput(_ output: FormattedOutput, transcript: Transcript) -> String {
        if testingTranscriptHasSpeakerData(transcript) && !output.clean_text.contains("[") {
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

    private func testingTranscriptHasSpeakerData(_ transcript: Transcript) -> Bool {
        transcript.segments.contains { segment in
            !(segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

private struct SettingsWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.10, green: 0.12, blue: 0.17),
                    Color(red: 0.14, green: 0.18, blue: 0.26),
                    Color(red: 0.09, green: 0.11, blue: 0.16)
                ]
                : [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.86, green: 0.89, blue: 0.95),
                    Color(red: 0.95, green: 0.97, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#if canImport(AppKit)
private struct WindowConfigurator: NSViewRepresentable {
    let centerOnFirstAppear: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(from nsView: NSView, coordinator: Coordinator) {
        guard let window = nsView.window else { return }

        if coordinator.window !== window {
            coordinator.window = window

            if centerOnFirstAppear {
                window.center()
            }
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    final class Coordinator {
        weak var window: NSWindow?
    }
}
#else
private struct WindowConfigurator: View {
    let centerOnFirstAppear: Bool

    var body: some View {
        EmptyView()
    }
}
#endif
