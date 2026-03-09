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

private struct StyleCategoryShowcase {
    let title: String
    let gradientColors: [Color]
    let glowColor: Color
    let appIcons: [(symbol: String, tint: Color)]
}

private enum DictionarySortMode {
    case alphabeticalAscending
    case alphabeticalDescending

    var systemImage: String {
        switch self {
        case .alphabeticalAscending:
            return "arrow.up.arrow.down"
        case .alphabeticalDescending:
            return "arrow.down.arrow.up"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .alphabeticalAscending:
            return "Sort A to Z"
        case .alphabeticalDescending:
            return "Sort Z to A"
        }
    }
}

private struct TranscriptHistoryItem: Identifiable {
    let id: String
    let record: TranscriptRecord
}

private struct TranscriptHistorySection: Identifiable {
    let id: String
    let date: Date
    let items: [TranscriptHistoryItem]
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsPresented = false
    @AppStorage("verbatim.style.selectedCategory") private var selectedStyleCategoryStorage = StyleCategory.personal.rawValue
    @State private var dictionarySearchText = ""
    @State private var isDictionarySearchVisible = false
    @State private var dictionarySortMode: DictionarySortMode = .alphabeticalAscending
    @State private var isAddingDictionaryEntry = false
    @State private var newDictionaryFromText = ""
    @State private var newDictionaryToText = ""

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
        .sheet(isPresented: $isAddingDictionaryEntry) {
            dictionaryAddSheet
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
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader(
                    eyebrow: viewModel.selectedSection.shortTitle.uppercased(),
                    title: homeTitle,
                    subtitle: "Review recent transcripts by day, copy the cleaned output, and prepare feedback without reopening the last session.",
                    accent: viewModel.selectedSection.accent
                ) {
                    EmptyView()
                }

                transcriptHistoryContent
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var dictionaryContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    Text("Dictionary")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Spacer(minLength: 16)

                    Button("Add new") {
                        openDictionaryAddFlow()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.96))
                    )
                    .foregroundStyle(Color.white)
                    .buttonStyle(.plain)
                }

                HStack(alignment: .bottom) {
                    Text("All")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Spacer(minLength: 16)

                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isDictionarySearchVisible.toggle()
                            }
                            if !isDictionarySearchVisible {
                                dictionarySearchText = ""
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Toggle search")

                        Button {
                            dictionarySortMode = dictionarySortMode == .alphabeticalAscending
                                ? .alphabeticalDescending
                                : .alphabeticalAscending
                        } label: {
                            Image(systemName: dictionarySortMode.systemImage)
                        }
                        .accessibilityLabel(dictionarySortMode.accessibilityLabel)

                        Button {
                            resetDictionaryControls()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Reset dictionary filters")
                    }
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(VerbatimPalette.mutedInk)
                    .buttonStyle(.plain)
                }

                if isDictionarySearchVisible {
                    TextField("Search dictionary", text: $dictionarySearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .frame(maxWidth: 360)
                }

                dictionaryListCard
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var styleContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Style")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)

                styleCategoryTabs
                styleCategoryHeroCard

                LazyVGrid(columns: stylePresetColumns, alignment: .leading, spacing: 18) {
                    ForEach(selectedStyleCategory.availablePresets) { preset in
                        stylePresetCard(for: preset)
                    }
                }

                styleCategorySettingsCard
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    private var transcriptHistoryContent: some View {
        let sections = transcriptHistorySections

        return VStack(alignment: .leading, spacing: 26) {
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No transcripts yet")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text("Use the testing tools in Settings to record, reformat, and review transcripts. Finished sessions will appear here automatically.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)

                    Button("Open testing tools") {
                        openSettingsWindow()
                    }
                    .applyGlassButtonStyle(prominent: true)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 24)
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let relativeLabel = relativeHistoryLabel(for: section.date) {
                            Text(relativeLabel)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(VerbatimPalette.mutedInk)
                        }

                        Text(historyDateTitle(for: section.date))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(VerbatimPalette.ink.opacity(0.72))

                        transcriptHistoryCard(for: section)
                    }
                }
            }
        }
    }

    private var settingsSheet: some View {
        SettingsWindowView()
            .environmentObject(viewModel)
            .preferredColorScheme(viewModel.appearanceMode.preferredColorScheme)
            .applyWindowChrome()
            .frame(minWidth: 940, minHeight: 700)
    }

    private var dictionaryAddSheet: some View {
        ZStack {
            ambientBackground

            VStack(alignment: .leading, spacing: 18) {
                Text("Add Dictionary Entry")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundStyle(VerbatimPalette.ink)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What Verbatim hears")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    TextField("Example: screed", text: $newDictionaryFromText)
                        .textFieldStyle(.roundedBorder)

                    Text("Correct output")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    TextField("Example: Screed", text: $newDictionaryToText)
                        .textFieldStyle(.roundedBorder)

                    Text("Use the exact term you want preserved during cleanup and formatting.")
                        .font(.caption)
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                HStack(spacing: 10) {
                    Button("Save Entry") {
                        addDictionaryEntry()
                    }
                    .applyGlassButtonStyle(prominent: true)
                    .disabled(trimmedNewDictionaryFromText.isEmpty || trimmedNewDictionaryToText.isEmpty)

                    Button("Cancel") {
                        closeDictionaryAddFlow()
                    }
                    .applyGlassButtonStyle()
                }
            }
            .frame(minWidth: 520)
            .applyLiquidCardStyle(cornerRadius: 30, tone: .frost, padding: 24)
            .padding(26)
        }
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

    private func transcriptHistoryCard(for section: TranscriptHistorySection) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                transcriptHistoryRow(for: item.record)

                if index < section.items.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func transcriptHistoryRow(for record: TranscriptRecord) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text(historyTimeLabel(for: record.createdAt))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink.opacity(0.78))
                .frame(width: 116, alignment: .leading)

            Text(viewModel.preferredTranscriptText(for: record))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button {
                    viewModel.copyTranscriptRecord(record)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy transcript")

                Button {
                    viewModel.copyTranscriptFeedbackPacket(record)
                } label: {
                    Image(systemName: "flag")
                }
                .help("Send feedback")

                Menu {
                    Button("Copy transcript") {
                        viewModel.copyTranscriptRecord(record)
                    }

                    Button("Copy raw transcript") {
                        viewModel.copyRawTranscriptRecord(record)
                    }

                    Button("Copy feedback packet") {
                        viewModel.copyTranscriptFeedbackPacket(record)
                    }

                    Divider()

                    Button("Open testing tools") {
                        openSettingsWindow()
                    }
                } label: {
                    Image(systemName: "ellipsis.vertical")
                }
                .help("More actions")
            }
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(VerbatimPalette.ink.opacity(0.78))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
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

    private var dictionaryListCard: some View {
        let entries = filteredDictionaryEntries

        return VStack(spacing: 0) {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(dictionarySearchText.isEmpty ? "No dictionary entries yet." : "No dictionary matches.")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(dictionarySearchText.isEmpty
                        ? "Add names, firms, places, and repeat terminology so Verbatim preserves them during cleanup."
                        : "Try another search term or reset the filters.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                .padding(28)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    dictionaryRow(for: entry)

                    if index < entries.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func dictionaryRow(for entry: GlossaryEntry) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dictionaryDisplayText(for: entry))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)

                if dictionarySecondaryText(for: entry) != nil {
                    Text(dictionarySecondaryText(for: entry) ?? "")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var styleCategoryTabs: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 34) {
                ForEach(StyleCategory.allCases) { category in
                    Button {
                        selectedStyleCategoryStorage = category.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(styleCategoryNavigationTitle(for: category))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(category == selectedStyleCategory ? VerbatimPalette.ink : VerbatimPalette.mutedInk)

                            Rectangle()
                                .fill(category == selectedStyleCategory ? VerbatimPalette.ink : Color.clear)
                                .frame(height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
                .offset(y: -1)
        }
    }

    private var styleCategoryHeroCard: some View {
        let showcase = styleCategoryShowcase(for: selectedStyleCategory)

        return ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: showcase.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(showcase.glowColor.opacity(0.36))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 180, y: 40)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(showcase.title)
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.96))

                    Text("Style formatting only applies in English. More languages coming soon.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                }

                Spacer(minLength: 16)

                HStack(spacing: -12) {
                    ForEach(Array(showcase.appIcons.enumerated()), id: \.offset) { _, item in
                        styleHeroIcon(symbol: item.symbol, tint: item.tint)
                    }

                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .frame(width: 78, height: 78)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .frame(minHeight: 220)
    }

    private var styleCategorySettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                Toggle("Apply automatically in this category", isOn: refineEnabledBinding(for: selectedStyleCategory))

                Spacer(minLength: 12)

                Toggle("Preview before insert", isOn: $viewModel.refineSettings.previewBeforeInsert)
            }

            if selectedStyleCategory == .email {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email sign-off name")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    TextField("Your name for 'Best regards'", text: $viewModel.refineSettings.emailSignatureName)
                        .textFieldStyle(.roundedBorder)

                    Text("Email presets will always structure a greeting, body, and closing. If this is blank, the closing keeps 'Best regards,' without a name line.")
                        .font(.caption)
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }
            }
        }
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
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

            Toggle("Skip silent hotkey recordings", isOn: $viewModel.interactionSettings.silenceDetectionEnabled)
            Toggle("Lock target app at start", isOn: $viewModel.interactionSettings.lockTargetAtStart)

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

            Picker("Insertion mode", selection: $viewModel.interactionSettings.insertionMode) {
                ForEach(RecordingInsertionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Auto-paste after insert", isOn: $viewModel.interactionSettings.autoPasteAfterInsert)
                .disabled(viewModel.interactionSettings.insertionMode != .autoPasteWhenPossible)
            Toggle("Show permission warnings", isOn: $viewModel.interactionSettings.showPermissionWarnings)

            Text(viewModel.hotkeyStatusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.shouldShowPermissionWarning ? Color.orange : VerbatimPalette.mutedInk)
        }
        .applyLiquidCardStyle(cornerRadius: 28, tone: .frost, padding: 22)
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeading(
                title: "Accessibility Permission",
                subtitle: "Fn / Globe hotkeys and insertion need Accessibility access."
            )

            Text(viewModel.accessibilityPermissionStateDescription)
                .font(.body.weight(.semibold))
                .foregroundStyle(viewModel.shouldShowPermissionWarning ? Color.orange : VerbatimPalette.ink)

            Text("Prompt macOS for access, then enable Verbatim in System Settings > Privacy & Security > Accessibility.")
                .font(.body)
                .foregroundStyle(VerbatimPalette.ink)

            Text(viewModel.accessibilityPermissionHelpText)
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)

            Button("Prompt Accessibility Access") {
                viewModel.requestAccessibilityPermissionPrompt()
            }
            .applyGlassButtonStyle(prominent: true)
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

            Picker("Local engine", selection: $viewModel.selectedLocalEngineMode) {
                ForEach(LocalTranscriptionEngineMode.userFacingCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)

            Text(viewModel.selectedLocalEngineMode.subtitle)
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text("Apple On-Device is ready immediately. Choose WhisperKit for app-managed installs or Legacy Whisper for existing whisper.cpp models.")
                .font(.caption)
                .foregroundStyle(VerbatimPalette.mutedInk)
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
                            localModelRow(model)
                        }
                    }
                }
            }
        }
    }

    private func localModelRow(_ model: LocalTranscriptionModel) -> some View {
        let isSelected = viewModel.selectedLocalModel == model
        let isAvailable = viewModel.isLocalModelSelectable(model)
        let actionTitle = viewModel.localModelPrimaryActionTitle(model)
        let canRunPrimary = viewModel.canRunLocalModelPrimaryAction(model) && !isBusy
        let canRemove = viewModel.canRemoveLocalModel(model) && !isBusy
        let progressValue = viewModel.localModelProgressValue(model)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(model.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VerbatimPalette.mutedInk)
                }

                Spacer()

                Text(viewModel.localModelBadgeText(model))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isAvailable ? VerbatimPalette.ink : VerbatimPalette.mutedInk)
                    .applyStatusBadgeEffect()
            }

            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppSectionAccent.amber.tint : VerbatimPalette.mutedInk)

                Text(isSelected ? "Selected" : "Tap to choose")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isAvailable ? VerbatimPalette.ink : VerbatimPalette.mutedInk)

                Spacer()
            }

            if !viewModel.localModelNotes(model).isEmpty {
                Text(viewModel.localModelNotes(model))
                    .font(.caption)
                    .foregroundStyle(viewModel.localModelBadgeText(model) == "Retry" || !isAvailable ? Color.orange : VerbatimPalette.mutedInk)
            }

            if model.isWhisperModel {
                if let actionTitle {
                    HStack(spacing: 10) {
                        Button(actionTitle, systemImage: actionTitle == "Install" ? "shippingbox" : "arrow.down.circle") {
                            viewModel.performPrimaryWhisperAction(for: model)
                        }
                        .applyGlassButtonStyle(prominent: true)
                        .disabled(!canRunPrimary)

                        if canRemove {
                            Button("Remove", systemImage: "trash") {
                                viewModel.removeWhisperModel(model)
                            }
                            .applyGlassButtonStyle()
                        }
                    }
                } else if canRemove {
                    Button("Remove", systemImage: "trash") {
                        viewModel.removeWhisperModel(model)
                    }
                    .applyGlassButtonStyle()
                }

                switch viewModel.localWhisperInstallStateDescription(model) {
                case .progress(let label):
                    VStack(alignment: .leading, spacing: 6) {
                        if let progressValue {
                            ProgressView(value: progressValue)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(VerbatimPalette.mutedInk)
                    }
                case .none:
                    EmptyView()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? AppSectionAccent.amber.glow : Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? AppSectionAccent.amber.tint.opacity(0.70) : Color.white.opacity(0.24),
                            lineWidth: 1
                        )
                )
        )
        .opacity(isAvailable ? 1 : 0.68)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            guard !isBusy else { return }
            viewModel.selectLocalModel(model)
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

    private var filteredDictionaryEntries: [GlossaryEntry] {
        let query = dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = viewModel.dictionaryEntries.filter { entry in
            guard !query.isEmpty else { return true }
            return entry.from.lowercased().contains(query) || entry.to.lowercased().contains(query)
        }

        return filtered.sorted { lhs, rhs in
            let left = dictionaryDisplayText(for: lhs).localizedLowercase
            let right = dictionaryDisplayText(for: rhs).localizedLowercase

            switch dictionarySortMode {
            case .alphabeticalAscending:
                return left < right
            case .alphabeticalDescending:
                return left > right
            }
        }
    }

    private var trimmedNewDictionaryFromText: String {
        newDictionaryFromText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewDictionaryToText: String {
        newDictionaryToText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dictionaryDisplayText(for entry: GlossaryEntry) -> String {
        let corrected = entry.to.trimmingCharacters(in: .whitespacesAndNewlines)
        return corrected.isEmpty ? entry.from : corrected
    }

    private func dictionarySecondaryText(for entry: GlossaryEntry) -> String? {
        let heard = entry.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = entry.to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !corrected.isEmpty else { return nil }
        guard heard.caseInsensitiveCompare(corrected) != .orderedSame else { return nil }
        return "Heard as \(heard)"
    }

    private func openDictionaryAddFlow() {
        newDictionaryFromText = ""
        newDictionaryToText = ""
        isAddingDictionaryEntry = true
    }

    private func closeDictionaryAddFlow() {
        isAddingDictionaryEntry = false
        newDictionaryFromText = ""
        newDictionaryToText = ""
    }

    private func addDictionaryEntry() {
        let from = trimmedNewDictionaryFromText
        let to = trimmedNewDictionaryToText
        guard !from.isEmpty, !to.isEmpty else { return }

        let newEntry = GlossaryEntry(from: from, to: to)
        viewModel.upsertDictionaryEntry(from: newEntry.from, to: newEntry.to)
        closeDictionaryAddFlow()
    }

    private func resetDictionaryControls() {
        dictionarySearchText = ""
        isDictionarySearchVisible = false
        dictionarySortMode = .alphabeticalAscending
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
                viewModel.dictionaryEntries
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
                viewModel.replaceDictionaryEntries(parsed)
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

    private var selectedStyleCategory: StyleCategory {
        StyleCategory(rawValue: selectedStyleCategoryStorage) ?? .personal
    }

    private var stylePresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 18, alignment: .top)]
    }

    private func styleCategoryNavigationTitle(for category: StyleCategory) -> String {
        switch category {
        case .personal:
            return "Personal messages"
        case .work:
            return "Work messages"
        case .email:
            return "Email"
        case .other:
            return "Other"
        }
    }

    private func stylePresetCard(for preset: StylePreset) -> some View {
        let definition = selectedStyleCategory.presetDefinition(
            for: preset,
            emailSignatureName: viewModel.refineSettings.emailSignatureName
        )
        let isSelected = viewModel.refineSettings.preset(for: selectedStyleCategory) == preset

        return Button {
            viewModel.refineSettings.setPreset(preset, for: selectedStyleCategory)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stylePresetTitle(for: preset))
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .foregroundStyle(VerbatimPalette.ink)

                    Text(stylePresetFeatureLabel(for: selectedStyleCategory, preset: preset))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)

                stylePresetPreview(for: selectedStyleCategory, preset: preset)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 430, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isSelected ? AppSectionAccent.violet.tint.opacity(0.72) : Color.primary.opacity(0.10),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
            )
            .shadow(
                color: isSelected ? AppSectionAccent.violet.tint.opacity(0.10) : Color.black.opacity(0.02),
                radius: isSelected ? 18 : 10,
                x: 0,
                y: 10
            )
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppSectionAccent.violet.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(AppSectionAccent.violet.glow.opacity(0.18))
                        )
                        .padding(18)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(definition.title) preset")
    }

    private func stylePresetTitle(for preset: StylePreset) -> String {
        switch preset {
        case .veryCasual:
            return "very casual"
        default:
            return preset.title
        }
    }

    private func stylePresetFeatureLabel(for category: StyleCategory, preset: StylePreset) -> String {
        switch (category, preset) {
        case (.personal, .formal), (.work, .formal), (.email, .formal), (.other, .formal):
            return "Caps + Punctuation"
        case (.personal, .casual), (.work, .casual), (.email, .casual), (.other, .casual):
            return "Caps + Less punctuation"
        case (.personal, .veryCasual):
            return "No Caps + Less punctuation"
        case (.work, .enthusiastic), (.email, .enthusiastic), (.other, .enthusiastic):
            return "More expressive language"
        default:
            return preset.title
        }
    }

    private func styleCategoryShowcase(for category: StyleCategory) -> StyleCategoryShowcase {
        switch category {
        case .personal:
            return StyleCategoryShowcase(
                title: "This style applies in personal messengers",
                gradientColors: [
                    Color(red: 0.24, green: 0.34, blue: 0.42),
                    Color(red: 0.29, green: 0.16, blue: 0.11),
                    Color(red: 0.30, green: 0.38, blue: 0.24)
                ],
                glowColor: Color(red: 0.86, green: 0.70, blue: 0.97),
                appIcons: [
                    ("message.fill", Color.green),
                    ("phone.fill", Color(red: 0.30, green: 0.76, blue: 0.39)),
                    ("paperplane.fill", Color.blue),
                    ("bolt.horizontal.circle.fill", Color(red: 0.92, green: 0.38, blue: 0.67))
                ]
            )
        case .work:
            return StyleCategoryShowcase(
                title: "This style applies in workplace messengers",
                gradientColors: [
                    Color(red: 0.21, green: 0.36, blue: 0.46),
                    Color(red: 0.31, green: 0.16, blue: 0.10),
                    Color(red: 0.28, green: 0.36, blue: 0.24)
                ],
                glowColor: Color(red: 0.88, green: 0.58, blue: 0.90),
                appIcons: [
                    ("message.badge.fill", Color(red: 0.14, green: 0.71, blue: 0.54)),
                    ("person.2.fill", Color(red: 0.45, green: 0.48, blue: 0.91))
                ]
            )
        case .email:
            return StyleCategoryShowcase(
                title: "This style applies in all major email apps",
                gradientColors: [
                    Color(red: 0.23, green: 0.39, blue: 0.50),
                    Color(red: 0.34, green: 0.17, blue: 0.10),
                    Color(red: 0.31, green: 0.39, blue: 0.26)
                ],
                glowColor: Color(red: 0.93, green: 0.63, blue: 0.78),
                appIcons: [
                    ("envelope.badge.fill", Color.orange),
                    ("tray.full.fill", Color(red: 0.19, green: 0.20, blue: 0.24)),
                    ("envelope.open.fill", Color(red: 0.20, green: 0.57, blue: 0.92)),
                    ("paperplane.fill", Color(red: 0.28, green: 0.63, blue: 0.97))
                ]
            )
        case .other:
            return StyleCategoryShowcase(
                title: "This style applies in all other apps",
                gradientColors: [
                    Color(red: 0.24, green: 0.36, blue: 0.43),
                    Color(red: 0.23, green: 0.11, blue: 0.09),
                    Color(red: 0.35, green: 0.41, blue: 0.31)
                ],
                glowColor: Color(red: 0.79, green: 0.66, blue: 0.95),
                appIcons: [
                    ("checklist", Color(red: 0.25, green: 0.35, blue: 0.82)),
                    ("note.text", Color.white),
                    ("square.and.pencil", Color.yellow)
                ]
            )
        }
    }

    private func styleHeroIcon(symbol: String, tint: Color) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .frame(width: 78, height: 78)
            .overlay {
                Circle()
                    .fill(tint.opacity(0.94))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tint == .white ? Color.black.opacity(0.82) : Color.white)
                    }
            }
    }

    @ViewBuilder
    private func stylePresetPreview(for category: StyleCategory, preset: StylePreset) -> some View {
        switch category {
        case .personal:
            personalStylePreview(for: preset)
        case .work:
            workStylePreview(for: preset)
        case .email:
            emailStylePreview(for: preset)
        case .other:
            otherStylePreview(for: preset)
        }
    }

    private func personalStylePreview(for preset: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(personalPreviewText(for: preset))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppSectionAccent.violet.glow.opacity(0.08))
                )

            HStack {
                Spacer()

                Circle()
                    .fill(stylePreviewAccent(for: preset).opacity(0.95))
                    .frame(width: 74, height: 74)
                    .overlay {
                        Text("J")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
            }
        }
    }

    private func workStylePreview(for preset: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(stylePreviewAccent(for: preset).opacity(0.30))
                    .frame(width: 82, height: 82)
                    .overlay {
                        Text("J")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("John Doe 9:45 AM")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink.opacity(0.74))

                    Text(workPreviewText(for: preset))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VerbatimPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func emailStylePreview(for preset: StylePreset) -> some View {
        let name = viewModel.refineSettings.emailSignatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        let signoffName = name.isEmpty ? "Your Name" : name

        return VStack(alignment: .leading, spacing: 12) {
            Text("To: Alex Doe")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            Text(emailPreviewBody(for: preset))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Best regards,")
                Text(signoffName)
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(VerbatimPalette.ink)
        }
    }

    private func otherStylePreview(for preset: StylePreset) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permit response note")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.mutedInk)

            Text(otherPreviewText(for: preset))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(VerbatimPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppSectionAccent.violet.glow.opacity(0.08))
                )
        }
    }

    private func personalPreviewText(for preset: StylePreset) -> String {
        switch preset {
        case .formal:
            return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual:
            return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case .veryCasual:
            return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        case .enthusiastic:
            return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you!"
        }
    }

    private func workPreviewText(for preset: StylePreset) -> String {
        switch preset {
        case .formal:
            return "Hi, if you're free, let's chat about the project results."
        case .casual:
            return "Hey, if you're free let's chat about the project results"
        case .enthusiastic:
            return "Hey, if you're free, let's chat about the project results!"
        case .veryCasual:
            return "hey if you're free let's chat about the project results"
        }
    }

    private func emailPreviewBody(for preset: StylePreset) -> String {
        switch preset {
        case .formal:
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat."
        case .casual:
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat."
        case .enthusiastic:
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat!"
        case .veryCasual:
            return "hi alex,\n\nit was great talking with you today. looking forward to our next chat"
        }
    }

    private func otherPreviewText(for preset: StylePreset) -> String {
        switch preset {
        case .formal:
            return "Updated the permit response draft. It is ready for review."
        case .casual:
            return "updated the permit response draft ready for review"
        case .enthusiastic:
            return "Updated the permit response draft. Ready for review!"
        case .veryCasual:
            return "updated the permit response draft ready for review"
        }
    }

    private func stylePreviewAccent(for preset: StylePreset) -> Color {
        switch preset {
        case .formal:
            return Color(red: 0.84, green: 0.74, blue: 0.92)
        case .casual:
            return Color(red: 0.91, green: 0.64, blue: 0.87)
        case .enthusiastic, .veryCasual:
            return AppSectionAccent.violet.tint
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

    private var homeTitle: String {
        let explicitName = viewModel.refineSettings.emailSignatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitName.isEmpty {
            return "Welcome back, \(explicitName)"
        }

        let firstName = NSFullUserName()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first ?? ""

        if !firstName.isEmpty {
            return "Welcome back, \(firstName)"
        }

        return "Welcome back"
    }

    private var transcriptHistorySections: [TranscriptHistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: viewModel.transcriptHistory) { record in
            calendar.startOfDay(for: record.createdAt)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                let records = (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
                let items = records.enumerated().map { index, record in
                    TranscriptHistoryItem(
                        id: "\(day.timeIntervalSince1970)-\(Int(record.createdAt.timeIntervalSince1970))-\(index)",
                        record: record
                    )
                }
                return TranscriptHistorySection(
                    id: String(Int(day.timeIntervalSince1970)),
                    date: day,
                    items: items
                )
            }
    }

    private func relativeHistoryLabel(for date: Date) -> String? {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return "TODAY"
        }
        if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        }
        return nil
    }

    private func historyDateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        return formatter.string(from: date).uppercased()
    }

    private func historyTimeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
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
