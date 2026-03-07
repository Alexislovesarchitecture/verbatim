import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case transcription
    case logic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .transcription:
            return "Transcription"
        case .logic:
            return "Logic"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Hotkeys, feedback, and insertion behavior."
        case .transcription:
            return "Speech engine, API key, and transcription controls."
        case .logic:
            return "Refinement engine, model selection, and logic behavior."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
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
        case .transcription:
            return .amber
        case .logic:
            return .violet
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsPresented = false

    var body: some View {
        VerbatimGlassGroup(spacing: 14) {
            windowShell
                .padding(10)
        }
        .overlay(alignment: .topLeading) {
            MainWindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .sheet(isPresented: actionItemsPreviewBinding) {
            actionItemsSheet
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
        }
    }

    private var windowShell: some View {
        HStack(spacing: 14) {
            navigationRail
            detailCanvas
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var navigationRail: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                VerbatimBrandMark(size: 34)
                    .padding(14)
                    .applyLiquidCardStyle(cornerRadius: 22, tone: .frost, padding: 0)

                Text("Verbatim")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink.opacity(0.88))
            }
            .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        viewModel.selectedSection = section
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(section.shortTitle)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(
                            section == viewModel.selectedSection
                                ? section.accent.tint
                                : VerbatimPalette.ink.opacity(0.76)
                        )
                    }
                    .buttonStyle(
                        VerbatimRailButtonStyle(
                            isActive: section == viewModel.selectedSection,
                            accent: section.accent
                        )
                    )
                    .accessibilityLabel(section.accessibilityLabel)
                    .help(section.accessibilityLabel)
                }
            }

            Spacer()

            Button {
                openSettingsWindow()
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(VerbatimPalette.ink.opacity(0.76))
            }
            .buttonStyle(
                VerbatimRailButtonStyle(
                    isActive: false,
                    accent: .mint
                )
            )
            .help("Settings")
        }
        .frame(width: 110)
        .padding(.vertical, 8)
        .applyLiquidCardStyle(cornerRadius: 30, tone: .rail, padding: 12)
    }

    private var detailCanvas: some View {
        currentSectionContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .applyLiquidCardStyle(cornerRadius: 32, tone: .frost, padding: 0)
    }

    @ViewBuilder
    private var currentSectionContent: some View {
        switch viewModel.selectedSection {
        case .home:
            homeContent
        case .dictionary:
            dictionaryContent
        case .style:
            styleContent
        }
    }

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                sectionHeader(
                    eyebrow: viewModel.selectedSection.shortTitle.uppercased(),
                    title: "Home",
                    subtitle: viewModel.selectedSection.subtitle,
                    accent: viewModel.selectedSection.accent
                ) {
                    workspaceHeaderActions
                }

                workspaceHeroCard
                transcriptCard
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var dictionaryContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                sectionHeader(
                    eyebrow: viewModel.selectedSection.shortTitle.uppercased(),
                    title: "Dictionary",
                    subtitle: viewModel.selectedSection.subtitle,
                    accent: viewModel.selectedSection.accent
                ) {
                    EmptyView()
                }

                dictionaryOverviewCard
                dictionaryEditorCard
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var styleContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                sectionHeader(
                    eyebrow: viewModel.selectedSection.shortTitle.uppercased(),
                    title: "Style",
                    subtitle: viewModel.selectedSection.subtitle,
                    accent: viewModel.selectedSection.accent
                ) {
                    EmptyView()
                }

                styleOverviewCard

                LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                    styleCategoriesCard
                    styleMemoryCard
                }

                styleProfilesCard
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var settingsSheet: some View {
        SettingsWindowView()
            .environmentObject(viewModel)
            .preferredColorScheme(viewModel.appearanceMode.preferredColorScheme)
            .applyWindowChrome()
            .frame(minWidth: 940, minHeight: 700)
    }

    private var actionItemsSheet: some View {
        ZStack {
            ambientBackground

            VStack(alignment: .leading, spacing: 18) {
                Text("Action Items Preview")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundStyle(VerbatimPalette.ink)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Structured JSON")
                        .font(.headline)

                    ScrollView {
                        Text(viewModel.pendingActionItemsJSON ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180)
                    .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Rendered text")
                        .font(.headline)

                    ScrollView {
                        Text(viewModel.pendingActionItemsRenderedText ?? "")
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 140)
                    .applyInsetWellStyle(cornerRadius: 20, padding: 16)
                }

                HStack(spacing: 10) {
                    Button("Insert Rendered Text") {
                        viewModel.confirmActionItemsPreviewInsertion()
                    }
                    .applyGlassButtonStyle(prominent: true)

                    Button("Close") {
                        viewModel.dismissActionItemsPreview()
                    }
                    .applyGlassButtonStyle()
                }
            }
            .frame(minWidth: 680, minHeight: 560)
            .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 24)
            .padding(26)
        }
    }

    private var workspaceHeaderActions: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(viewModel.promptProfiles) { profile in
                    Button(profile.name) {
                        viewModel.runManualReformat(profileID: profile.id)
                    }
                    .disabled(viewModel.transcript == nil || !profile.enabled || viewModel.isBusy)
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
            .disabled(!hasTranscriptText)

            Button {
                viewModel.clearTranscript()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .applyGlassButtonStyle()
            .disabled(!hasTranscriptText)
        }
    }

    private var workspaceHeroCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hold to dictate. Let Verbatim shape the rest.")
                        .font(.system(size: 40, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Record from your hotkey, route through the active speech stack, and keep the review flow calm enough to focus on the words.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 18)

                VerbatimBrandMark(size: 86)
                    .padding(18)
                    .applyInsetWellStyle(cornerRadius: 28, padding: 16)
            }

            HStack(spacing: 12) {
                Button(action: handlePrimaryAction) {
                    Label(viewModel.primaryButtonTitle, systemImage: primaryButtonSymbol)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .applyGlassButtonStyle(prominent: true)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!viewModel.canToggleRecording)

                VStack(alignment: .leading, spacing: 8) {
                    Label(stateLabel, systemImage: statusSymbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)
                        .applyStatusBadgeEffect()

                    Text(activeEngineSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(AppSectionAccent.cobalt.tint)

                    Text("Transcript")
                        .font(.system(size: 34, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)

                    if let warning = viewModel.lastErrorSummary,
                       !warning.isEmpty,
                       viewModel.selectedTranscriptViewMode == .formatted {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    if viewModel.shouldShowTranscriptTabs {
                        Picker("Transcript view", selection: $viewModel.selectedTranscriptViewMode) {
                            ForEach(TranscriptViewMode.allCases) { mode in
                                Text(mode == .raw ? "Raw" : "Formatted").tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .disabled(viewModel.transcript == nil || viewModel.formattedOutput == nil)
                    }

                    Text("\(wordCount) words")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                        .applyStatusBadgeEffect()
                }
            }

            ScrollView(showsIndicators: false) {
                Text(activeTranscriptText)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(activeTranscriptText.contains("Your transcript will appear here") ? .secondary : VerbatimPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
            .frame(minHeight: 360)
            .applyInsetWellStyle(cornerRadius: 24, padding: 18)
        }
    }

    private var dictionaryOverviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Words Verbatim should never miss.")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Use dictionary entries for names, firms, places, and repeat terminology. These mappings feed cleanup and model routing without hiding them in settings.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer(minLength: 16)

                VerbatimBrandMark(size: 72)
                    .padding(16)
                    .applyInsetWellStyle(cornerRadius: 26, padding: 14)
            }

            if viewModel.refineSettings.glossary.isEmpty {
                Text("No dictionary entries yet. Add lines below using `from=>to` format.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            } else {
                LazyVGrid(columns: dictionaryColumns, alignment: .leading, spacing: 10) {
                    ForEach(viewModel.refineSettings.glossary) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.from)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(VerbatimPalette.ink)
                            Text(entry.to)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(VerbatimPalette.mutedInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .applyInsetWellStyle(cornerRadius: 18, padding: 12)
                    }
                }
            }
        }
    }

    private var dictionaryEditorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Edit Dictionary",
                subtitle: "One mapping per line. Example: `Screed=>SCREED` or `Eulogio=>Eulogio`."
            )

            TextField("from=>to, one per line", text: glossaryMappingsBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(8...16)
                .font(.system(.body, design: .rounded))

            Text("These replacements are applied case-insensitively during cleanup.")
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)
        }
    }

    private var styleOverviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tune the way cleanup sounds.")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Style controls stay separate from model settings now. Use this page to decide when refinement applies and which prompt profiles stay available.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer(minLength: 16)

                Label("Preview before insert", systemImage: viewModel.refineSettings.previewBeforeInsert ? "eye" : "eye.slash")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)
                    .applyStatusBadgeEffect()
            }
        }
    }

    private var styleCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Where Refinement Runs",
                subtitle: "Choose the app contexts that should receive cleanup and tone-shaping."
            )

            LazyVGrid(columns: styleColumns, alignment: .leading, spacing: 12) {
                ForEach(StyleCategory.allCases) { category in
                    Toggle(isOn: refineEnabledBinding(for: category)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(styleCategorySubtitle(for: category))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(VerbatimPalette.mutedInk)
                        }
                    }
                    .toggleStyle(.switch)
                    .applyInsetWellStyle(cornerRadius: 20, padding: 14)
                }
            }

            Toggle("Preview before clipboard insert", isOn: $viewModel.refineSettings.previewBeforeInsert)
        }
    }

    private var styleMemoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Context Memory",
                subtitle: "Keep reminders and recurring context close to the style layer."
            )

            TextField("One line per memory item", text: sessionMemoryBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(6...12)
        }
    }

    private var styleProfilesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading(
                title: "Prompt Profiles",
                subtitle: "Enable the cleanup profiles you want available from Home."
            )

            HStack {
                Text("Available profiles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VerbatimPalette.mutedInk)

                Spacer()

                Button("Reload profiles", systemImage: "arrow.clockwise") {
                    viewModel.refreshPromptProfiles()
                }
                .applyGlassButtonStyle()
                .disabled(isBusy)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.promptProfiles) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { profile.enabled },
                        set: { enabled in
                            viewModel.setPromptProfileEnabled(profile.id, enabled: enabled)
                        }
                    ))
                    .applyInsetWellStyle(cornerRadius: 18, padding: 12)
                }
            }
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
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
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

            Text(viewModel.hotkeyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.hotkeyPermissionGranted ? VerbatimPalette.mutedInk : Color.orange)
        }
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeading(
                title: "Accessibility Permission",
                subtitle: "The global hotkey and insertion flows need Accessibility access."
            )

            Text("Grant permission in System Settings > Privacy & Security > Accessibility.")
                .font(.body)
                .foregroundStyle(VerbatimPalette.ink)
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
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
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
        .applyLiquidCardStyle(cornerRadius: 28, tone: .cream, padding: 22)
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
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
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
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
    }

    private func sectionHeader<Actions: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        accent: AppSectionAccent,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(accent.tint)

                Text(title)
                    .font(.system(size: 38, weight: .medium, design: .serif))
                    .foregroundStyle(VerbatimPalette.ink)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
            }

            Spacer(minLength: 16)

            actions()
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

    private var actionItemsPreviewBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingActionItemsJSON != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissActionItemsPreview()
                }
            }
        )
    }

    private var sessionMemoryBinding: Binding<String> {
        Binding(
            get: { viewModel.refineSettings.sessionMemory.joined(separator: "\n") },
            set: { value in
                viewModel.refineSettings.sessionMemory = value
                    .components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var glossaryMappingsBinding: Binding<String> {
        Binding(
            get: {
                viewModel.refineSettings.glossary
                    .map { "\($0.from)=>\($0.to)" }
                    .joined(separator: "\n")
            },
            set: { value in
                let parsed: [GlossaryEntry] = value
                    .components(separatedBy: CharacterSet.newlines)
                    .compactMap { line in
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return nil }
                        let parts = trimmed.components(separatedBy: "=>")
                        guard parts.count == 2 else { return nil }
                        let from = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let to = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !from.isEmpty, !to.isEmpty else { return nil }
                        return GlossaryEntry(from: from, to: to)
                    }
                viewModel.refineSettings.glossary = parsed
            }
        )
    }

    private func refineEnabledBinding(for category: StyleCategory) -> Binding<Bool> {
        Binding(
            get: { viewModel.refineSettings.isEnabled(for: category) },
            set: { enabled in
                viewModel.refineSettings.setEnabled(enabled, for: category)
            }
        )
    }

    private func styleCategorySubtitle(for category: StyleCategory) -> String {
        switch category {
        case .work:
            return "Docs, proposals, and internal writing."
        case .email:
            return "Mail and follow-ups."
        case .personal:
            return "Texts, chats, and informal notes."
        case .other:
            return "Fallback for everything uncategorized."
        }
    }

    private var settingsColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 18, alignment: .top)]
    }

    private var dictionaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10, alignment: .top)]
    }

    private var styleColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12, alignment: .top)]
    }

    private var activeEngineSummary: String {
        let transMode = viewModel.transcriptionMode == .remote ? "Remote STT" : "Local STT"
        let logicMode = viewModel.logicMode == .remote ? "Remote logic" : "Local logic"
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
            if let deterministic = viewModel.deterministicResult?.text, !deterministic.isEmpty {
                return deterministic
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

    private var ambientBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.12, blue: 0.17),
                        Color(red: 0.14, green: 0.18, blue: 0.25),
                        Color(red: 0.09, green: 0.11, blue: 0.16)
                    ]
                    : [
                        Color(red: 0.94, green: 0.96, blue: 0.99),
                        Color(red: 0.86, green: 0.90, blue: 0.96),
                        Color(red: 0.96, green: 0.97, blue: 0.99)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.58))
                .frame(width: 520, height: 520)
                .blur(radius: 180)
                .offset(x: -220, y: -250)

            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.43, green: 0.56, blue: 0.88).opacity(0.22)
                        : Color(red: 0.72, green: 0.82, blue: 1.0).opacity(0.26)
                )
                .frame(width: 420, height: 420)
                .blur(radius: 165)
                .offset(x: 300, y: 220)

            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.96, green: 0.80, blue: 0.45).opacity(0.08)
                        : Color(red: 1.0, green: 0.96, blue: 0.86).opacity(0.16)
                )
                .frame(width: 360, height: 360)
                .blur(radius: 150)
                .offset(x: 80, y: -180)
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

    private func openSettingsWindow() {
        isSettingsPresented = true
    }

    private func responseFormats(for model: ModelRegistryEntry) -> [String] {
        if model.id == "gpt-4o-transcribe-diarize" && viewModel.transcribeUseDiarization {
            return ["diarized_json"]
        }

        return model.allowedResponseFormats
    }
}
#if canImport(AppKit)
private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from nsView: NSView) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}
#else
private struct MainWindowConfigurator: View {
    var body: some View {
        EmptyView()
    }
}
#endif
